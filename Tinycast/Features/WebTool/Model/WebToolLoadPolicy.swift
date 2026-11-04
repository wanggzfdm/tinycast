import Foundation

enum WebToolLoadPolicy {
    case initial
    case refresh

    /// A cached page paints first; a detected web update refreshes only on the next explicit open.
    static func resolve(hasLoadedPage: Bool, refreshPending: Bool) -> WebToolLoadPolicy? {
        guard hasLoadedPage else { return .initial }
        return refreshPending ? .refresh : nil
    }
}
