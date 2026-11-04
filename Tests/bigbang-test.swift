import Foundation

// Checks Big Bang word breaking and selection rejoining against the source text.
@main
struct BigBangTest {
    static func main() {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures.append(name) }
            print((condition ? "ok   " : "FAIL ") + name)
        }

        // Chinese explodes into multiple word pills covering the whole text.
        let chinese = BigBang.words(in: "明天早上九点开会讨论项目排期")
        check("chinese splits into words", chinese.count > 2)
        check("chinese pills carry letters", chinese.allSatisfy { $0.text.contains { $0.isLetter } })

        // English splits on word boundaries, punctuation never becomes a pill.
        let english = BigBang.words(in: "cache miss, retry later")
        check("english splits", english.count == 4)
        check("english has no punctuation pill", english.allSatisfy { !$0.text.contains(",") })

        // Rejoining adjacent Chinese words restores them glued, a gap keeps its space.
        let glued = BigBang.words(in: "明天开会")
        check("adjacent words rejoin glued", BigBang.join(glued, in: "明天开会") == "明天开会")

        let gapped = BigBang.words(in: "cache miss")
        check("gapped words rejoin with a space", BigBang.join(gapped, in: "cache miss") == "cache miss")

        // A single pick joins to itself.
        let single = BigBang.words(in: "hello")
        check("single pick rejoins as-is", BigBang.join([single[0]], in: "hello") == "hello")

        // Picks with skipped words between them never swallow the sentence back.
        let skippedChinese = BigBang.words(in: "明天早上九点开会讨论排期")
        let pickedChinese = [skippedChinese[0], skippedChinese[3]]
        check("skipped chinese words are dropped",
              BigBang.join(pickedChinese, in: "明天早上九点开会讨论排期") == "明天开会")

        let skippedEnglish = BigBang.words(in: "cache miss retry later")
        let pickedEnglish = [skippedEnglish[0], skippedEnglish[3]]
        check("skipped english words get a space",
              BigBang.join(pickedEnglish, in: "cache miss retry later") == "cache later")

        // Shift-click selects the inclusive interval from the last anchor.
        check("shift pick creates an inclusive range",
              BigBang.togglingSelection([1], tapped: 4, anchor: 1, extending: true) == Set(1...4))
        check("plain pick toggles only itself",
              BigBang.togglingSelection([1, 2], tapped: 2, anchor: 1, extending: false) == [1])

        // Dragging paints the inclusive interval between the press and the current pill.
        check("drag paints the interval",
              BigBang.dragSelection(tapped: 2, anchor: 5) == Set(2...5))
        check("drag works backwards",
              BigBang.dragSelection(tapped: 5, anchor: 2) == Set(2...5))
        check("drag from nothing selects the tapped pill",
              BigBang.dragSelection(tapped: 3, anchor: nil) == [3])

        // A drag overwrites the previous selection: it is a fresh gesture, not a union.
        check("drag restarts the selection", BigBang.dragSelection(tapped: 1, anchor: 4) == Set(1...4))

        // Empty input is empty.
        check("empty text is empty", BigBang.words(in: "").isEmpty)

        if failures.isEmpty {
            print("bigbang-test: all passed")
        } else {
            print("bigbang-test: \(failures.count) failed")
            exit(1)
        }
    }
}
