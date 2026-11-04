import Foundation

@main
@MainActor
struct ToolWindowLevelTests {
    static var failures = 0

    static func expect(_ actual: ToolWindowLevel, _ expected: ToolWindowLevel, _ message: String) {
        if actual == expected { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func main() {
        expect(ToolWindowLevel(alwaysOnTop: false), .normal, "ordinary windows stay normal")
        expect(ToolWindowLevel(alwaysOnTop: true), .floating, "tools use the floating level")
        print("\(2 - failures) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
