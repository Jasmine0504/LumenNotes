import Foundation
import SwiftData

/// The root note aggregate. Rich content lives in `contentData` as a versioned
/// `NoteDocument` JSON blob; `plainText` is a denormalised search projection.
@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var contentData: Data
    var plainText: String
    var createdAt: Date
    var updatedAt: Date
    var isLocked: Bool
    /// True once the user has ever protected this note, even while it is
    /// temporarily unlocked. Used to re-lock on the next launch.
    var isProtected: Bool
    /// AES-GCM ciphertext of `contentData` while locked. The plaintext body is
    /// cleared while locked so Spotlight / list previews cannot leak it.
    var lockedContentData: Data?
    var fontOverrideData: Data?
    /// OCR of all drawings inside this note, regenerated when a drawing changes.
    var drawingSearchText: String
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.note)
    var attachments: [Attachment]
    @Relationship(inverse: \Tag.notes)
    var tags: [Tag]

    init(
        id: UUID = UUID(),
        title: String = "",
        document: NoteDocument = .empty,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        folder: Folder? = nil
    ) {
        self.id = id
        self.title = title
        self.contentData = (try? NoteDocument.encode(document)) ?? Data()
        self.plainText = document.searchableText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLocked = false
        self.isProtected = false
        self.lockedContentData = nil
        self.fontOverrideData = nil
        self.drawingSearchText = ""
        self.folder = folder
        self.attachments = []
        self.tags = []
    }

    var document: NoteDocument {
        get { (try? NoteDocument.decode(contentData)) ?? .empty }
        set {
            contentData = (try? NoteDocument.encode(newValue)) ?? Data()
            plainText = newValue.searchableText
            updatedAt = .now
        }
    }

    var fontOverride: NoteFontOverride? {
        get {
            guard let data = fontOverrideData else { return nil }
            return try? JSONDecoder().decode(NoteFontOverride.self, from: data)
        }
        set {
            fontOverrideData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = plainText
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine, !firstLine.isEmpty { return firstLine }
        return "新建备忘录"
    }

    var summary: String {
        if isLocked { return "已锁定 · 解锁后查看内容" }
        let text = plainText.replacingOccurrences(of: "\n", with: " ")
        return String(text.prefix(180))
    }

    func touch() {
        updatedAt = .now
    }
}

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var sortIndex: Int
    var parent: Folder?
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
    var children: [Folder]
    @Relationship(deleteRule: .nullify, inverse: \Note.folder)
    var notes: [Note]

    init(id: UUID = UUID(), name: String, sortIndex: Int = 0, parent: Folder? = nil) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.sortIndex = sortIndex
        self.parent = parent
        self.children = []
        self.notes = []
    }

    var depth: Int {
        var value = 0
        var cursor = parent
        while let current = cursor, value < 32 {
            value += 1
            cursor = current.parent
        }
        return value
    }
}

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var createdAt: Date
    var notes: [Note]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.notes = []
    }
}

@Model
final class SmartFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var ruleData: Data
    var createdAt: Date
    var symbolName: String

    init(id: UUID = UUID(), name: String, rule: SmartFolderRule, symbolName: String = "line.3.horizontal.decrease.circle") {
        self.id = id
        self.name = name
        self.ruleData = (try? JSONEncoder().encode(rule)) ?? Data()
        self.createdAt = .now
        self.symbolName = symbolName
    }

    var rule: SmartFolderRule {
        get { (try? JSONDecoder().decode(SmartFolderRule.self, from: ruleData)) ?? .empty }
        set { ruleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

enum AttachmentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case photo, pdf, scan, audio, link, map

    var symbolName: String {
        switch self {
        case .photo: "photo"
        case .pdf: "doc.richtext"
        case .scan: "doc.viewfinder"
        case .audio: "waveform"
        case .link: "link"
        case .map: "map"
        }
    }

    var displayName: String {
        switch self {
        case .photo: "照片"
        case .pdf: "PDF"
        case .scan: "扫描文稿"
        case .audio: "录音"
        case .link: "网页链接"
        case .map: "地点"
        }
    }
}

struct AttachmentMetadata: Codable, Hashable, Sendable {
    var linkURL: String?
    var linkTitle: String?
    var linkHost: String?
    var latitude: Double?
    var longitude: Double?
    var mapTitle: String?
    var durationSeconds: Double?
    var pageCount: Int?

    init(
        linkURL: String? = nil,
        linkTitle: String? = nil,
        linkHost: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        mapTitle: String? = nil,
        durationSeconds: Double? = nil,
        pageCount: Int? = nil
    ) {
        self.linkURL = linkURL
        self.linkTitle = linkTitle
        self.linkHost = linkHost
        self.latitude = latitude
        self.longitude = longitude
        self.mapTitle = mapTitle
        self.durationSeconds = durationSeconds
        self.pageCount = pageCount
    }
}

@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var fileName: String
    @Attribute(.externalStorage) var data: Data
    var ocrText: String
    var createdAt: Date
    var metadataData: Data
    /// Optional PencilKit annotation layer for PDF / scan attachments.
    var annotationData: Data?
    var note: Note?

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        fileName: String,
        data: Data,
        ocrText: String = "",
        metadata: AttachmentMetadata = .init(),
        annotationData: Data? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.data = data
        self.ocrText = ocrText
        self.createdAt = .now
        self.metadataData = (try? JSONEncoder().encode(metadata)) ?? Data()
        self.annotationData = annotationData
        self.note = nil
    }

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .pdf }
        set { kindRaw = newValue.rawValue }
    }

    var metadata: AttachmentMetadata {
        get { (try? JSONDecoder().decode(AttachmentMetadata.self, from: metadataData)) ?? .init() }
        set { metadataData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
