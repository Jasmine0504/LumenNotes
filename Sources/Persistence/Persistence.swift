import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    let isDegraded: Bool

    init(inMemory: Bool = false) {
        let schema = Schema([
            Note.self,
            Folder.self,
            Tag.self,
            SmartFolder.self,
            Attachment.self
        ])
        let configuration = ModelConfiguration(
            "LumenNotes",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            isDegraded = false
        } catch {
            // The app must still open if the store cannot be migrated. An
            // in-memory store lets the user read the failure and export notes
            // instead of staring at a crash on launch.
            let fallback = ModelConfiguration(
                "LumenNotes-Recovery",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true
            )
            container = try! ModelContainer(for: schema, configurations: [fallback])
            isDegraded = true
        }
    }

    func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Folder>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        let work = Folder(name: "工作", sortIndex: 0)
        let life = Folder(name: "生活", sortIndex: 1)
        let ideas = Folder(name: "灵感", sortIndex: 2)
        let reading = Folder(name: "阅读", sortIndex: 1, parent: life)
        for folder in [work, life, ideas, reading] { context.insert(folder) }

        let welcome = makeWelcomeNote()
        welcome.folder = work
        let checklist = makeChecklistNote()
        checklist.folder = work
        let design = makeDesignNote()
        design.folder = ideas
        let book = makeReadingNote()
        book.folder = reading
        for note in [welcome, checklist, design, book] { context.insert(note) }

        let tagDesign = Tag(name: "设计")
        let tagGlass = Tag(name: "液态玻璃")
        let tagReading = Tag(name: "阅读")
        for tag in [tagDesign, tagGlass, tagReading] { context.insert(tag) }
        design.tags = [tagDesign, tagGlass]
        book.tags = [tagReading]

        let rule = SmartFolderRule(
            name: "含核对清单且本周创建",
            dateField: .created,
            dateWindow: .thisWeek,
            checklist: .any
        )
        context.insert(SmartFolder(name: rule.name, rule: rule, symbolName: "checklist"))

        let rule2 = SmartFolderRule(name: "最近修改的附件", dateField: .updated, dateWindow: .last7Days, requiresAttachment: true)
        context.insert(SmartFolder(name: rule2.name, rule: rule2, symbolName: "paperclip"))

        try? context.save()
    }

    private func makeWelcomeNote() -> Note {
        var document = NoteDocument.empty
        document.blocks = [
            .heading("欢迎来到流明笔记", level: 1),
            .paragraph("这是一个把**字体**、**纸张**和**液态玻璃**放在一起的备忘录实验。正文永远是实色纸张，只有工具栏和控件浮在玻璃里。", style: .body),
            .heading("三步开始", level: 2),
            .checklist([
                ChecklistItem(text: "点右下角 + 新建一条备忘录", isChecked: false),
                ChecklistItem(text: "在设置里把字体换成 Georgia 22pt", isChecked: false),
                ChecklistItem(text: "试试 #标签 和 >> 关联另一条笔记", isChecked: false)
            ]),
            .paragraph("小提示：正文输入 ==高亮== 会被渲染成高亮标记；标题左侧的 V 可以折叠整段区域。", style: .highlight),
            .heading("一个简单的表格", level: 3),
            .table(TableData(rows: [["场景", "字体"], ["长文阅读", "New York"], ["代码片段", "SF Mono"]])),
            .paragraph("锁定的备忘录正文会用 AES-GCM 加密后再落盘，列表只显示一把锁。", style: .quote)
        ]
        return Note(title: "欢迎来到流明笔记", document: document)
    }

    private func makeChecklistNote() -> Note {
        var document = NoteDocument.empty
        document.blocks = [
            .heading("本周要做", level: 1),
            .checklist([
                ChecklistItem(text: "整理设计评审反馈", isChecked: true),
                ChecklistItem(text: "给字体面板补齐 12–32pt 步进", isChecked: false),
                ChecklistItem(text: "录一段 5 秒语音测试转写", isChecked: false)
            ]),
            .paragraph("智能文件夹「含核对清单且本周创建」会自动收走这条笔记。", style: .body)
        ]
        return Note(title: "本周要做", document: document)
    }

    private func makeDesignNote() -> Note {
        var document = NoteDocument.empty
        document.blocks = [
            .heading("玻璃与纸", level: 1),
            .paragraph("Liquid Glass 只属于控制层。内容层需要的是不透明、稳定、可长时间阅读的表面。", style: .body),
            .paragraph("==边界感== 是这个设计里最重要的东西：工具栏可以折射背景，正文不能。", style: .highlight),
            .heading("字体搭配", level: 2),
            .paragraph("标题用 New York，正文用 Georgia，标签用 SF Mono。切换字体后，已有文本即时重排。", style: .bullet),
            .paragraph("中文字体回退到 PingFang SC，细体用于辅助文本。", style: .bullet)
        ]
        return Note(title: "玻璃与纸", document: document)
    }

    private func makeReadingNote() -> Note {
        var document = NoteDocument.empty
        document.blocks = [
            .heading("正在读", level: 1),
            .checklist([
                ChecklistItem(text: "《The Design of Everyday Things》", isChecked: false),
                ChecklistItem(text: "《A Philosophy of Software Design》", isChecked: false)
            ]),
            .paragraph("读完后把摘录放进正文，并用手写画一张结构图。", style: .quote)
        ]
        return Note(title: "正在读", document: document)
    }
}
