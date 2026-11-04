import Foundation

/// Content tools lead only when nothing else answers the query; any ordinary result owns Enter.
enum LauncherContentPlacement {
    static func separatesTools(entries: [AppEntry]) -> Bool {
        !entries.isEmpty
    }

    /// Clipboard text is an explicit one-shot action, while the empty launcher has a full app grid.
    static func toolsLead(query: String, pastedText: String?) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(pastedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Finder lends its folder to file creation, but matched apps still own the top rows and
    /// Enter; the insertion point follows the app run, after any leading browser or card rows.
    static func fileCreationInsertionIndex(in entries: [AppEntry], leadingRows: Int) -> Int {
        leadingRows
            + entries.dropFirst(leadingRows).prefix { $0.kind == .application }.count
    }
}
