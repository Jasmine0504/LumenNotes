import Foundation

/// The app and the widget extension cannot share object graphs, so a tiny
/// App Group queue bridges "create a note now" requests.
enum SharedCapture {
    static let appGroup = "group.com.lumen.notes"
    private static let key = "lumen.pendingCapture"

    struct Request: Codable, Sendable {
        var id: UUID
        var createdAt: Date
        var initialText: String?
        var source: String
    }

    static func enqueue(text: String? = nil, source: String) {
        let request = Request(id: UUID(), createdAt: .now, initialText: text, source: source)
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults.set(data, forKey: key)
    }

    static func consume() -> Request? {
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return try? JSONDecoder().decode(Request.self, from: data)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
