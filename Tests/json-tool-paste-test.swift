// Reproduces the paste-chip → JSON tool summon path: the copied text must survive
// the push to .jsonTool and land in jsonToolText, which is what the editor seeds from.
import Foundation

@main
@MainActor
struct JSONToolPasteTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        let copied = #"{"b":1,"a":[true,null,"x"],"z":"ok"}"#

        // A paste chip on the launcher: query is empty, pastedText carries the copy.
        let vm = PaletteState()
        vm.prepare(mode: .launcher)
        vm.pastedText = copied
        expect(vm.query.isEmpty, "a paste chip leaves the query empty")
        expect(vm.pastedText == copied, "the chip holds the copied JSON")

        // LauncherScreen resolves the match query from the chip, then activate() launches with it.
        let matchQuery = vm.pastedText ?? vm.query
        expect(matchQuery == copied, "the content-match query falls back to the paste chip")

        // Mirrors LauncherCoordinator.launch(.jsonFormatter): only valid JSON rides in, then navigate.
        vm.jsonToolText = JSONTool.isValid(matchQuery) ? matchQuery : ""
        // `navigate(to:)` pushes because the palette is visible and mode differs.
        // push → replace → openScreen clears pastedText/query but must keep jsonToolText.
        vm.push(mode: .jsonTool)

        expect(vm.mode == .jsonTool, "the push lands on the JSON tool screen")
        expect(vm.pastedText == nil, "openScreen clears the chip as it does for every screen")
        expect(vm.query.isEmpty, "openScreen clears the query as it does for every screen")
        expect(vm.jsonToolText == copied, "jsonToolText survives openScreen so the editor can seed")

        // The editor's seed guard: it only fills when text is empty and initialText is not.
        let initialText = vm.jsonToolText
        expect(!initialText.isEmpty, "the editor's initialText is the copied JSON, not empty")
        expect(JSONTool.isValid(initialText), "the copied JSON is valid so it earns a formatted seed")

        // A second summon with a different copy must reseed, not keep the old text.
        let secondCopy = #"{"x":2}"#
        vm.pop()  // back to the launcher
        expect(vm.mode == .launcher, "back returns to the launcher")
        vm.pastedText = secondCopy
        let secondQuery = vm.pastedText ?? vm.query
        vm.jsonToolText = JSONTool.isValid(secondQuery) ? secondQuery : ""
        vm.push(mode: .jsonTool)
        expect(vm.jsonToolText == secondCopy, "a second summon carries the new copy, not the old one")

        // Empty copy must not crash and must leave the editor empty.
        let vm2 = PaletteState()
        vm2.prepare(mode: .launcher)
        vm2.pastedText = ""
        let emptyQuery = vm2.pastedText ?? vm2.query
        vm2.jsonToolText = JSONTool.isValid(emptyQuery) ? emptyQuery : ""
        vm2.push(mode: .jsonTool)
        expect(vm2.jsonToolText.isEmpty, "an empty copy leaves jsonToolText empty")

        // A name search ("json") is not JSON: the same launch path seeds the empty tool.
        let vm3 = PaletteState()
        vm3.prepare(mode: .launcher)
        let nameQuery = "json"
        vm3.jsonToolText = JSONTool.isValid(nameQuery) ? nameQuery : ""
        vm3.push(mode: .jsonTool)
        expect(vm3.jsonToolText.isEmpty, "a name search opens the tool with no carried text")

        report()
    }

    static func report() {
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
