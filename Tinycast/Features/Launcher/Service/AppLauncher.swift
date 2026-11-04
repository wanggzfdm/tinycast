import AppKit

enum AppLauncher {

    @MainActor
    static func launch(_ url: URL, allowsRunningApplicationSubstitution: Bool = true) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = allowsRunningApplicationSubstitution
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
    @MainActor
    static func openInTerminal(_ path: String) {
        if let script = terminalOpenScript(for: path) {
            var errorInfo: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        } else {
            // No supported terminal installed: bare `open` still lands a folder in Finder.
            open(URL(fileURLWithPath: path))
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Prefer a real terminal in this order — iTerm2, Ghostty, then Terminal.app — like ZTools.
    private static var preferredTerminalApp: String? {
        let candidates = [
            "/Applications/iTerm.app", "/Applications/iTerm2.app",
            "/Applications/Ghostty.app", "/Applications/Utilities/Terminal.app",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The AppleScript that opens `path` in the installed terminal, or nil when none is found.
    private static func terminalOpenScript(for path: String) -> String? {
        let quoted = shellQuoted(path)
        switch preferredTerminalApp {
        case .some(let app) where app.contains("iTerm"):
            // A new tab in the front window, or a window when none exists; then cd.
            return """
                tell application "iTerm"
                    activate
                    if (count of windows) = 0 then
                        create window with default profile
                    else
                        tell current window
                            create tab with default profile
                        end tell
                    end if
                    tell current session of current window
                        write text "cd \(quoted)"
                    end tell
                end tell
                """
        case .some(let app) where app.contains("Ghostty"):
            // New window config carries the working directory; no shell write needed.
            return """
                tell application "Ghostty"
                    activate
                    set cfg to new surface configuration
                    set initial working directory of cfg to "\(path.replacingOccurrences(of: "\"", with: "\\\""))"
                end tell
                """
        case .some:
            // Terminal.app: a new tab in the front window, or a window when none exists.
            return """
                tell application "Terminal"
                    activate
                    if (count of windows) is 0 then
                        do script "cd \(quoted)"
                    else
                        do script "cd \(quoted)" in front window
                    end if
                end tell
                """
        case nil:
            return nil
        }
    }

    @MainActor
    static func openInVisualStudioCode(_ url: URL) {
        NSWorkspace.shared.open(
            [url], withApplicationAt: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        bringFileViewerForwardIfRefused()
    }

    /// While `.regular` and inactive, cooperative activation refuses the viewer's own activation.
    @MainActor
    private static func bringFileViewerForwardIfRefused() {
        guard NSApp.activationPolicy() == .regular, !NSApp.isActive,
            let viewer = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: fileViewerBundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: viewer, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The global `NSFileViewer` default is how a replacement file viewer takes over reveals.
    private static var fileViewerBundleID: String {
        UserDefaults.standard.string(forKey: "NSFileViewer") ?? "com.apple.finder"
    }

    /// No AppKit route for Get Info, so this drives Finder over Apple events — seconds when cold.
    static func showInfoInFinder(_ url: URL) async -> Bool {
        let source = """
            tell application "Finder"
                activate
                open information window of (POSIX file "\(url.path)" as alias)
            end tell
            """
        return await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return false }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            return errorInfo == nil
        }.value
    }

    @MainActor
    static func openSettingsPane(bundleID: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + bundleID) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Focus the app if it isn't frontmost, hide it if it is, launch it if it isn't running.
    @MainActor
    static func toggle(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first
        if let running, running.isActive {
            running.hide()
            return
        }
        if let url = running?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            // Dock-click semantics; a bare `activate()` does none of it reliably.
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let running {
            // Running app whose bundle URL can't be resolved (moved or deleted since launch).
            running.unhide()
            running.activate()
        }
    }

    @MainActor
    @discardableResult
    static func quit(bundleID: String, url: URL? = nil, force: Bool = false) -> Bool {
        let running = runningApplications(bundleID: bundleID, at: url)
        for app in running {
            if force { app.forceTerminate() } else { app.terminate() }
        }
        return !running.isEmpty
    }

    /// Long enough for any app to exit, short enough not to relaunch under the user.
    private static let exitGrace = Duration.seconds(5)

    /// A refused quit — a save sheet left standing — relaunches nothing.
    @MainActor
    static func restart(bundleID: String, url: URL) async {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        let running = runningApplications(bundleID: bundleID, at: target)
        guard !running.isEmpty, !Task.isCancelled, await quitAwaitingExit(running), !Task.isCancelled
        else { return }
        launch(target, allowsRunningApplicationSubstitution: false)
    }

    @MainActor
    static func quitAwaitingExit(bundleID: String, url: URL) async -> Bool {
        let running = runningApplications(bundleID: bundleID, at: url)
        return await quitAwaitingExit(running)
    }

    @MainActor
    private static func runningApplications(bundleID: String, at url: URL?) -> [NSRunningApplication] {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let target = url?.resolvingSymlinksInPath().standardizedFileURL else { return running }
        return running.filter { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == target }
    }

    @MainActor
    private static func quitAwaitingExit(_ apps: [NSRunningApplication]) async -> Bool {
        guard !Task.isCancelled else { return false }
        for app in apps { app.terminate() }

        let deadline = ContinuousClock.now + exitGrace
        while apps.contains(where: { !$0.isTerminated }) {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }

    /// Finder is never a Quit All target: `terminate()` only makes it relaunch.
    private static let quitAllExclusions: Set<String> = ["com.apple.finder"]

    /// Every app with a Dock presence, bar Finder and us; resolved once, so it can't drift.
    @MainActor
    static func quitAllTargets() -> [NSRunningApplication] {
        // By PID, not policy: About/Settings flips us to `.regular` temporarily.
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ownPID
                && !quitAllExclusions.contains(app.bundleIdentifier ?? "")
        }
    }
}
