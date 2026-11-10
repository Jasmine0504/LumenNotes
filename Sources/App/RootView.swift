import SwiftData
import SwiftUI

enum LumenRoute: Hashable {
    case note(UUID)
}

@MainActor
struct RootView: View {
    @Environment(AppContainer.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var path = NavigationPath()
    @State private var showFontSettings = false
    @State private var lastQuickCaptureRequest: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            NotesListView(
                onOpenNote: { id in
                    path.append(LumenRoute.note(id))
                },
                onNewNote: { folder in
                    createNote(folder: folder)
                },
                onQuickNote: {
                    createNote(folder: nil, quick: true)
                },
                onOpenSettings: {
                    showFontSettings = true
                }
            )
            .navigationDestination(for: LumenRoute.self) { route in
                switch route {
                case .note(let id):
                    if let note = note(id: id) {
                        NoteEditorView(note: note) { target in
                            path.append(LumenRoute.note(target))
                        }
                    } else {
                        ContentUnavailableView("备忘录不存在", systemImage: "note.text", description: Text("它可能已经被删除。"))
                    }
                }
            }
        }
        .sheet(isPresented: $showFontSettings) {
            FontSettingsView(note: nil)
                .environment(app.fontTheme)
        }
        .onOpenURL(perform: handleURL)
        .onContinueUserActivity("com.lumen.notes.capture") { activity in
            let text = activity.userInfo?["text"] as? String
            createNote(folder: nil, quick: true, initialText: text)
        }
        .onContinueUserActivity("com.lumen.notes.note") { activity in
            if let raw = activity.userInfo?["noteID"] as? String, let id = UUID(uuidString: raw) {
                path.append(LumenRoute.note(id))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumenQuickCapture)) { _ in
            createNote(folder: nil, quick: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                consumeSharedCapture()
            } else if phase == .background {
                Task { @MainActor in
                    // Give the editor one run-loop turn to flush its debounced
                    // document before the ciphertext snapshot is taken.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    app.lockService.lockAllProtectedNotes(context: modelContext)
                }
            }
        }
        .task {
            consumeSharedCapture()
        }
    }

    private func note(id: UUID) -> Note? {
        let descriptor = FetchDescriptor<Note>()
        guard let notes = try? modelContext.fetch(descriptor) else { return nil }
        return notes.first { $0.id == id }
    }

    @discardableResult
    private func createNote(folder: Folder?, quick: Bool = false, initialText: String? = nil) -> Note? {
        var document = NoteDocument.empty
        if let initialText, !initialText.isEmpty {
            document.blocks = [.paragraph(initialText)]
        }
        let note = Note(
            title: quick ? (initialText?.isEmpty == false ? String(initialText!.prefix(36)) : "快速备忘录") : "",
            document: document,
            folder: folder
        )
        modelContext.insert(note)
        try? modelContext.save()
        path.append(LumenRoute.note(note.id))
        return note
    }

    private func consumeSharedCapture() {
        guard let request = SharedCapture.consume() else { return }
        if lastQuickCaptureRequest == request.id { return }
        lastQuickCaptureRequest = request.id
        createNote(folder: nil, quick: true, initialText: request.initialText)
    }

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "lumen" else { return }
        switch url.host?.lowercased() {
        case "new":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let text = components?.queryItems?.first(where: { $0.name == "text" })?.value
            createNote(folder: nil, quick: true, initialText: text)
        case "note":
            if let id = UUID(uuidString: url.lastPathComponent) {
                path.append(LumenRoute.note(id))
            }
        default:
            break
        }
    }
}

extension Notification.Name {
    static let lumenQuickCapture = Notification.Name("com.lumen.notes.quickCapture")
}

struct LumenCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("快速备忘录") {
                NotificationCenter.default.post(name: .lumenQuickCapture, object: nil)
            }
            .keyboardShortcut("q", modifiers: [.function])
        }
    }
}
