import Foundation

// Checks reminder time parsing: a future phrase splits off, the past and plain text do not.
@main
struct ReminderDraftTest {
    static func main() {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if !condition { failures.append(name) }
            print((condition ? "ok   " : "FAIL ") + name)
        }

        // NSDataDetector resolves "明天" against the system clock, so tests ride the real now.
        let now = Date()

        // Plain text stays whole and undated.
        let plain = ReminderDraft.parse("买牛奶", now: now)
        check("plain text keeps its title", plain.title == "买牛奶")
        check("plain text has no due", plain.due == nil)

        // A future time phrase splits off the title and sets a due date.
        let scheduled = ReminderDraft.parse("明天 9 点 开会", now: now)
        check("future phrase sets a due", scheduled.due != nil && scheduled.due! > now)
        check("future phrase shortens the title", scheduled.title.count < "明天 9 点 开会".count)
        check("future phrase keeps the tail", scheduled.title.contains("开会"))

        // Time after the text works too.
        let trailing = ReminderDraft.parse("买牛奶 明天9点", now: now)
        check("trailing phrase sets a due", trailing.due != nil)
        check("trailing phrase keeps the head", trailing.title.contains("买牛奶"))

        // A date in the past is literal text, never a schedule.
        let past = ReminderDraft.parse("1999年1月1日 竣工纪念", now: now)
        check("past date has no due", past.due == nil)
        check("past date keeps its title", past.title == "1999年1月1日 竣工纪念")

        // Text that is nothing but a future date still carries it as the title.
        let only = ReminderDraft.parse("明天9点", now: now)
        check("date-only keeps its text", only.title == "明天9点")
        check("date-only sets a due", only.due != nil)

        // Empty input is an empty draft.
        check("empty input is empty", ReminderDraft.parse("   ", now: now).title == "")

        if failures.isEmpty {
            print("reminder-draft-test: all passed")
        } else {
            print("reminder-draft-test: \(failures.count) failed")
            exit(1)
        }
    }
}
