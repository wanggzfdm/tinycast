import Foundation

@main
struct JSONToolContentEntryTests {
    static func main() {
        let source = #"{"message":"你好"}"#
        let entry = CommandCatalog.contentMatches(for: source).first!
        guard CommandCatalog.command(for: entry) == .jsonFormatter else {
            fatalError("FAIL: offers JSON tool")
        }
        guard CommandCatalog.jsonToolText(from: entry) == source else {
            fatalError("FAIL: preserves matched JSON source")
        }
        guard CommandCatalog.jsonToolText(from: CommandCatalog.makeEntry(.jsonFormatter)) == nil else {
            fatalError("FAIL: generic JSON command has no source")
        }
        print("3 passed, 0 failed")
    }
}
