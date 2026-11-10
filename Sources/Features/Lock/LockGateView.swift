import SwiftUI
import SwiftData

@MainActor
struct LockGateView: View {
    @Environment(LockService.self) private var lockService
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    @State private var isAuthenticating = false
    @State private var didAttempt = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(LumenTheme.accent)
                .padding(26)
                .background(LumenTheme.accent.opacity(0.10), in: Circle())
            Text("「\(note.displayTitle)」已锁定")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("使用 Face ID、Touch ID、Optic ID 或设备密码解锁。正文以 AES-GCM 加密后存储在本机。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button {
                Task { await unlock() }
            } label: {
                Label(isAuthenticating ? "验证中…" : "解锁", systemImage: "faceid")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            if let error = lockService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LumenBackground())
        .task {
            guard !didAttempt else { return }
            didAttempt = true
            await unlock()
        }
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        _ = await lockService.unlock(note: note, context: modelContext)
    }
}
