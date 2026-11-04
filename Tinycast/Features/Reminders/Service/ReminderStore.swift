import EventKit

@MainActor
final class ReminderStore {
    private(set) var access: CalendarAccess = Permissions.reminderAccess()

    /// Built on first use: a Mac that never adds reminders never loads EventKit.
    private var eventStore: EKEventStore?

    /// TCC sends nothing when a grant changes in Settings, so callers re-read before acting.
    func refreshAccess() {
        access = Permissions.reminderAccess()
    }

    func requestAccess() async -> Bool {
        let granted = await Permissions.requestReminderAccess()
        refreshAccess()
        return granted
    }

    /// False means no writable list, which the caller reports rather than silently dropping.
    func addReminder(title: String, due: Date? = nil) -> Bool {
        let store = eventStore ?? EKEventStore()
        eventStore = store
        guard access == .granted, let list = store.defaultCalendarForNewReminders() else {
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
        }
        return (try? store.save(reminder, commit: true)) != nil
    }
}
