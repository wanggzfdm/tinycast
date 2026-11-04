import Foundation

@main
@MainActor
struct ToolDetachShortcutTests {
    static var failures = 0

    static func expect(_ actual: Bool, _ message: String) {
        if !actual {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        expect(
            ToolDetachShortcut.matches(
                command: true, shift: false, option: false, control: false,
                showsToolChrome: true, isControlListOpen: false, isCollapsed: false),
            "⌘D detaches an expanded tool")
        expect(
            !ToolDetachShortcut.matches(
                command: true, shift: false, option: false, control: false,
                showsToolChrome: false, isControlListOpen: false, isCollapsed: false),
            "⌘D does not detach non-tool screens")
        expect(
            !ToolDetachShortcut.matches(
                command: true, shift: false, option: false, control: false,
                showsToolChrome: true, isControlListOpen: true, isCollapsed: false),
            "an open control list owns ⌘D")
        expect(
            !ToolDetachShortcut.matches(
                command: true, shift: true, option: false, control: false,
                showsToolChrome: true, isControlListOpen: false, isCollapsed: false),
            "⇧⌘D is not the detach shortcut")
        expect(
            !ToolDetachShortcut.matches(
                command: true, shift: false, option: false, control: false,
                showsToolChrome: true, isControlListOpen: false, isCollapsed: true),
            "the compact bar has no tool to detach")

        print("\(5 - failures) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
