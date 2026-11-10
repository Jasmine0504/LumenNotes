import SwiftData
import SwiftUI

struct FolderBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query private var notes: [Note]

    let selection: UUID?
    let nilTitle: String
    let allowsManagement: Bool
    var onSelect: (Folder?) -> Void

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderParent: Folder?
    @State private var renameFolder: Folder?
    @State private var renameText = ""
    @State private var deleteFolder: Folder?

    private var flattened: [(folder: Folder, depth: Int)] {
        var result: [(folder: Folder, depth: Int)] = []
        func walk(_ parent: Folder?, depth: Int) {
            let children = folders
                .filter { $0.parent?.id == parent?.id }
                .sorted { $0.sortIndex == $1.sortIndex ? $0.name < $1.name : $0.sortIndex < $1.sortIndex }
            for folder in children {
                result.append((folder, depth))
                walk(folder, depth: depth + 1)
            }
        }
        walk(nil, depth: 0)
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Label(nilTitle, systemImage: nilTitle.contains("全部") ? "tray.full" : "tray")
                            Spacer()
                            if selection == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(LumenTheme.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("文件夹") {
                    if flattened.isEmpty {
                        Text("还没有文件夹。点击右上角 + 新建一个。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(flattened, id: \.folder.id) { entry in
                        folderRow(entry.folder, depth: entry.depth)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LumenBackground())
            .navigationTitle("文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if allowsManagement {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            newFolderParent = nil
                            newFolderName = ""
                            showNewFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("新建文件夹")
                    }
                }
            }
            .alert("新建文件夹", isPresented: $showNewFolder) {
                TextField("文件夹名称", text: $newFolderName)
                Button("取消", role: .cancel) {}
                Button("创建") { createFolder() }
            } message: {
                Text(newFolderParent.map { "将创建在「\($0.name)」中" } ?? "将创建在根目录")
            }
            .alert("重命名文件夹", isPresented: Binding(
                get: { renameFolder != nil },
                set: { if !$0 { renameFolder = nil } }
            )) {
                TextField("文件夹名称", text: $renameText)
                Button("取消", role: .cancel) { renameFolder = nil }
                Button("保存") { commitRename() }
            }
            .confirmationDialog(
                "删除文件夹？",
                isPresented: Binding(
                    get: { deleteFolder != nil },
                    set: { if !$0 { deleteFolder = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除文件夹", role: .destructive) { commitDelete() }
                Button("取消", role: .cancel) { deleteFolder = nil }
            } message: {
                Text("子文件夹和其中的备忘录不会删除，会移动到上一级。")
            }
        }
    }

    private func folderRow(_ folder: Folder, depth: Int) -> some View {
        Button {
            onSelect(folder)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: depth == 0 ? "folder" : "arrow.turn.down.right")
                    .foregroundStyle(LumenTheme.accent)
                    .frame(width: 20)
                Text(folder.name)
                    .foregroundStyle(.primary)
                Text("\(countNotes(in: folder))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if selection == folder.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(LumenTheme.accent)
                }
            }
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if allowsManagement {
                Button {
                    newFolderParent = folder
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Label("新建子文件夹", systemImage: "folder.badge.plus")
                }
                Button {
                    renameFolder = folder
                    renameText = folder.name
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteFolder = folder
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func countNotes(in folder: Folder) -> Int {
        var ids = Set<UUID>([folder.id])
        var changed = true
        while changed {
            changed = false
            for candidate in folders where candidate.parent != nil {
                if let parent = candidate.parent, ids.contains(parent.id), !ids.contains(candidate.id) {
                    ids.insert(candidate.id)
                    changed = true
                }
            }
        }
        return notes.filter { note in
            guard let noteFolder = note.folder else { return false }
            return ids.contains(noteFolder.id)
        }.count
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = Folder(
            name: trimmed,
            sortIndex: (folders.map(\.sortIndex).max() ?? 0) + 1,
            parent: newFolderParent
        )
        modelContext.insert(folder)
        try? modelContext.save()
        newFolderName = ""
        newFolderParent = nil
    }

    private func commitRename() {
        guard let folder = renameFolder else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { folder.name = trimmed }
        renameFolder = nil
        try? modelContext.save()
    }

    private func commitDelete() {
        guard let folder = deleteFolder else { return }
        let parent = folder.parent
        for child in folder.children { child.parent = parent }
        for note in folder.notes { note.folder = parent }
        modelContext.delete(folder)
        deleteFolder = nil
        try? modelContext.save()
    }
}
