import UIKit
import XCTest
@testable import LumenNotes

final class DomainTests: XCTestCase {
    func testCollapseHidesBlocksUntilNextPeerHeading() {
        let h1 = NoteBlock.heading("A", level: 1)
        var collapsed = h1
        collapsed.isCollapsed = true
        let body = NoteBlock.paragraph("hidden")
        let h2 = NoteBlock.heading("B", level: 2)
        let body2 = NoteBlock.paragraph("also hidden")
        let h1Again = NoteBlock.heading("C", level: 1)
        let visible = NoteBlock.paragraph("visible")

        let document = NoteDocument(version: 1, blocks: [collapsed, body, h2, body2, h1Again, visible])
        let hidden = document.hiddenBlockIDs()
        XCTAssertTrue(hidden.contains(body.id))
        XCTAssertTrue(hidden.contains(h2.id))
        XCTAssertTrue(hidden.contains(body2.id))
        XCTAssertFalse(hidden.contains(h1Again.id))
        XCTAssertFalse(hidden.contains(visible.id))
    }

    func testChecklistAndTableSearchText() {
        var document = NoteDocument.empty
        document.blocks = [
            .checklist([ChecklistItem(text: "买牛奶", isChecked: false)]),
            .table(TableData(rows: [["预算", "300"]]))
        ]
        XCTAssertTrue(document.searchableText.contains("买牛奶"))
        XCTAssertTrue(document.searchableText.contains("预算"))
    }

    func testTagExtraction() {
        let text = "今天开会 #设计 #工作 还有 #设计 重复"
        XCTAssertEqual(SearchService.extractTags(from: text), ["设计", "工作"])
    }

    func testTagExtractionIgnoresEscapedHash() {
        XCTAssertTrue(SearchService.extractTags(from: "C# 和 issue#42").isEmpty)
    }

    func testSmartFolderRuleChecklistAndDate() {
        var document = NoteDocument.empty
        document.blocks = [.checklist([ChecklistItem(text: "未完成", isChecked: false)])]
        let note = Note(title: "测试", document: document)
        let rule = SmartFolderRule(
            dateField: .created,
            dateWindow: .last7Days,
            checklist: .hasUnchecked
        )
        XCTAssertTrue(rule.matches(note))
        XCTAssertEqual(rule.predicateFormat, "created >= now-7d AND uncheckedChecklistCount > 0")
    }

    @MainActor
    func testRichTextRTFRoundTrip() {
        let font = UIFont.systemFont(ofSize: 17)
        let attributed = NSAttributedString(
            string: "高亮文本",
            attributes: [.font: font, .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.3)]
        )
        let data = RichTextCoding.rtfData(from: attributed)
        XCTAssertNotNil(data)
        let rich = RichText(plain: "高亮文本", rtf: data)
        let restored = RichTextCoding.attributedString(from: rich, font: font, color: .label)
        XCTAssertEqual(restored.string, "高亮文本")
    }

    func testTableNormalization() {
        var table = TableData(rows: [["a"], ["b", "c"]])
        table.normalize()
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table.rows[0].count, 2)
    }
}
