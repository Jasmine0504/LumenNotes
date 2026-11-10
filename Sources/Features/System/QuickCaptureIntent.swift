import AppIntents
import Foundation

struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "新建备忘录"
    static var description = IntentDescription("立即打开流明笔记并新建一条备忘录。")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "初始文本")
    var text: String?

    init() {}

    init(text: String?) {
        self.text = text
    }

    func perform() async throws -> some IntentResult {
        SharedCapture.enqueue(text: text, source: "app-intent")
        return .result()
    }
}
