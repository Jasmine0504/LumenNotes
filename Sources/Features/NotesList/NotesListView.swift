import SwiftData
import SwiftUI

@MainActor
struct NotesListView: View {
    @Environment(FontTheme.self) private var theme
    @Environment(AppContainer.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Folder.sortIndex, order: .forward) private var folders: [Folder]
    @Query(sort: \SmartFolder.createdAt, order: .reverse) private var smartFolders: [SmartFolder]
    @Query(sort: \Tag.name, order: .forward) private var tags: [Tag]

    let onOpenNote: (UUID) -> Void
    let onNewNote: (Folder?) -> Void
    let onQuickNote: () -> Void
    let onOpenSettings: () -> Void

    @State private var searchText = ""
    @State private var activeFolderID: UUID?
    @State private var activeTag: String?
    @State private var activeSmartFolderID: UUID?
    @State private var showFolderBrowser = false
    @State private var showSmartFolderEditor = false
    @State private var movingNote: Note?
    @State private var deletingNote: Note?
    @State private var showDeleteAlert = false

    private var activeFolder: Folder? {
        guard let activeFolderID else { return nil }
        return folders.first { $0.id == activeFolderID }
    }

    private var activeSmartFolder: SmartFolder? {
        guard let activeSmartFolderID else { return nil }
        return smartFolders.first { $0.id == activeSmartFolderID }
    }

