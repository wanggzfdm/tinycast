import AppKit

/// Reads Finder's current window target only while Finder is the app the palette covered.
enum FinderFolderAccess {
    static func isFinder(_ app: NSRunningApplication?) -> Bool {
        app?.bundleIdentifier == "com.apple.finder"
    }

    static func currentFolder(finderWasFrontmost: Bool) async -> URL? {
        guard finderWasFrontmost else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let source = """
                tell application "Finder"
                    if (count of windows) is 0 then return ""
                    POSIX path of (target of front window as alias)
                end tell
                """
            guard let script = NSAppleScript(source: source),
                let path = script.executeAndReturnError(nil).stringValue,
                !path.isEmpty
            else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }.value
    }
}
