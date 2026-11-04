import Foundation
import NaturalLanguage

struct BigBangWord: Identifiable, Equatable, Sendable {
    let index: Int
    let text: String
    /// utf16 offsets in the source text, so a selection rejoins with the gaps it came from.
    let range: NSRange

    var id: Int { index }
}

/// Smartisan-style word breaking: NLTokenizer gives Chinese real word boundaries, so a
/// reader can pick scattered words and translate exactly what they chose.
enum BigBang {
    static func words(in text: String) -> [BigBangWord] {
        var words: [BigBangWord] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            // Pure punctuation and whitespace are separators, never pickable words.
            guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else { return true }
            words.append(
                BigBangWord(
                    index: words.count, text: trimmed,
                    range: NSRange(
                        location: range.lowerBound.utf16Offset(in: text),
                        length: range.upperBound.utf16Offset(in: text)
                            - range.lowerBound.utf16Offset(in: text))))
            return true
        }
        return words
    }

    /// Selected words rejoin as a new text: adjacent picks keep their original spacing, but
    /// anything skipped between them is dropped — two picks must never swallow the sentence back.
    static func join(_ words: [BigBangWord], in source: String) -> String {
        guard words.count > 1 else { return words.first?.text ?? "" }
        let sorted = words.sorted { $0.index < $1.index }
        var joined = sorted[0].text
        var previous = sorted[0]
        for word in sorted.dropFirst() {
            let gapLength = word.range.location - NSMaxRange(previous.range)
            if gapLength > 0 {
                let gap = NSRange(location: NSMaxRange(previous.range), length: gapLength)
                let gapText = (source as NSString).substring(with: gap)
                if gapText.contains(where: { !$0.isWhitespace }) {
                    // Something was skipped: Latin picks still need a separator, CJK glues.
                    if needsSpace(previous.text, word.text) { joined += " " }
                } else if gapText.contains(where: { $0.isWhitespace }) {
                    joined += " "
                }
            }
            joined += word.text
            previous = word
        }
        return joined
    }

    /// A plain click toggles one pill; Shift-click selects the inclusive range from its anchor.
    static func togglingSelection(
        _ selected: Set<Int>, tapped: Int, anchor: Int?, extending: Bool
    ) -> Set<Int> {
        guard extending, let anchor else {
            var result = selected
            if !result.insert(tapped).inserted { result.remove(tapped) }
            return result
        }
        return Set(min(anchor, tapped)...max(anchor, tapped))
    }

    /// A drag paints the inclusive interval from where it started to where it is now.
    static func dragSelection(tapped: Int, anchor: Int?) -> Set<Int> {
        guard let anchor else { return [tapped] }
        return Set(min(anchor, tapped)...max(anchor, tapped))
    }

    private static func needsSpace(_ a: String, _ b: String) -> Bool {
        func isCJK(_ character: Character?) -> Bool {
            guard let character, let scalar = character.unicodeScalars.first else { return false }
            return (0x4E00...0x9FFF).contains(scalar.value)
        }
        return !(isCJK(a.last) && isCJK(b.first))
    }
}
