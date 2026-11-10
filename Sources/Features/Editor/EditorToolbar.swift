import SwiftUI

enum BlockStyleCommand {
    case heading(Int)
    case paragraph(ParagraphStyle)
}

enum InsertCommand {
    case checklist, table, drawing, photo, pdf, scan, link, map, internalLink
}

struct GlassMorphID: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

struct NoteEditorToolbar: View {
    @Bindable var richContext: RichTextEditingContext
    let isRecording: Bool
    var onStyle: (BlockStyleCommand) -> Void
    var onInsert: (InsertCommand) -> Void
    var onAudio: () -> Void
    var onDismissKeyboard: () -> Void

    @Namespace private var glassNamespace
    @State private var isInsertExpanded = false

    var body: some View {
        GlassGroup(spacing: 8) {
            VStack(spacing: 8) {
                if isInsertExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            insertButton(.checklist, "checklist", "核对清单")
                            insertButton(.table, "tablecells", "表格")
                            insertButton(.drawing, "scribble.variable", "速绘")
                            insertButton(.photo, "photo", "照片")
                            insertButton(.pdf, "doc.richtext", "PDF")
                            insertButton(.scan, "doc.viewfinder", "扫描")
                            insertButton(.link, "link", "链接")
                            insertButton(.map, "map", "地点")
                            insertButton(.internalLink, "arrow.turn.down.right", "关联笔记")
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxWidth: 420)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                    .modifier(GlassMorphID(id: "insert.options", namespace: glassNamespace))
                }

                HStack(spacing: 7) {
                    styleMenu
                    formatButton("bold", label: "加粗", active: richContext.isBold) {
                        richContext.toggleBold()
                    }
                    formatButton("italic", label: "斜体", active: richContext.isItalic) {
                        richContext.toggleItalic()
                    }
                    formatButton("highlighter", label: "高亮", active: richContext.isHighlighted) {
                        richContext.toggleHighlight()
                    }

                    GlassIconButton(
                        systemName: isInsertExpanded ? "xmark" : "plus",
                        label: isInsertExpanded ? "收起插入菜单" : "插入内容",
                        tint: isInsertExpanded ? LumenTheme.accent : .primary
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            isInsertExpanded.toggle()
                        }
                    }
                    .modifier(GlassMorphID(id: "insert.toggle", namespace: glassNamespace))

                    GlassIconButton(
                        systemName: isRecording ? "stop.circle.fill" : "mic.fill",
                        label: isRecording ? "停止录音" : "录音",
                        tint: isRecording ? .red : .primary
                    ) {
                        onAudio()
                    }

                    GlassIconButton(systemName: "keyboard.chevron.compact.down", label: "收起键盘") {
                        onDismissKeyboard()
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .frame(maxWidth: 520)
    }

    private var styleMenu: some View {
        Menu {
            Button("标题 1") { onStyle(.heading(1)) }
            Button("标题 2") { onStyle(.heading(2)) }
            Button("标题 3") { onStyle(.heading(3)) }
            Divider()
            Button("正文") { onStyle(.paragraph(.body)) }
            Button("项目符号") { onStyle(.paragraph(.bullet)) }
            Button("编号列表") { onStyle(.paragraph(.numbered)) }
            Button("引用") { onStyle(.paragraph(.quote)) }
            Button("高亮段落") { onStyle(.paragraph(.highlight)) }
        } label: {
            Image(systemName: "textformat")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .lumenGlass(in: Circle())
        .modifier(GlassMorphID(id: "style", namespace: glassNamespace))
        .accessibilityLabel("段落样式")
    }

    private func formatButton(_ systemName: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        GlassIconButton(
            systemName: systemName,
            label: label,
            tint: active ? LumenTheme.accent : .primary,
            isEnabled: richContext.hasFocus,
            action: action
        )
        .modifier(GlassMorphID(id: "format.\(systemName)", namespace: glassNamespace))
    }

    private func insertButton(_ command: InsertCommand, _ systemName: String, _ label: String) -> some View {
        GlassIconButton(systemName: systemName, label: label) {
            onInsert(command)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isInsertExpanded = false
            }
        }
        .modifier(GlassMorphID(id: "insert.\(label)", namespace: glassNamespace))
    }
}
