import Foundation

enum SmartDateField: String, Codable, CaseIterable, Hashable, Sendable {
    case created, updated

    var displayName: String {
        switch self {
        case .created: "创建时间"
        case .updated: "修改时间"
        }
    }
}

enum SmartDateWindow: String, Codable, CaseIterable, Hashable, Sendable {
    case today, thisWeek, last7Days, last30Days, olderThan30Days

    var displayName: String {
        switch self {
        case .today: "今天"
        case .thisWeek: "本周"
        case .last7Days: "最近 7 天"
        case .last30Days: "最近 30 天"
        case .olderThan30Days: "30 天以前"
        }
    }
}

enum ChecklistRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    case any, hasUnchecked, allChecked, none

    var displayName: String {
        switch self {
        case .any: "含核对清单"
        case .hasUnchecked: "含未完成项"
        case .allChecked: "全部已完成"
        case .none: "不含核对清单"
        }
    }
}

struct SmartFolderRule: Codable, Hashable, Sendable {
    var name: String
    var dateField: SmartDateField?
    var dateWindow: SmartDateWindow?
    var checklist: ChecklistRequirement?
    var attachmentKind: AttachmentKind?
    var requiresAttachment: Bool
    var tagNames: [String]
    var folderID: UUID?
    var lockedOnly: Bool?

    init(
        name: String = "新建智能文件夹",
        dateField: SmartDateField? = nil,
        dateWindow: SmartDateWindow? = nil,
        checklist: ChecklistRequirement? = nil,
        attachmentKind: AttachmentKind? = nil,
        requiresAttachment: Bool = false,
        tagNames: [String] = [],
        folderID: UUID? = nil,
        lockedOnly: Bool? = nil
    ) {
        self.name = name
        self.dateField = dateField
        self.dateWindow = dateWindow
        self.checklist = checklist
        self.attachmentKind = attachmentKind
        self.requiresAttachment = requiresAttachment
        self.tagNames = tagNames
        self.folderID = folderID
        self.lockedOnly = lockedOnly
    }

    static let empty = SmartFolderRule()

    var isActive: Bool {
        dateField != nil || dateWindow != nil || checklist != nil ||
        attachmentKind != nil || requiresAttachment || !tagNames.isEmpty ||
        folderID != nil || lockedOnly != nil
    }

    /// A genuine NSPredicate whose block evaluates the in-memory SwiftData
    /// object. SwiftData cannot translate relationship predicates reliably, so
    /// we do not push this into a FetchDescriptor; we evaluate it over the
    /// already-fetched notes. The same rule is also rendered as a readable
    /// predicate string in the condition builder.
    var predicate: NSPredicate {
        NSPredicate { object, _ in
            guard let note = object as? Note else { return false }
            return self.matches(note)
        }
    }

    var predicateFormat: String {
        var clauses: [String] = []
        if let dateField, let dateWindow {
            clauses.append("\(dateField.rawValue) \(dateWindow.predicateOperator)")
        }
        switch checklist {
        case .any: clauses.append("checklistCount > 0")
        case .hasUnchecked: clauses.append("uncheckedChecklistCount > 0")
        case .allChecked: clauses.append("checklistCount > 0 AND uncheckedChecklistCount == 0")
        case .none: clauses.append("checklistCount == 0")
        case nil: break
        }
        if requiresAttachment { clauses.append("attachments.@count > 0") }
        if let attachmentKind { clauses.append("ANY attachments.kindRaw == '\(attachmentKind.rawValue)'") }
        if !tagNames.isEmpty {
            let quoted = tagNames.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" }.joined(separator: ", ")
            clauses.append("ANY tags.name IN {\(quoted)}")
        }
        if folderID != nil { clauses.append("folder != nil") }
        if let lockedOnly { clauses.append("isLocked == \(lockedOnly)") }
        return clauses.isEmpty ? "TRUEPREDICATE" : clauses.joined(separator: " AND ")
    }

    var ruleDescription: String {
        var parts: [String] = []
        if let dateField, let dateWindow { parts.append("\(dateField.displayName)为\(dateWindow.displayName)") }
        if let checklist { parts.append(checklist.displayName) }
        if requiresAttachment { parts.append("含附件") }
        if let attachmentKind { parts.append("含\(attachmentKind.displayName)") }
        if !tagNames.isEmpty { parts.append("标签：\(tagNames.joined(separator: "、"))") }
        if folderID != nil { parts.append("位于指定文件夹") }
        if let lockedOnly { parts.append(lockedOnly ? "已锁定" : "未锁定") }
        return parts.isEmpty ? "全部备忘录" : parts.joined(separator: " · ")
    }

    func matches(_ note: Note) -> Bool {
        if let dateField, let dateWindow {
            let date = dateField == .created ? note.createdAt : note.updatedAt
            guard dateWindow.contains(date) else { return false }
        }
        if let checklist {
            let items = note.document.blocks.compactMap(\.checklistItems).flatMap { $0 }
            switch checklist {
            case .any: if items.isEmpty { return false }
            case .hasUnchecked: if !items.contains(where: { !$0.isChecked }) { return false }
            case .allChecked: if items.isEmpty || items.contains(where: { !$0.isChecked }) { return false }
            case .none: if !items.isEmpty { return false }
            }
        }
        if requiresAttachment, note.attachments.isEmpty { return false }
        if let attachmentKind, !note.attachments.contains(where: { $0.kind == attachmentKind }) { return false }
        if !tagNames.isEmpty {
            let names = Set(note.tags.map(\.name))
            if names.isDisjoint(with: Set(tagNames)) { return false }
        }
        if let folderID, note.folder?.id != folderID { return false }
        if let lockedOnly, note.isLocked != lockedOnly { return false }
        return true
    }
}

private extension SmartDateWindow {
    var predicateOperator: String {
        switch self {
        case .today: ">= startOfDay"
        case .thisWeek: ">= startOfWeek"
        case .last7Days: ">= now-7d"
        case .last30Days: ">= now-30d"
        case .olderThan30Days: "< now-30d"
        }
    }

    func contains(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
            return interval.contains(date)
        case .last7Days:
            return date >= now.addingTimeInterval(-7 * 86_400) && date <= now
        case .last30Days:
            return date >= now.addingTimeInterval(-30 * 86_400) && date <= now
        case .olderThan30Days:
            return date < now.addingTimeInterval(-30 * 86_400)
        }
    }
}
