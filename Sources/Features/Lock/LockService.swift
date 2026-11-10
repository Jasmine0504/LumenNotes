import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import Security
import SwiftData

enum LockError: LocalizedError {
    case keychain(OSStatus)
    case encryptFailed
    case decryptFailed
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .keychain: "无法读取本机加密密钥"
        case .encryptFailed: "加密失败，备忘录未锁定"
        case .decryptFailed: "解密失败，请重试"
        case .authenticationFailed: "身份验证未通过"
        }
    }
}

enum NoteCipher {
    private static let service = "com.lumen.notes.cipher"
    private static let account = "note-content-key"

    static func encrypt(_ data: Data) throws -> Data {
        let key = try key()
        guard let sealed = try? AES.GCM.seal(data, using: key), let combined = sealed.combined else {
            throw LockError.encryptFailed
        }
        return combined
    }

    static func decrypt(_ data: Data) throws -> Data {
        let key = try key()
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key) else {
            throw LockError.decryptFailed
        }
        return opened
    }

    private static func key() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        if status != errSecItemNotFound {
            throw LockError.keychain(status)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw LockError.keychain(randomStatus) }
        let newKey = Data(bytes)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: newKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw LockError.keychain(addStatus) }
        return SymmetricKey(data: newKey)
    }
}

@MainActor
@Observable
final class LockService {
    var autoLockSeconds: Double {
        didSet { defaults.set(autoLockSeconds, forKey: Self.autoLockKey) }
    }
    var lastUnlockAt: Date?
    var lastError: String?
    var protectedOpenIDs: Set<UUID> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var relockTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private static let autoLockKey = "lumen.lock.autolockSeconds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: Self.autoLockKey) as? Double, stored >= 0 {
            self.autoLockSeconds = stored
        } else {
            self.autoLockSeconds = 60
        }
    }

    func enforceLockedNotesOnLaunch(context: ModelContext) {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isProtected })
        guard let notes = try? context.fetch(descriptor) else { return }
        for note in notes where !note.isLocked {
            lock(note: note, context: context)
        }
        for note in notes where note.isLocked && note.lockedContentData != nil && !note.contentData.isEmpty {
            note.contentData = Data()
            note.plainText = ""
        }
        try? context.save()
    }

    func lock(note: Note, context: ModelContext) {
        guard !note.isLocked else { return }
        do {
            let encrypted = try NoteCipher.encrypt(note.contentData)
            note.lockedContentData = encrypted
            note.contentData = Data()
            note.plainText = ""
            note.isProtected = true
            note.isLocked = true
            note.touch()
            protectedOpenIDs.remove(note.id)
            relockTasks[note.id]?.cancel()
            relockTasks[note.id] = nil
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unlock(note: Note, context: ModelContext) async -> Bool {
        guard note.isLocked else { return true }
        guard await authenticate(reason: "解锁「\(note.displayTitle)」") else {
            lastError = "身份验证未通过"
            return false
        }
        guard let encrypted = note.lockedContentData else {
            lastError = "缺少加密正文"
            return false
        }
        do {
            let data = try NoteCipher.decrypt(encrypted)
            note.contentData = data
            let document = (try? NoteDocument.decode(data)) ?? .empty
            note.plainText = document.searchableText
            note.lockedContentData = nil
            note.isLocked = false
            note.touch()
            try context.save()
            lastUnlockAt = .now
            lastError = nil
            protectedOpenIDs.insert(note.id)
            scheduleAutoLock(note: note, context: context)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = "使用设备密码"
        var error: NSError?
        let policy: LAPolicy
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            policy = .deviceOwnerAuthentication
        } else {
            lastError = "此设备未设置 Face ID、Touch ID 或设备密码"
            return false
        }
        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func scheduleAutoLock(note: Note, context: ModelContext) {
        relockTasks[note.id]?.cancel()
        guard autoLockSeconds > 0 else { return }
        let interval = autoLockSeconds
        let noteID = note.id
        relockTasks[note.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.relockIfStillOpen(noteID: noteID, context: context)
        }
    }

    func relockIfStillOpen(noteID: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<Note>()
        guard let notes = try? context.fetch(descriptor),
              let note = notes.first(where: { $0.id == noteID }) else { return }
        guard !note.isLocked else { return }
        lock(note: note, context: context)
        lastUnlockAt = nil
    }

    func lockAllProtectedNotes(context: ModelContext) {
        for id in Array(protectedOpenIDs) {
            relockIfStillOpen(noteID: id, context: context)
        }
    }
}
