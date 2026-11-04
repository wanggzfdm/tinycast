import Foundation

struct ReminderDraft: Equatable, Sendable {
    let title: String
    let due: Date?

    /// Splits typed text into a reminder title and an optional due date via the system's
    /// date detector. A date already in the past stays as literal text: "昨天…" is a note,
    /// not a schedule. A text that is nothing but a date keeps the full text as its title.
    static func parse(_ text: String, now: Date) -> ReminderDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return ReminderDraft(title: trimmed, due: nil) }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for match in detector.matches(in: trimmed, range: range) {
            guard match.range.location != NSNotFound,
                let due = match.date, due >= now,
                let matchRange = Range(match.range, in: trimmed)
            else { continue }
            let remainder = (
                String(trimmed[trimmed.startIndex..<matchRange.lowerBound]) + " "
                    + String(trimmed[matchRange.upperBound...])
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,、;；:："))
            guard !remainder.isEmpty else {
                return ReminderDraft(title: trimmed, due: due)
            }
            return ReminderDraft(title: remainder, due: due)
        }
        return ReminderDraft(title: trimmed, due: nil)
    }
}