    private var filteredNotes: [Note] {
        var result = notes
        if let smart = activeSmartFolder {
            let predicate = smart.rule.predicate
            result = result.filter { predicate.evaluate(with: $0) }
        }
        if let folderID = activeFolderID {
            let ids = descendantFolderIDs(of: folderID)
            result = result.filter { note in
                guard let noteFolder = note.folder else { return false }
                return ids.contains(noteFolder.id)
            }
        }
        if let activeTag {
            result = result.filter { note in
                note.tags.contains { $0.name == activeTag }
            }
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = SearchService.filter(result, query: searchText)
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var visibleTags: [Tag] {
        Array(tags.filter { !$0.notes.isEmpty }.prefix(10))
    }

    var body: some View {
        ZStack {
            LumenBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    searchBar
                    if app.persistence.isDegraded {
                        degradedBanner
                    }
                    smartFolderSection
                    tagSection
                    activeFilterBanner
                    notesSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showFolderBrowser = true
                } label: {
                    Label(activeFolder?.name ?? "文件夹", systemImage: "folder")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showSmartFolderEditor = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("新建智能文件夹")

                Button(action: onOpenSettings) {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("字体设置")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            floatingActions
        }
        .sheet(isPresented: $showFolderBrowser) {
            FolderBrowserView(
                selection: activeFolderID,
                nilTitle: "全部备忘录",
                allowsManagement: true
            ) { folder in
                activeFolderID = folder?.id
                activeSmartFolderID = nil
            }
        }
        .sheet(isPresented: $showSmartFolderEditor) {
            SmartFolderEditor()
        }
        .sheet(isPresented: Binding(
            get: { movingNote != nil },
            set: { if !$0 { movingNote = nil } }
        )) {
            if let movingNote {
                FolderBrowserView(
                    selection: movingNote.folder?.id,
                    nilTitle: "无文件夹",
                    allowsManagement: false
                ) { folder in
                    movingNote.folder = folder
                    movingNote.touch()
                    try? modelContext.save()
                    self.movingNote = nil
                }
            }
        }
        .alert("删除这条备忘录？", isPresented: $showDeleteAlert, presenting: deletingNote) { note in
            Button("删除", role: .destructive) {
                modelContext.delete(note)
                try? modelContext.save()
                deletingNote = nil
            }
            Button("取消", role: .cancel) { deletingNote = nil }
        } message: { note in
            Text("「\(note.displayTitle)」及其附件会被删除，此操作不可撤销。")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("流明")
                    .font(theme.font(for: .title).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(theme.font(for: .caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(filteredNotes.count) 条")
                .font(theme.font(for: .caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .padding(.top, 2)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(
                "",
                text: $searchText,
                prompt: Text("搜索标题、正文、OCR、手写…")
                    .font(theme.font(for: .body))
                    .foregroundStyle(.secondary)
            )
            .font(theme.font(for: .body))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .lumenGlass(in: Capsule(), interactive: true)
    }

    private var degradedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("本地数据库无法打开，当前处于只读/内存恢复模式。")
                .font(theme.font(for: .caption))
                .foregroundStyle(.secondary)
        }
        .contentSurface(radius: 16, padding: 12)
    }

    private var smartFolderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("智能文件夹")
                    .font(theme.font(for: .body).weight(.semibold))
                Spacer()
                Button {
                    showSmartFolderEditor = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(theme.font(for: .caption))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LumenTheme.accent)
            }
            if smartFolders.isEmpty {
                Button {
                    showSmartFolderEditor = true
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("创建「含核对清单且本周创建」智能文件夹")
                            .font(theme.font(for: .caption))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentSurface(radius: 16, padding: 14)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(smartFolders, id: \.id) { smart in
                            smartFolderCard(smart)
                        }
                    }
                }
            }
        }
    }

    private func smartFolderCard(_ smart: SmartFolder) -> some View {
        let count = notes.filter { smart.rule.predicate.evaluate(with: $0) }.count
        let selected = activeSmartFolderID == smart.id
        return Button {
            withAnimation(.snappy) {
                activeSmartFolderID = selected ? nil : smart.id
                activeFolderID = nil
                activeTag = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: smart.symbolName)
                        .foregroundStyle(LumenTheme.accent)
                    Spacer()
                    Text("\(count)")
                        .font(theme.font(for: .caption).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(smart.name)
                    .font(theme.font(for: .body).weight(.semibold))
                    .lineLimit(1)
                Text(smart.rule.ruleDescription)
                    .font(theme.font(for: .caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 220, alignment: .leading)
            .contentSurface(radius: 18, padding: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? LumenTheme.accent : .clear, lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !visibleTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            activeTag = nil
                        } label: {
                            Text("全部")
                                .font(theme.font(for: .caption))
                                .foregroundStyle(activeTag == nil ? .white : LumenTheme.accent)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(activeTag == nil ? LumenTheme.accent : LumenTheme.accent.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        ForEach(visibleTags, id: \.id) { tag in
                            Button {
                                activeTag = activeTag == tag.name ? nil : tag.name
                            } label: {
                                TagChip(name: tag.name, isSelected: activeTag == tag.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var activeFilterBanner: some View {
        if let activeSmartFolder {
            filterBanner(title: activeSmartFolder.name, symbol: activeSmartFolder.symbolName) {
                activeSmartFolderID = nil
            }
        } else if let activeFolder {
            filterBanner(title: activeFolder.name, symbol: "folder") {
                activeFolderID = nil
            }
        } else if let activeTag {
            filterBanner(title: "#\(activeTag)", symbol: "number") {
                self.activeTag = nil
            }
        }
    }

    private func filterBanner(title: String, symbol: String, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(LumenTheme.accent)
            Text(title)
                .font(theme.font(for: .caption).weight(.semibold))
            Spacer()
            Button("清除") { withAnimation(.snappy) { clear() } }
                .font(theme.font(for: .caption))
                .foregroundStyle(.secondary)
        }
        .contentSurface(radius: 14, padding: 10)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("备忘录")
                    .font(theme.font(for: .body).weight(.semibold))
                Spacer()
                if !searchText.isEmpty {
                    Text("搜索：\(searchText)")
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if filteredNotes.isEmpty {
                emptyState
            } else {
                ForEach(filteredNotes, id: \.id) { note in
                    Button {
                        onOpenNote(note.id)
                    } label: {
                        NoteListRow(note: note)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            movingNote = note
                        } label: {
                            Label("移动到文件夹", systemImage: "folder")
                        }
                        Button(role: .destructive) {
                            deletingNote = note
                            showDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "这里还没有备忘录" : "没有找到匹配的备忘录")
                .font(theme.font(for: .body).weight(.semibold))
            Text(searchText.isEmpty ? "点击右下角新建，或从控制中心快速记录。" : "试试更短的关键词，搜索会覆盖 OCR 与手写文本。")
                .font(theme.font(for: .caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .contentSurface(radius: 22, padding: 20)
    }

    private var floatingActions: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                GlassIconButton(systemName: "bolt.fill", label: "快速备忘录") {
                    onQuickNote()
                }
                GlassCapsuleButton(
                    title: "新建备忘录",
                    systemName: "square.and.pencil",
                    prominent: true
                ) {
                    onNewNote(activeFolder)
                }
            }
            .padding(6)
        }
        .padding(.trailing, 18)
        .padding(.bottom, 16)
    }

    private func descendantFolderIDs(of root: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [root]
        var changed = true
        while changed {
            changed = false
            for folder in folders {
                if let parent = folder.parent, ids.contains(parent.id), !ids.contains(folder.id) {
                    ids.insert(folder.id)
                    changed = true
                }
            }
        }
        return ids
    }
}

@MainActor
struct NoteListRow: View {
    @Environment(FontTheme.self) private var theme
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.displayTitle)
                    .font(theme.font(for: .body).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(note.updatedAt.lumenRelative)
                    .font(theme.font(for: .caption))
                    .foregroundStyle(.secondary)
            }
            Text(note.isLocked ? "已锁定 · 解锁后查看内容" : note.summary)
                .font(theme.font(for: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if note.isLocked {
                    Label("已锁定", systemImage: "lock.fill")
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(note.attachments.prefix(3)), id: \.id) { attachment in
                        AttachmentGlyph(kind: attachment.kind)
                    }
                    ForEach(Array(note.tags.prefix(2)), id: \.id) { tag in
                        TagChip(name: tag.name)
                    }
                }
                Spacer()
            }
        }
        .contentSurface(radius: 20, padding: 15)
    }
}
