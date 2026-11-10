import Foundation

enum SearchService {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    static func tokens(_ query: String) -> [String] {
        normalized(query)
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func haystack(for note: Note) -> String {
        var pieces: [String] = [note.title, note.plainText, note.drawingSearchText]
        pieces.append(contentsOf: note.tags.map(\.name))
        for attachment in note.attachments {
            pieces.append(attachment.fileName)
            pieces.append(attachment.ocrText)
            if let title = attachment.metadata.linkTitle { pieces.append(title) }
            if let host = attachment.metadata.linkHost { pieces.append(host) }
            if let map = attachment.metadata.mapTitle { pieces.append(map) }
        }
        return normalized(pieces.joined(separator: "\n"))
    }

    static func matches(note: Note, query: String) -> Bool {
        let tokens = tokens(query)
        guard !tokens.isEmpty else { return true }
        let haystack = haystack(for: note)
        return tokens.allSatisfy { haystack.contains($0) }
    }

    static func filter(_ notes: [Note], query: String) -> [Note] {
        let tokens = tokens(query)
        guard !tokens.isEmpty else { return notes }
        return notes.filter { note in
            // A locked note should not leak whether a query term exists in its
            // encrypted body. It becomes searchable again after unlocking.
            guard !note.isLocked else { return false }
            let haystack = haystack(for: note)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    static func extractTags(from text: String) -> [String] {
        let pattern = #"(?<![\p{L}\p{N}_])#([\p{L}\p{N}_-]{1,32})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, range: range)
        var seen = Set<String>()
        var result: [String] = []
        for match in matches where match.numberOfRanges > 1 {
            guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
            let tag = String(text[swiftRange])
            if seen.insert(tag).inserted { result.append(tag) }
        }
        return result
    }
}
