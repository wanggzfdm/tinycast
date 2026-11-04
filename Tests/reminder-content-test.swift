import AppKit
import Foundation

// Checks the launcher's reminder content row: URL round-trip and the shape of the match.
@main
struct ReminderContentTest {
    static func main() {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures.append(name) }
            print((condition ? "ok   " : "FAIL ") + name)
        }
        func expect(_ actual: String, expected: String, _ name: String) {
            check("\(name): \(actual)", actual == expected)
        }

        let entry = CommandCatalog.reminder(for: "买牛奶")!
        expect(entry.name, expected: "添加提醒", "row name")
        expect(entry.subtitle ?? "", expected: "买牛奶", "subtitle carries the text")
        expect(CommandCatalog.reminderTitle(from: entry) ?? "", expected: "买牛奶", "title round-trip")

        let unicode = CommandCatalog.reminder(for: "明天 9 点 standup 会上同步进度")!
        expect(CommandCatalog.reminderTitle(from: unicode) ?? "",
               expected: "明天 9 点 standup 会上同步进度", "unicode round-trip")

        check("empty text is no row", CommandCatalog.reminder(for: "   ") == nil)
        check("absolute path is no row", CommandCatalog.reminder(for: "/usr/bin") == nil)

        // The entry routes through the command funnel.
        expect(CommandCatalog.command(for: entry)?.rawValue ?? "", expected: "command:create-reminder", "command id")

        let app = AppEntry(
            id: "com.example.Activity", name: "活动监视器", url: URL(fileURLWithPath: "/tmp"),
            bundleID: "com.example.Activity", kind: .application)
        check("application match separates content tools",
              LauncherContentPlacement.separatesTools(entries: [app, entry]))
        let command = CommandCatalog.makeEntry(.openCamera)
        check("command match separates content tools",
              LauncherContentPlacement.separatesTools(entries: [command, entry]))
        check("tool-only match keeps content tools leading",
              !LauncherContentPlacement.separatesTools(entries: []))
        check("clipboard text leads tools in an empty query",
              LauncherContentPlacement.toolsLead(query: "", pastedText: "thinking"))
        check("typed query keeps ordinary results leading",
              !LauncherContentPlacement.toolsLead(query: "thinking", pastedText: "thinking"))
        check("empty launcher does not make a tool section lead",
              !LauncherContentPlacement.toolsLead(query: "", pastedText: nil))

        // Finder lends its folder to file creation, but matched apps still own the top rows.
        let app2 = AppEntry(
            id: "com.example.Mole", name: "Mole", url: URL(fileURLWithPath: "/tmp"),
            bundleID: "com.example.Mole", kind: .application)
        check("creation follows matched apps",
              LauncherContentPlacement.fileCreationInsertionIndex(in: [app, app2], leadingRows: 0) == 2)
        check("a non-app run start leaves creation leading",
              LauncherContentPlacement.fileCreationInsertionIndex(in: [command, app], leadingRows: 0) == 0)
        check("leading rows are skipped, not counted",
              LauncherContentPlacement.fileCreationInsertionIndex(in: [command, app], leadingRows: 1) == 2)
        check("no results leaves creation leading",
              LauncherContentPlacement.fileCreationInsertionIndex(in: [], leadingRows: 0) == 0)

        // The Big Bang command: a catalog entry, never a content row, so its id round-trips.
        let bigBang = CommandCatalog.entry(for: .bigBang)
        expect(bigBang?.name ?? "", expected: "大爆炸", "big bang row name")
        expect(bigBang?.id ?? "", expected: "command:bigbang", "big bang command id")
        check("big bang is a plain command", bigBang?.kind == .command)

        // Clipboard text earns a Big Bang content row carrying the exact source.
        let bigBangRow = CommandCatalog.contentMatches(for: "BUILD-DONE").first {
            $0.id == CommandID.bigBang.rawValue
        }
        expect(bigBangRow?.name ?? "", expected: "大爆炸", "content row name")
        expect(CommandCatalog.bigBangText(from: bigBangRow!) ?? "", expected: "BUILD-DONE", "text round-trip")
        check("blank text is no big bang row",
              CommandCatalog.contentMatches(for: "   ").allSatisfy { $0.id != CommandID.bigBang.rawValue })

        // A pasted folder path still translates, but a typed path never grows a translate row.
        let pathRow = CommandCatalog.contentMatches(for: "/Applications", pasted: true).first {
            $0.id == CommandID.translate.rawValue
        }
        expect(CommandCatalog.translateText(from: pathRow!) ?? "", expected: "/Applications", "path text round-trip")
        check("typed path stays path-only",
              !CommandCatalog.contentMatches(for: "/Applications").contains { $0.id == CommandID.translate.rawValue })

        if failures.isEmpty {
            print("reminder-content-test: all passed")
        } else {
            print("reminder-content-test: \(failures.count) failed")
            exit(1)
        }
    }
}
