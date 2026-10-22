import Foundation

struct ClipboardAutofillPolicy {
    /// How soon after a copy a launcher open still counts as "right after"; older copies never autofill.
    static let freshnessInterval: TimeInterval = 1
    /// The 0.5s poll can lag a fresh copy; the caller retries at this cadence within this window.
    static let retryInterval: TimeInterval = 0.05
    static let retryWindow: TimeInterval = 0.6

    private(set) var lastConsumedChangeCount: Int
    private(set) var changeDates: [Int: Date] = [:]

    mutating func observe(changeCount: Int, at date: Date) {
        guard changeCount != lastConsumedChangeCount else { return }
        changeDates[changeCount] = date
    }

    /// The verdict of one autofill read: filled, settled as a miss, or still unobserved.
    enum Verdict: Equatable {
        case filled(String)
        case missed
        case waiting
    }

    mutating func consume(changeCount: Int, text: String?, at date: Date) -> Verdict {
        guard changeCount != lastConsumedChangeCount else { return .missed }
        // Not yet picked up by the 0.5s poll: the caller may retry shortly.
        guard let changedAt = changeDates[changeCount] else { return .waiting }
        defer {
            lastConsumedChangeCount = changeCount
            changeDates = changeDates.filter { $0.key > changeCount }
        }
        guard date.timeIntervalSince(changedAt) <= Self.freshnessInterval,
              let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= ClipboardTextLimit.maxTextLength
        else { return .missed }
        return .filled(text)
    }
}

enum ClipboardTextLimit {
    static let maxTextLength = 32_000
}
