import SwiftUI
import UIKit

@MainActor
struct NoteBlockRow: View {
    @Environment(FontTheme.self) private var fontTheme

    @Binding var block: NoteBlock
    let attachments: [Attachment]
    let fontOverride: NoteFontOverride?
    let richContext: RichTextEditingContext
    let listNumber: Int?
    let canCollapse: Bool
    var onTyping: () -> Void
    var onFocus: () -> Void
    var onRequestInternalLink: () -> Void
    var onToggleCollapse: () -> Void
    var onDelete: () -> Void
    var onOpenDrawing: () -> Void
    var onPreviewAttachment: (Attachment) -> Void
    var onDeleteAttachment: (Attachment) -> Void
    var onOpenInternalLink: (UUID) -> Void

    var body: some View {
        Group {
            switch block.kind {
            case .heading:
                heading
            case .paragraph:
                paragraph
            case .checklist:
                checklist
            case .table:
                tableBlock
            case .drawing:
                drawing
            case .attachment:
                attachmentOrLink
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("删除此块", systemImage: "trash")
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 6) {
            if canCollapse {
                Button(action: onToggleCollapse) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .rotationEffect(.degrees(block.isCollapsed == true ? 0 : 90))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(block.isCollapsed == true ? "展开区域" : "折叠区域")
            } else {
                Color.clear.frame(width: 0, height: 34)
            }
            richEditor(
                font: fontTheme.headingUIFont(level: block.headingLevel ?? 1, override: fontOverride),
                placeholder: headingPlaceholder,
                color: .label
            )
            .padding(.top, (block.headingLevel ?? 1) == 1 ? 8 : 3)
        }
        .padding(.top, (block.headingLevel ?? 1) == 1 ? 12 : 4)
    }

    private var paragraph: some View {
        HStack(alignment: .top, spacing: 8) {
            switch block.listStyle ?? .body {
            case .bullet:
                Text("•")
                    .font(fontTheme.font(for: .body, override: fontOverride))
                    .foregroundStyle(LumenTheme.accent)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 1)
            case .numbered:
                Text("\(listNumber ?? 1).")
                    .font(fontTheme.font(for: .caption, override: fontOverride))
                    .foregroundStyle(LumenTheme.accent)
                    .frame(width: 22, alignment: .trailing)
                    .padding(.top, 4)
            case .quote:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LumenTheme.accent.opacity(0.55))
                    .frame(width: 3)
            case .highlight, .body:
                EmptyView()
            }

            richEditor(
                font: fontTheme.uiFont(for: .body, override: fontOverride),
                placeholder: paragraphPlaceholder,
                color: block.listStyle == .quote ? .secondaryLabel : .label
            )
            .padding(block.listStyle == .highlight ? 10 : 0)
            .background {
                if block.listStyle == .highlight {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LumenTheme.warm.opacity(0.20))
                }
            }
            .foregroundStyle(block.listStyle == .quote ? Color.secondary : Color.primary)
        }
        .padding(.vertical, 2)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array((block.checklistItems ?? []).enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        guard var items = block.checklistItems, items.indices.contains(index) else { return }
                        items[index].isChecked.toggle()
                        block.checklistItems = items
                        onTyping()
                    } label: {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.isChecked ? LumenTheme.accent : Color.secondary)
                            .frame(width: 26, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.isChecked ? "取消勾选" : "勾选")

                    TextField(
                        "待办事项",
                        text: itemBinding(index: index, keyPath: \.text),
                        axis: .vertical
                    )
                    .font(fontTheme.font(for: .body, override: fontOverride))
                    .strikethrough(item.isChecked, color: .secondary)
                    .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                    .textFieldStyle(.plain)
                    .padding(.top, 3)

                    Button {
                        guard var items = block.checklistItems, items.indices.contains(index) else { return }
                        items.remove(at: index)
                        block.checklistItems = items.isEmpty ? [ChecklistItem()] : items
                        onTyping()
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("删除待办事项")
                }
                .padding(.vertical, 3)
            }
            Button {
                block.checklistItems = (block.checklistItems ?? []) + [ChecklistItem()]
                onTyping()
            } label: {
                Label("添加项目", systemImage: "plus")
                    .font(fontTheme.font(for: .caption, override: fontOverride).weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(LumenTheme.accent)
            .padding(.top, 6)
        }
        .contentSurface(radius: 18, padding: 14)
    }

    private var tableBlock: some View {
        TableBlockView(
            table: Binding(
                get: { block.table ?? TableData() },
                set: { block.table = $0; onTyping() }
            ),
            fontOverride: fontOverride,
            onTyping: onTyping
        )
    }

    private var drawing: some View {
        Button(action: onOpenDrawing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("速绘", systemImage: "scribble.variable")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("PencilKit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let image = DrawingRenderer.image(from: block.drawingData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(height: 120)
                        .overlay {
                            Label("点击开始速绘", systemImage: "pencil.tip")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .contentSurface(radius: 18, padding: 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var attachmentOrLink: some View {
        if let linkID = block.internalLinkID {
            Button {
                onOpenInternalLink(linkID)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.title3)
                        .foregroundStyle(LumenTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(LumenTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(block.internalLinkTitle ?? "关联备忘录")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("内部链接 · 点击打开")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentSurface(radius: 16, padding: 12)
            }
            .buttonStyle(.plain)
        } else if let id = block.attachmentID, let attachment = attachments.first(where: { $0.id == id }) {
            AttachmentCard(
                attachment: attachment,
                onPreview: { onPreviewAttachment(attachment) },
                onDelete: { onDeleteAttachment(attachment) }
            )
        } else {
            HStack {
                Image(systemName: "paperclip.badge.ellipsis")
                Text("附件缺失")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .contentSurface(radius: 14, padding: 12)
        }
    }

    private func richEditor(font: UIFont, placeholder: String, color: UIColor) -> some View {
        ZStack(alignment: .topLeading) {
            if block.text?.isEmpty != false {
                Text(placeholder)
                    .font(Font(font))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .padding(.top, 1)
            }
            RichTextEditor(
                richText: Binding(
                    get: { block.text ?? .text("") },
                    set: { block.text = $0; onTyping() }
                ),
                font: font,
                textColor: color,
                placeholder: placeholder,
                context: richContext,
                onTyping: onTyping,
                onFocus: onFocus,
                onRequestInternalLink: onRequestInternalLink
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headingPlaceholder: String {
        switch block.headingLevel ?? 1 {
        case 1: "区域标题"
        case 2: "小标题"
        default: "次级标题"
        }
    }

    private var paragraphPlaceholder: String {
        switch block.listStyle ?? .body {
        case .bullet: "列表项"
        case .numbered: "编号项"
        case .quote: "引用"
        case .highlight: "高亮段落"
        case .body: "开始写…"
        }
    }

    private func itemBinding(index: Int, keyPath: WritableKeyPath<ChecklistItem, String>) -> Binding<String> {
        Binding(
            get: {
                guard let items = block.checklistItems, items.indices.contains(index) else { return "" }
                return items[index][keyPath: keyPath]
            },
            set: { value in
                guard var items = block.checklistItems, items.indices.contains(index) else { return }
                items[index][keyPath: keyPath] = value
                block.checklistItems = items
                onTyping()
            }
        )
    }
}

@MainActor
struct TableBlockView: View {
    @Environment(FontTheme.self) private var fontTheme
    @Binding var table: TableData
    let fontOverride: NoteFontOverride?
    var onTyping: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 1, verticalSpacing: 1) {
                    ForEach(table.rows.indices, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                                TextField("", text: cellBinding(row: rowIndex, column: columnIndex), axis: .vertical)
                                    .font(fontTheme.font(for: .body, override: fontOverride))
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .frame(minWidth: 112, minHeight: 40, alignment: .leading)
                                    .background(Color(uiColor: .tertiarySystemFill))
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: 14) {
                Button {
                    table.addRow()
                    onTyping()
                } label: {
                    Label("行", systemImage: "plus.rectangle")
                }
                Button {
                    table.addColumn()
                    onTyping()
                } label: {
                    Label("列", systemImage: "plus.rectangle.portrait")
                }
                Menu {
                    if table.rows.count > 1 {
                        Button("删除末行", role: .destructive) {
                            table.removeRow(at: table.rows.count - 1)
                            onTyping()
                        }
                    }
                    if table.columnCount > 1 {
                        Button("删除末列", role: .destructive) {
                            table.removeColumn(at: table.columnCount - 1)
                            onTyping()
                        }
                    }
                } label: {
                    Label("删除", systemImage: "ellipsis.circle")
                }
                Spacer()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(LumenTheme.accent)
        }
        .contentSurface(radius: 18, padding: 14)
        .onAppear { table.normalize() }
    }

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: {
                guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return "" }
                return table.rows[row][column]
            },
            set: { value in
                guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return }
                table.rows[row][column] = value
                onTyping()
            }
        )
    }
}
