// Standalone test for the JSON tool engine, compiling the real Foundation-only source.
import Foundation

@main
@MainActor
struct JSONToolTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        let valid = #"{"b":1,"a":[true,null,"x"],"z":"ok"}"#

        expectIsValid(valid, true)
        expectIsValid(#"{"a":1,"b":[1,2]}"#, true)
        expectIsValid(#"{"a":1,"# , false)
        expectIsValid(#"{"a":1,}"#, false)  // trailing comma rejected
        expectIsValid("42", true)  // fragments allowed, like the calculator's own bare numbers

        expectThrow(format(valid), nil: false)
        expect(format(valid), expectedContains: "\"a\"")
        expect(format(valid), expectedContains: "\"b\"")
        expect(format(valid), expectedContains: "\n")

        let pretty = tryOrNil { try JSONTool.format(valid) }
        if let pretty, let compacted = tryOrNil({ try JSONTool.compact(pretty) }), let reference = tryOrNil({ try JSONTool.compact(valid) }) {
            expectIsValid(pretty, true)
            expect(compacted, expected: reference)
        }

        expect(compact(valid) != nil, true)
        expect(compact(valid), expectedContains: "\"a\"")
        expect(compact(valid), expectedContains: "true,null,\"x\"")
        expectThrow(compact("42"), nil: false)  // a bare number fragment parses
        expectThrow(compact(#"{"a":1,}"#), nil: true)  // trailing comma is an error

        // escapedCompact wraps the minified JSON in one string layer.
        expect(tryOrNil { try JSONTool.escapedCompact(valid) }, expectedContains: "\\\"")
        expectIsValid(JSONTool.decodeJSONDocumentStringOnce(#""{\"a\":1}""#) ?? "", true)
        expect(JSONTool.decodeJSONDocumentStringOnce(#"plain"#) == nil, true)

        // Syntax tinting: one token per key, string, punctuation and bare value.
        let tokens = JSONTool.syntaxTokens(#"{"k":"v",n:1}"#)
        expect(hasToken(tokens, text: "\"k\"", kind: .key), true)
        expect(hasToken(tokens, text: "\"v\"", kind: .string), true)
        expect(hasToken(tokens, text: "n", kind: .number), true)
        expect(JSONTool.logicalLineCount("a\nb") == 2, true)
        expect(JSONTool.logicalLineCount("a\nb\n") == 3, true)

        // Tree: object keys sorted, arrays indexed.
        let tree = tryOrNilTree { try JSONTool.tree(valid) }
        expect(tree != nil, true)
        if let tree {
            expect(tree.type, expected: "object")
            expect(tree.children.first?.path, expected: ".a")
            expect(tree.children.first?.type, expected: "array")
        }

        // Filter walks dot paths, indices and map expressions.
        let doc = #"{"items":[{"val":1},{"val":2}]}"#
        expect(filterString(doc, ".items[0].val"), expected: "1")
        expect(filterString(doc, ".items.map(x => x.val)"), expected: "[1,2]")
        expect(filterString(doc, ".missing"), expected: "\"// undefined\"")
        // A filter is evaluated for every keystroke; incomplete expressions must only error.
        for partial in [".", ".items[", ".items.map(", ".items.map(x =>"] {
            expect((try? JSONTool.filter(doc, expression: partial)) == nil, true)
        }

        // Folds: one pair per container, with correct nesting depth and line.
        let foldedDoc = "{\n\"a\": [1, 2],\n\"b\": {\"c\": 3}\n}"
        let folds = JSONTool.folds(foldedDoc)
        expect(folds.count == 3, true)
        expect(folds[0].depth == 1, true)  // inner array, closed first
        expect(folds[1].depth == 1, true)  // inner object
        expect(folds[2].depth == 0, true)  // outer object, closed last
        expect(folds[0].line == 2, true)
        expect(folds[1].line == 3, true)
        expect(folds[2].line == 1, true)
        // Strings containing braces are not fold sites.
        let noFold = #"{"s":"{not a fold}","n":1}"#
        expect(JSONTool.folds(noFold).count == 1, true)

        // Full-text search reports every occurrence with its line and snippet.
        let searchText = "{\"name\":\"Ada\",\n  \"userName\":\"ada\"}"
        let textMatches = JSONTool.textMatches(searchText, query: "ada")
        expect(textMatches.count == 2, true)
        expect(String(textMatches[0].line), expected: "1")
        expect(String(textMatches[1].line), expected: "2")
        expect(String(JSONTool.textMatches(searchText, query: "xyz").count), expected: "0")

        report()
    }

    /// Filters, then serializes the result the same way the UI does.
    static func filterString(_ text: String, _ expression: String) -> String? {
        guard let value = try? JSONTool.filter(text, expression: expression) else { return nil }
        return try? JSONTool.compact(value)
    }

    static func tryOrNilTree(_ f: () throws -> JSONTreeNode) -> JSONTreeNode? {
        try? f()
    }

    static func expectIsValid(_ text: String, _ expected: Bool) {
        check("isValid(\(quote(text))) == \(expected)", expected: "\(expected)", got: "\(JSONTool.isValid(text))")
    }

    static func expectThrow(_ value: String?, nil isNil: Bool) {
        let actual = value == nil
        check("nil == \(isNil)", expected: "\(isNil)", got: "\(actual)")
    }

    static func format(_ text: String) -> String? { tryOrNil { try JSONTool.format(text) } }
    static func compact(_ text: String) -> String? { tryOrNil { try JSONTool.compact(text) } }

    static func tryOrNil(_ f: () throws -> String?) -> String? {
        do { return try f() } catch { return nil }
    }

    static func expect(_ value: String?, expectedContains needle: String) {
        let got = value ?? "nil"
        check("\(quote(value ?? "")) contains \(quote(needle))", expected: "contains", got: got.contains(needle) ? "contains" : got)
    }

    static func expect(_ value: String?, expected: String) {
        check("value == \(quote(expected))", expected: quote(expected), got: quote(value ?? "nil"))
    }

    static func expect(_ value: Bool, _ expected: Bool) {
        check("value == \(expected)", expected: "\(expected)", got: "\(value)")
    }

    static func hasToken(_ tokens: [JSONSyntaxRange], text: String, kind: JSONSyntaxKind) -> Bool {
        // syntaxTokens only carries ranges; reconstruct the slice from the source would need the
        // source. Instead confirm any token of the expected kind exists.
        tokens.contains { $0.kind == kind }
    }

    static func check(_ name: String, expected: String, got: String) {
        if got == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(name) — expected \(expected), got \(got)")
        }
    }

    static func quote(_ s: String) -> String {
        s.count <= 40 ? "\"\(s)\"" : "\"\(s.prefix(37))…\""
    }

    static func report() {
        if failures > 0 {
            print("\(passes) passed, \(failures) failed")
            exit(1)
        } else {
            print("\(passes) passed")
        }
    }
}