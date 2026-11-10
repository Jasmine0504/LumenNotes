import AppIntents

struct LumenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "用 \(.applicationName) 新建备忘录",
                "在 \(.applicationName) 写一条备忘",
                "Create a note in \(.applicationName)"
            ],
            shortTitle: "新建备忘录",
            systemImageName: "square.and.pencil"
        )
    }
}
