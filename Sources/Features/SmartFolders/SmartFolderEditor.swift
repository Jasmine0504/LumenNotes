import SwiftData
import SwiftUI

struct SmartFolderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var name = "新建智能文件夹"
    @State private var useDate = false
    @State private var dateField: SmartDateField = .created
    @State private var dateWindow: SmartDateWindow = .thisWeek
    @State private var useChecklist = false
    @State private var checklist: ChecklistRequirement = .any
    @State private var useAttachment = false
    @State private var attachmentKind: AttachmentKind = .photo
    @State private var tagText = ""
    @State private var lockedFilter = 0

    private var tagNames: [String] {
        tagText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map { String($0).replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var rule: SmartFolderRule {
        SmartFolderRule(
            name: name,
            dateField: useDate ? dateField : nil,
            dateWindow: useDate ? dateWindow : nil,
            checklist: useChecklist ? checklist : nil,
            attachmentKind: useAttachment ? attachmentKind : nil,
            requiresAttachment: useAttachment,
            tagNames: tagNames,
            lockedOnly: lockedFilter == 0 ? nil : lockedFilter == 1
        )
    }

    private var matchCount: Int {
        let predicate = rule.predicate
        return notes.filter { predicate.evaluate(with: $0) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("智能文件夹名称", text: $name)
                }

                Section("日期") {
                    Toggle("按日期筛选", isOn: $useDate.animation())
                    if useDate {
                        Picker("字段", selection: $dateField) {
                            ForEach(SmartDateField.allCases, id: \.self) { field in
                                Text(field.displayName).tag(field)
                            }
                        }
                        Picker("范围", selection: $dateWindow) {
                            ForEach(SmartDateWindow.allCases, id: \.self) { window in
                                Text(window.displayName).tag(window)
                            }
                        }
                    }
                }

                Section("核对清单") {
                    Toggle("按核对清单筛选", isOn: $useChecklist.animation())
                    if useChecklist {
                        Picker("条件", selection: $checklist) {
                            ForEach(ChecklistRequirement.allCases, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                    }
                }

                Section("附件") {
                    Toggle("必须含附件", isOn: $useAttachment.animation())
                    if useAttachment {
                        Picker("附件类型", selection: $attachmentKind) {
                            ForEach(AttachmentKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                    }
                }

                Section("标签") {
                    TextField("用逗号分隔，例如：设计, 阅读", text: $tagText)
                }

                Section("锁定状态") {
                    Picker("锁定状态", selection: $lockedFilter) {
                        Text("不限").tag(0)
                        Text("已锁定").tag(1)
                        Text("未锁定").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Label("实时匹配", systemImage: "sparkle.magnifyingglass")
                        Spacer()
                        Text("\(matchCount) 条")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(LumenTheme.accent)
                    }
                    Text(rule.predicateFormat)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("预览")
                } footer: {
                    Text("SwiftData 无法可靠翻译关联条件，因此这里保留真实的 NSPredicate，并对已加载的备忘录实时求值。")
                }
            }
            .navigationTitle("智能文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let finalRule = SmartFolderRule(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名智能文件夹" : name,
                            dateField: rule.dateField,
                            dateWindow: rule.dateWindow,
                            checklist: rule.checklist,
                            attachmentKind: rule.attachmentKind,
                            requiresAttachment: rule.requiresAttachment,
                            tagNames: rule.tagNames,
                            lockedOnly: rule.lockedOnly
                        )
                        modelContext.insert(SmartFolder(name: finalRule.name, rule: finalRule))
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
