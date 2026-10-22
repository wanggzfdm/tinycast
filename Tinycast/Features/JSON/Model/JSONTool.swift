import Foundation

/// A JSON diagnostic pinned to a source location, so the editor can say where it failed.
struct JSONToolError: Error, Equatable, LocalizedError {
    let message: String
    let line: Int
    let column: Int
    var errorDescription: String { "\(message) (line \(line), column \(column))" }
}

/// What a token in the JSON editor is, so it can be tinted by kind.
enum JSONSyntaxKind: Equatable { case key, string, number, bool, null, punctuation }

/// A range of UTF-16 units in the editor, tagged with what it represents.
struct JSONSyntaxRange: Equatable {
    let nsRange: NSRange
    let kind: JSONSyntaxKind
}

/// A value-bearing node in the tree view, with its type and JSON path.
struct JSONTreeNode: Identifiable {
    let id = UUID()
    let key: String?
    let value: Any
    let type: String
    let path: String
    let children: [JSONTreeNode]

    init(key: String? = nil, value: Any, path: String = ".") {
        self.key = key
        self.value = value
        self.path = path
        if value is [String: Any] {
            type = "object"
            children = (value as! [String: Any]).keys.sorted().compactMap {
                JSONTreeNode(key: $0, value: (value as! [String: Any])[$0]!,
                             path: path == "." ? ".\($0)" : "\(path).\($0)")
            }
        } else if let array = value as? [Any] {
            type = "array"
            children = array.enumerated().map {
                JSONTreeNode(key: "[\($0.offset)]", value: $0.element, path: "\(path)[\($0.offset)]")
            }
        } else if value is String {
            type = "string"
            children = []
        } else if let number = value as? NSNumber {
            type = JSONTreeNode.isBoolean(number) ? "bool" : "number"
            children = []
        } else if value is NSNull {
            type = "null"
            children = []
        } else {
            type = "unknown"
            children = []
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

/// A brace/bracket pair a code-folding toggle can collapse: the UTF-16 offsets of the open and
/// close marks, the nesting depth, and the line the open mark sits on.
struct JSONFold: Equatable {
    let start: Int
    let end: Int
    let depth: Int
    let line: Int
}

/// JSON parse, format, minify, syntax tinting and filtering. Pure Foundation so a harness can
/// compile it without AppKit or SwiftUI — the editor that consumes it lives in the UI layer.
enum JSONTool {
    /// The whole text parses as JSON, which is what lets it earn the JSON tool's content row.
    static func isValid(_ text: String) -> Bool {
        (try? parse(text)) != nil
    }

    /// Parses, rejecting trailing commas so a format round-trips instead of silently repairing.
    static func parse(_ text: String) throws -> Any {
        try rejectTrailingCommas(text)
        do {
            return try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch {
            let ns = error as NSError
            let offset = ns.userInfo["NSJSONSerializationErrorIndex"] as? Int ?? text.utf8.count
            let (line, column) = lineColumn(text, byteOffset: offset)
            throw JSONToolError(message: ns.localizedDescription, line: line, column: column)
        }
    }

    /// Pretty-printed, keys sorted, so the same input always formats the same way.
    static func format(_ text: String) throws -> String {
        try serialize(try parse(text), options: [.prettyPrinted, .fragmentsAllowed, .withoutEscapingSlashes])
    }

    /// One line, with the whitespace JSONSerialization emits stripped out.
    static func compact(_ text: String) throws -> String {
        try serialize(try parse(text), options: [.fragmentsAllowed, .withoutEscapingSlashes])
    }

    /// Minifies, then re-encodes the result as a JSON string, for pasting into another JSON field.
    static func escapedCompact(_ text: String) throws -> String {
        let compactJSON = try compact(text)
        let wrapped = String(decoding: try JSONSerialization.data(withJSONObject: [compactJSON]), as: UTF8.self)
        return String(wrapped.dropFirst().dropLast())
    }

    /// Compacts an already-parsed value — what a filter result is serialized back into.
    static func compact(_ value: Any) throws -> String {
        try serialize(value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    }

    /// Decodes one JSON string layer only when its contents form a JSON document.
    static func decodeJSONDocumentStringOnce(_ text: String) -> String? {
        guard let decoded = try? parse(text) as? String, isValid(decoded) else { return nil }
        return decoded
    }

    /// The one-based logical line number for every UTF-16 unit in the text.
    static func lineNumbers(for text: String) -> [Int] {
        var line = 1
        var result: [Int] = []
        result.reserveCapacity(text.utf16.count)
        for character in text {
            result.append(contentsOf: repeatElement(line, count: character.utf16.count))
            if character == "\n" { line += 1 }
        }
        return result
    }

    /// Logical lines, counting the empty line that trails a final newline.
    static func logicalLineCount(_ text: String) -> Int {
        lineNumbers(for: text).last.map { $0 + (text.last == "\n" ? 1 : 0) } ?? 1
    }

    /// A tagged token per key, value and punctuation mark, in editor order.
    static func syntaxTokens(_ text: String) -> [JSONSyntaxRange] {
        var result: [JSONSyntaxRange] = []
        let chars = Array(text.utf16)
        let n = chars.count
        var pos = 0
        let punct: Set<UInt16> = [0x2C, 0x3A, 0x7B, 0x7D, 0x5B, 0x5D]

        func isWS(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
        func kind(ofWord word: String) -> JSONSyntaxKind {
            word == "true" || word == "false" ? .bool : word == "null" ? .null
                : Double(word) != nil ? .number : .punctuation
        }

        while pos < n {
            let c = chars[pos]
            if isWS(c) { pos += 1; continue }
            let start = pos
            if c == 0x22 {
                pos += 1
                var escaped = false
                while pos < n {
                    let ch = chars[pos]
                    if escaped { escaped = false }
                    else if ch == 0x5C { escaped = true }
                    else if ch == 0x22 { pos += 1; break }
                    pos += 1
                }
                var after = pos
                while after < n && isWS(chars[after]) { after += 1 }
                let tokenKind: JSONSyntaxKind = (after < n && chars[after] == 0x3A) ? .key : .string
                result.append(JSONSyntaxRange(nsRange: NSRange(location: start, length: pos - start), kind: tokenKind))
            } else if punct.contains(c) {
                pos += 1
                result.append(JSONSyntaxRange(nsRange: NSRange(location: start, length: 1), kind: .punctuation))
            } else {
                while pos < n && !isWS(chars[pos]) && !punct.contains(chars[pos]) { pos += 1 }
                let word = String(decoding: chars[start..<pos], as: UTF16.self)
                result.append(JSONSyntaxRange(nsRange: NSRange(location: start, length: pos - start), kind: kind(ofWord: word)))
            }
            if pos < n && punct.contains(chars[pos]) {
                let p = pos
                pos += 1
                result.append(JSONSyntaxRange(nsRange: NSRange(location: p, length: 1), kind: .punctuation))
            }
        }
        return result
    }

    /// The parsed text as a collapsible tree rooted at the document's value.
    static func tree(_ text: String) throws -> JSONTreeNode {
        JSONTreeNode(value: try parse(text))
    }

    /// Every brace/bracket pair in source order, so the editor can offer one fold toggle each.
    static func folds(_ text: String) -> [JSONFold] {
        var result: [JSONFold] = []
        var stack: [(offset: Int, line: Int)] = []
        var line = 1
        var inString = false
        var escaped = false
        var index = 0
        let units = Array(text.utf16)
        for c in units {
            if inString {
                if escaped { escaped = false }
                else if c == 0x5C { escaped = true }
                else if c == 0x22 { inString = false }
                if c == 0x0A { line += 1 }
                index += 1
                continue
            }
            if c == 0x22 { inString = true; index += 1; continue }
            if c == 0x0A { line += 1 }
            switch c {
            case 0x7B, 0x5B:
                stack.append((index, line))
            case 0x7D, 0x5D:
                if let open = stack.popLast() {
                    result.append(JSONFold(start: open.offset, end: index, depth: stack.count, line: open.line))
                }
            default:
                break
            }
            index += 1
        }
        return result
    }

    /// Walks a dot/bracket expression (`.key`, `[0]`, `.map(x => x.key)`) against the document.
    static func filter(_ text: String, expression: String) throws -> Any {
        var value = try parse(text)
        let chars = Array(expression)
        var i = 0
        func error(_ message: String) -> JSONToolError { JSONToolError(message: message, line: 1, column: max(1, i + 1)) }
        func skip() { while i < chars.count && chars[i].isWhitespace { i += 1 } }
        func key() throws -> String {
            skip()
            guard i < chars.count else { throw error("Expected key") }
            if chars[i] == "\"" { return try quotedKey() }
            let s = i
            while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
            guard s < i else { throw error("Expected object key") }
            return String(chars[s..<i])
        }
        func quotedKey() throws -> String {
            i += 1
            var result = ""
            while i < chars.count {
                let c = chars[i]
                i += 1
                if c == "\"" { return result }
                guard c == "\\" else { result.append(c); continue }
                guard i < chars.count else { throw error("Unterminated escape in quoted key") }
                let escaped = chars[i]
                i += 1
                switch escaped {
                case "\"", "\\", "/": result.append(escaped)
                case "b": result.append("\u{8}")
                case "f": result.append("\u{c}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    guard i + 4 <= chars.count, let first = UInt16(String(chars[i..<i + 4]), radix: 16) else {
                        throw error("Invalid Unicode escape in quoted key")
                    }
                    i += 4
                    if (0xD800...0xDBFF).contains(first) {
                        guard i + 6 <= chars.count, chars[i] == "\\", chars[i + 1] == "u",
                            let second = UInt16(String(chars[i + 2..<i + 6]), radix: 16),
                            (0xDC00...0xDFFF).contains(second) else { throw error("Invalid Unicode surrogate pair in quoted key") }
                        i += 6
                        let scalar = UnicodeScalar(0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00))!
                        result.append(Character(scalar))
                    } else if (0xDC00...0xDFFF).contains(first) {
                        throw error("Invalid Unicode surrogate pair in quoted key")
                    } else {
                        result.append(Character(UnicodeScalar(first)!))
                    }
                default: throw error("Invalid escape in quoted key")
                }
            }
            throw error("Unterminated quoted key")
        }
        func lookup(_ key: String) throws -> Any {
            guard let dict = value as? [String: Any], let v = dict[key] else { throw error("Missing key: \(key)") }
            return v
        }
        skip()
        guard i < chars.count, chars[i] == "." || chars[i] == "[" else { throw error("Filter must start with . or [") }
        while i < chars.count {
            skip()
            if chars[i] == "." {
                i += 1
                skip()
                if i + 3 <= chars.count, String(chars[i..<i + 3]) == "map" {
                    i += 3
                    skip()
                    guard i < chars.count, chars[i] == "(" else { throw error("Invalid map expression") }
                    i += 1
                    skip()
                    let mapStart = i
                    while i < chars.count && (chars[i].isWhitespace || chars[i].isLetter || chars[i] == "=" || chars[i] == ">") { i += 1 }
                    let mapHead = String(chars[mapStart..<i]).filter { !$0.isWhitespace }
                    guard mapHead == "x=>x" else { throw error("Only x => x.key is supported") }
                    skip()
                    guard i < chars.count, chars[i] == "." else { throw error("map requires x.key") }
                    i += 1
                    let k = try key()
                    skip()
                    guard i < chars.count, chars[i] == ")" else { throw error("Invalid map expression") }
                    i += 1
                    guard let array = value as? [Any] else { throw error("map requires an array") }
                    value = try array.map {
                        guard let dict = $0 as? [String: Any], let v = dict[k] else { throw error("Missing key: \(k)") }
                        return v
                    }
                } else {
                    value = try lookup(try key())
                }
            } else if chars[i] == "[" {
                i += 1
                skip()
                if i < chars.count, chars[i] == "\"" {
                    let k = try key()
                    skip()
                    guard i < chars.count, chars[i] == "]" else { throw error("Invalid bracket key") }
                    i += 1
                    value = try lookup(k)
                } else {
                    let s = i
                    while i < chars.count && chars[i].isNumber { i += 1 }
                    guard s < i, let n = Int(String(chars[s..<i])) else { throw error("Invalid array index") }
                    skip()
                    guard i < chars.count, chars[i] == "]" else { throw error("Invalid array index") }
                    i += 1
                    guard let array = value as? [Any], n < array.count else { throw error("Array index out of bounds") }
                    value = array[n]
                }
            } else {
                throw error("Unexpected filter token")
            }
        }
        return value
    }

    private static func rejectTrailingCommas(_ text: String) throws {
        var inString = false
        var escaped = false
        var lastSignificant: (Character, Int)?
        var index = 0
        for c in text {
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" {
                    inString = false
                    // A closing quote is significant: the `]` after it must not read as following a comma.
                    lastSignificant = (c, index)
                }
                index += c.utf8.count
                continue
            }
            if c == "\"" {
                inString = true
                index += 1
                continue
            }
            if c == "," {
                lastSignificant = (c, index)
            } else if !c.isWhitespace {
                if (c == "}" || c == "]"), lastSignificant?.0 == "," {
                    let p = lineColumn(text, byteOffset: index)
                    throw JSONToolError(message: "Trailing comma", line: p.0, column: p.1)
                }
                lastSignificant = (c, index)
            }
            index += c.utf8.count
        }
    }

    private static func lineColumn(_ text: String, byteOffset: Int) -> (Int, Int) {
        let bytes = Array(text.utf8)
        let offset = min(max(0, byteOffset), bytes.count)
        let prefix = String(decoding: bytes.prefix(offset), as: UTF8.self)
        let line = prefix.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        let last = prefix.lastIndex(of: "\n")
        let segment = last.map { String(prefix[prefix.index(after: $0)...]) } ?? prefix
        return (line, max(1, segment.count + 1))
    }

    private static func serialize(_ value: Any, options: JSONSerialization.WritingOptions) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: options), as: UTF8.self)
    }
}