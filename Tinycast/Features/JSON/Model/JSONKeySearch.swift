import Foundation

struct JSONTextMatch: Identifiable, Equatable {
    let range: NSRange
    let line: Int
    let snippet: String

    var id: String { "\(range.location)" }
}

extension JSONTool {
    /// Case-insensitive full-text matches with source ranges, line numbers and line snippets.
    static func textMatches(_ text: String, query: String) -> [JSONTextMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let source = text as NSString
        let haystack = NSString(string: (text as NSString).lowercased)
        let target = NSString(string: (needle as NSString).lowercased)
        guard target.length > 0, haystack.length >= target.length else { return [] }

        var matches: [JSONTextMatch] = []
        var search = NSRange(location: 0, length: haystack.length)
        while search.location + target.length <= haystack.length {
            let hit = haystack.range(of: target as String, options: [], range: search)
            guard hit.location != NSNotFound else { break }
            let lineStart = haystack.lineStartPosition(before: hit.location)
            let line = haystack.lineNumber(at: hit.location)
            let lineEnd = min(haystack.length, lineStart + 200)
            let lineText = source.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
            let snippet = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            matches.append(JSONTextMatch(range: hit, line: line, snippet: snippet))
            search = NSRange(location: NSMaxRange(hit), length: haystack.length - NSMaxRange(hit))
        }
        return matches
    }
}

private extension NSString {
    func lineStartPosition(before location: Int) -> Int {
        var index = location
        while index > 0, character(at: index - 1) != unichar(10) { index -= 1 }
        return index
    }

    func lineNumber(at location: Int) -> Int {
        var line = 1
        for index in 0..<location where character(at: index) == unichar(10) { line += 1 }
        return line
    }
}
