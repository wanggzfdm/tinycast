import Foundation
@main
enum PaletteAutofillTest {
    static func main() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        policy.observe(changeCount: 2, at: start)
        expect(policy.consume(changeCount: 2, text: "hello", at: start.addingTimeInterval(1)) == .filled("hello"))
        expect(policy.consume(changeCount: 2, text: "hello", at: start.addingTimeInterval(1)) == .missed)

        policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        policy.observe(changeCount: 2, at: start)
        expect(policy.consume(changeCount: 2, text: "old", at: start.addingTimeInterval(20)) == .missed)

        policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        policy.observe(changeCount: 2, at: start.addingTimeInterval(0.2))
        expect(policy.consume(changeCount: 2, text: "instant", at: start.addingTimeInterval(0.2)) == .filled("instant"))

        policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        policy.observe(changeCount: 2, at: start)
        expect(policy.consume(changeCount: 2, text: "hello", at: start.addingTimeInterval(1)) == .filled("hello"))
        policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        policy.observe(changeCount: 2, at: start)
        expect(policy.consume(changeCount: 2, text: "hello", at: start.addingTimeInterval(1.1)) == .missed)
        expect(policy.consume(changeCount: 2, text: "hello", at: start.addingTimeInterval(1.2)) == .missed)

        // An unobserved change stays "waiting" — the caller retries instead of consuming it.
        policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        expect(policy.consume(changeCount: 2, text: "late", at: start) == .waiting)
        policy.observe(changeCount: 2, at: start)
        expect(policy.consume(changeCount: 2, text: "late", at: start) == .filled("late"))

        policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        policy.observe(changeCount: 2, at: start)
        expect(policy.consume(changeCount: 2, text: " \n", at: start) == .missed)
        policy = ClipboardAutofillPolicy(lastConsumedChangeCount: 1)
        policy.observe(changeCount: 2, at: start)
        expect(policy.consume(changeCount: 2, text: String(repeating: "x", count: ClipboardTextLimit.maxTextLength + 1), at: start) == .missed)
    }

    static func expect(_ value: Bool) {
        if !value { fatalError("Clipboard autofill policy assertion failed") }
    }
}