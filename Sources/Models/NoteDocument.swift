import Foundation

/// A block-based document. Blocks keep checklists, tables and drawings as
/// first-class values instead of trying to encode them into a single text view.
struct NoteDocument: Codable, Hashable, Sendable {
    var version: Int
    var blocks: [NoteBlock]

    static let currentVersion = 1

    static var empty: NoteDocument {
        NoteDocument(version: currentVersion, blocks: [.paragraph()])
    }

    var searchableText: String {
        blocks.map(\.searchText).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var isEmpty: Bool {
        blocks.allSatisfy { $0.isEffectivelyEmpty }
    }

    /// Blocks hidden by a collapsed heading. A H1 hides everything until the
    /// next H1; a nested H2 hides until the next H2/H1.
    func hiddenBlockIDs() -> Set<UUID> {
        var hidden = Set<UUID>()
        var activeCollapsedLevel: Int?
        for block in blocks {
            if block.kind == .heading {
                let level = block.headingLevel ?? 1
                if let active = activeCollapsedLevel, level <= active {
                    activeCollapsedLevel = nil
                }
                if activeCollapsedLevel != nil {
                    hidden.insert(block.id)
                    continue
                }
                if block.isCollapsed == true {
                    activeCollapsedLevel = level
                }
            } else if activeCollapsedLevel != nil {
                hidden.insert(block.id)
            }
        }
        return hidden
    }

    mutating func insert(_ block: NoteBlock, after id: UUID?) {
        guard let id, let index = blocks.firstIndex(where: { $0.id == id }) else {
            blocks.append(block)
            return
        }
        blocks.insert(block, at: index + 1)
    }

    mutating func remove(id: UUID) {
        blocks.removeAll { $0.id == id }
        if blocks.isEmpty { blocks = [.paragraph()] }
    }

    static func encode(_ document: NoteDocument) throws -> Data {
        try JSONEncoder().encode(document)
    }

    static func decode(_ data: Data) throws -> NoteDocument {
        guard !data.isEmpty else { return .empty }
        return try JSONDecoder().decode(NoteDocument.self, from: data)
    }
}

enum BlockKind: String, Codable, Hashable, Sendable {
    case heading
    case paragraph
    case checklist
    case table
    case drawing
    case attachment
}

enum ParagraphStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case body
    case bullet
    case numbered
    case quote
    case highlight

    var symbolName: String {
        switch self {
        case .body: "text.alignleft"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .quote: "text.quote"
        case .highlight: "highlighter"
        }
    }
}

/// Rich text is persisted as RTF (canonical) plus a plain-text mirror used for
/// instant rendering, diffing and search. `UIViewRepresentable` keeps the
/// selection and typing attributes in a real `UITextView`.
struct RichText: Codable, Hashable, Sendable {
    var plain: String
    var rtf: Data?

    init(plain: String = "", rtf: Data? = nil) {
        self.plain = plain
        self.rtf = rtf
    }

    static func text(_ value: String) -> RichText {
        RichText(plain: value)
    }

    var isEmpty: Bool {
        plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var isChecked: Bool

    init(id: UUID = UUID(), text: String = "", isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

struct TableData: Codable, Hashable, Sendable {
    var rows: [[String]]

    init(rows: [[String]] = [["", ""], ["", ""]]) {
        self.rows = rows.isEmpty ? [["", ""]] : rows
    }

    var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    mutating func normalize() {
        let columns = max(1, columnCount)
        if rows.isEmpty { rows = [[""]] }
        for index in rows.indices {
            if rows[index].count < columns {
                rows[index].append(contentsOf: Array(repeating: "", count: columns - rows[index].count))
            }
        }
    }

    mutating func addRow() {
        normalize()
        rows.append(Array(repeating: "", count: max(1, columnCount)))
    }

    mutating func addColumn() {
        normalize()
        for index in rows.indices { rows[index].append("") }
    }

    mutating func removeRow(at index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    mutating func removeColumn(at index: Int) {
        guard columnCount > 1 else { return }
        for row in rows.indices where rows[row].indices.contains(index) {
            rows[row].remove(at: index)
        }
    }
}

struct NoteBlock: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var kind: BlockKind
    var text: RichText?
    var headingLevel: Int?
    var listStyle: ParagraphStyle?
    var isCollapsed: Bool?
    var checklistItems: [ChecklistItem]?
    var table: TableData?
    var attachmentID: UUID?
    var drawingData: Data?
    var drawingText: String?
    var internalLinkID: UUID?
    var internalLinkTitle: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: BlockKind,
        text: RichText? = nil,
        headingLevel: Int? = nil,
        listStyle: ParagraphStyle? = nil,
        isCollapsed: Bool? = nil,
        checklistItems: [ChecklistItem]? = nil,
        table: TableData? = nil,
        attachmentID: UUID? = nil,
        drawingData: Data? = nil,
        drawingText: String? = nil,
        internalLinkID: UUID? = nil,
        internalLinkTitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.headingLevel = headingLevel
        self.listStyle = listStyle
        self.isCollapsed = isCollapsed
        self.checklistItems = checklistItems
        self.table = table
        self.attachmentID = attachmentID
        self.drawingData = drawingData
        self.drawingText = drawingText
        self.internalLinkID = internalLinkID
        self.internalLinkTitle = internalLinkTitle
        self.createdAt = .now
    }

    static func paragraph(_ value: String = "", style: ParagraphStyle = .body) -> NoteBlock {
        NoteBlock(kind: .paragraph, text: .text(value), listStyle: style)
    }

    static func heading(_ value: String = "", level: Int) -> NoteBlock {
        NoteBlock(kind: .heading, text: .text(value), headingLevel: min(3, max(1, level)), isCollapsed: false)
    }

    static func checklist(_ items: [ChecklistItem] = [ChecklistItem()]) -> NoteBlock {
        NoteBlock(kind: .checklist, checklistItems: items)
    }

    static func table(_ table: TableData = TableData()) -> NoteBlock {
        NoteBlock(kind: .table, table: table)
    }

    static func drawing(_ data: Data? = nil) -> NoteBlock {
        NoteBlock(kind: .drawing, drawingData: data)
    }

    static func attachment(_ id: UUID) -> NoteBlock {
        NoteBlock(kind: .attachment, attachmentID: id)
    }

    static func internalLink(noteID: UUID, title: String) -> NoteBlock {
        NoteBlock(kind: .attachment, internalLinkID: noteID, internalLinkTitle: title)
    }

    var isHeading: Bool { kind == .heading }

    var searchText: String {
        var parts: [String] = []
        if let text, !text.plain.isEmpty { parts.append(text.plain) }
        if let checklistItems {
            parts.append(contentsOf: checklistItems.map(\.text))
        }
        if let table {
            parts.append(contentsOf: table.rows.flatMap { $0 })
        }
        if let drawingText, !drawingText.isEmpty { parts.append(drawingText) }
        if let internalLinkTitle, !internalLinkTitle.isEmpty { parts.append(internalLinkTitle) }
        return parts.joined(separator: " ")
    }

    var isEffectivelyEmpty: Bool {
        switch kind {
        case .heading, .paragraph:
            return text?.isEmpty ?? true
        case .checklist:
            return checklistItems?.allSatisfy { $0.text.isEmpty } ?? true
        case .table:
            return table?.rows.flatMap { $0 }.allSatisfy { $0.isEmpty } ?? true
        case .drawing:
            return drawingData == nil
        case .attachment:
            return attachmentID == nil && internalLinkID == nil
        }
    }
}
