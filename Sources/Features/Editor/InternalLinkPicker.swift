import SwiftData
import SwiftUI

struct InternalLinkPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    let currentNoteID: UUID
    var onSelect: (Note) -> Void

    @State private var searchText = ""

    private var candidates: [Note] {
        notes.filter { note in
            guard note.id != currentNoteID else { return false }
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            return SearchService.matches(note: note, query: searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(candidates, id: \.id) { note in
                Button {
                    onSelect(note)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(note.displayTitle)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if note.isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(note.isLocked ? "已锁定" : note.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LumenBackground())
            .navigationTitle("关联备忘录")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索要关联的备忘录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
