import Foundation
import JavaScriptCore

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

    /// Evaluates a JS expression against the document, mirroring ZTools' `evalJsInContext`:
    /// `this` is bound to the parsed value, the user's expression is appended to `this` and eval'd.
    static func filter(_ text: String, expression: String) throws -> Any {
        let value = try parse(text)
        return try filter(value, expression: expression)
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

    /// Evaluates `this` + the user's expression in a JavaScriptCore sandbox, mirroring ZTools'
    /// `evalJsInContext`. Returns a Swift value the UI can re-serialize; `// undefined` and
    /// `// function` are returned as strings to match ZTools' sentinel output.
    static func filter(_ value: Any, expression: String) throws -> Any {
        guard let context = JSContext() else { throw JSONToolError(message: "无法创建 JS 上下文", line: 1, column: 1) }
        var errorMessage: String?
        context.exceptionHandler = { _, exception in
            errorMessage = exception?.toString()
        }
        let json = try serialize(value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        let escapedJSON = String(decoding: try JSONSerialization.data(withJSONObject: [json]), as: UTF8.self)
        let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedExpr = expr
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        var __input = JSON.parse(\(escapedJSON));
        eval("__input\(escapedExpr)");
        """
        let result = context.evaluateScript(script)
        if let errorMessage {
            throw JSONToolError(message: errorMessage, line: 1, column: 1)
        }
        guard let result else { return "// undefined" }
        if result.isUndefined { return "// undefined" }
        if let str = result.toString(), str == "[object Function]" { return "// function" }
        if let obj = result.toObject() {
            if let dict = obj as? [String: Any], dict.isEmpty, result.toString() == "undefined" {
                return "// undefined"
            }
            return obj
        }
        return result.toString() ?? ""
    }

    /// Removes `//` line comments and `/* */` block comments outside of strings.
    static func stripComments(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "\"" {
                let (strEnd, next) = readString(text, from: i)
                result.append(contentsOf: text[i..<next])
                i = next
                _ = strEnd
                continue
            }
            if c == "/" && text.index(after: i) < text.endIndex {
                let next = text[text.index(after: i)]
                if next == "/" {
                    let lineEnd = text[i...].firstIndex(of: "\n") ?? text.endIndex
                    i = lineEnd
                    continue
                }
                if next == "*" {
                    let close = text[i...].range(of: "*/")
                    if let close {
                        i = text.index(after: close.upperBound)
                        continue
                    }
                }
            }
            result.append(c)
            i = text.index(after: i)
        }
        return result
    }

    private static func readString(_ text: String, from start: String.Index) -> (end: String.Index, next: String.Index) {
        var i = text.index(after: start)
        while i < text.endIndex {
            let c = text[i]
            if c == "\\" {
                i = text.index(after: i)
                if i < text.endIndex { i = text.index(after: i) }
                continue
            }
            if c == "\"" {
                return (i, text.index(after: i))
            }
            i = text.index(after: i)
        }
        return (text.endIndex, text.endIndex)
    }

    /// A parsed value as XML, mirroring ZTools' `jsonObjToXml` + `toXml`.
    /// `@attr` keys become attributes, `#text` a text node, `#cdata` a CDATA section.
    static func toJSONXML(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            let keys = dict.keys.sorted()
            if keys.count == 1, let only = keys.first, !(dict[only] is [Any]) {
                return toXMLNode(key: only, value: dict[only]!)
            }
            return "<root>\(keys.map { toXMLNode(key: $0, value: dict[$0]!) }.joined())</root>"
        }
        if let array = value as? [Any] {
            return "<root>\(array.map { toXMLNode(key: "element", value: $0) }.joined())</root>"
        }
        return "<root>\(xmlText(value))</root>"
    }

    private static func toXMLNode(key: String, value: Any) -> String {
        if let array = value as? [Any] {
            return array.map { toXMLNode(key: key, value: $0) }.joined()
        }
        if let dict = value as? [String: Any] {
            var attrs = ""
            var hasChildren = false
            for k in dict.keys.sorted() where k.hasPrefix("@") {
                let attrName = String(k.dropFirst()).replacingOccurrences(of: "/", with: "-")
                attrs += " \(attrName)=\"\(xmlText(dict[k]!))\""
            }
            for k in dict.keys.sorted() where !k.hasPrefix("@") { hasChildren = true; _ = k }
            if !hasChildren { return "<\(key)\(attrs)/>" }
            var inner = ""
            for k in dict.keys.sorted() {
                if k == "#text" { inner += xmlText(dict[k]!) }
                else if k == "#cdata" { inner += "<![CDATA[\(dict[k]!)]]>" }
                else if !k.hasPrefix("@") { inner += toXMLNode(key: k, value: dict[k]!) }
            }
            return "<\(key)\(attrs)>\(inner)</\(key)>"
        }
        return "<\(key)>\(xmlText(value))</\(key)>"
    }

    private static func xmlText(_ value: Any) -> String {
        if value is NSNull { return "" }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        return String(describing: value)
    }

    /// A parsed value as TypeScript interface declarations, mirroring ZTools' type inferrer:
    /// each nested object becomes its own `interface`, arrays infer from their first element.
    static func toTypeScript(_ value: Any, name: String = "Root") -> String {
        var names: [String] = []
        let root = tsName(for: value, key: name, isRoot: true, names: &names)
        return names.joined(separator: "\n\n")
            + (names.isEmpty ? "type \(name) = \(tsScalar(value))" : "")
            + (root != name && !names.isEmpty ? "" : "")
    }

    private static func tsName(for value: Any, key: String, isRoot: Bool, names: inout [String]) -> String {
        if let dict = value as? [String: Any] {
            let ifaceName = tsUniqueName(key, names: names)
            names.append(tsInterface(name: ifaceName, dict: dict, names: &names))
            return ifaceName
        }
        if let array = value as? [Any], !array.isEmpty {
            let elemKey = isRoot ? "\(key)Item" : tsSingular(key)
            let elemType = tsName(for: array[0], key: elemKey, isRoot: false, names: &names)
            return "\(elemType.contains(" ") ? "(\(elemType))" : elemType)[]"
        }
        if let array = value as? [Any], array.isEmpty {
            return "unknown[]"
        }
        return tsScalar(value)
    }

    private static func tsInterface(name: String, dict: [String: Any], names: inout [String]) -> String {
        var lines = ["interface \(name) {"]
        for k in dict.keys.sorted() {
            let v = dict[k]!
            let fieldName = tsFieldName(k)
            let type = tsName(for: v, key: k, isRoot: false, names: &names)
            let isOptional = v is NSNull
            lines.append("  \(fieldName)\(isOptional ? "?" : ""): \(isOptional && type == "null" ? "any" : type);")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func tsUniqueName(_ key: String, names: [String]) -> String {
        var base = tsPascalCase(key)
        if base.isEmpty { base = "Root" }
        if !names.contains(base) { return base }
        var i = 2
        while names.contains("\(base)\(i)") { i += 1 }
        return "\(base)\(i)"
    }

    private static func tsPascalCase(_ key: String) -> String {
        key.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func tsSingular(_ key: String) -> String {
        if key.hasSuffix("s") && !key.hasSuffix("ss") { return String(key.dropLast()) }
        return key
    }

    private static func tsFieldName(_ key: String) -> String {
        if key.isEmpty { return "''" }
        if key.first?.isLetter == true || key.first == "_" {
            if key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { return key }
        }
        return "'\(key)'"
    }

    private static func tsScalar(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return "boolean" }
        if value is NSNumber { return "number" }
        if value is String { return "string" }
        return "unknown"
    }

    private static func serialize(_ value: Any, options: JSONSerialization.WritingOptions) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: options), as: UTF8.self)
    }
}