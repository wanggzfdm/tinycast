import Foundation

enum CommandCatalog {
    /// Sorted by name for the `AppIndex` invariant; the URL is a placeholder.
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .filter { !$0.isQueryDriven }
        .map { makeEntry($0) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    nonisolated static func entries(ownedBy owner: SettingsTab) -> [AppEntry] {
        owner.ownedCommands.map { makeEntry($0) }
    }

    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }

    /// From the catalog, not `AppIndex`: a disabled feature's command is absent from the index.
    static func entry(for command: CommandID) -> AppEntry? {
        all.first { $0.id == command.rawValue }
    }

    /// A query-driven row answers one query, so learning or pinning it would misrank a URL.
    static func isQueryDriven(_ entry: AppEntry) -> Bool {
        command(for: entry)?.isQueryDriven ?? false
    }

    /// The row a typed web address earns; unlike a catalog entry, its URL is the real destination.
    static func openInBrowser(for query: String) -> AppEntry? {
        guard case .web(let url)? = QuicklinkDestination.detect(query) else { return nil }
        return makeEntry(.openInBrowser, url: url, subtitle: String(localized: "URL"))
    }

    static func contentMatches(for query: String, pasted: Bool = false) -> [AppEntry] {
        let path = expandedPath(query)
        var matches: [AppEntry] = []
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            // A folder earns both a terminal and a Finder row; a file only Finder.
            if isDirectory.boolValue, let terminal = openInTerminal(for: path) {
                matches.append(terminal)
            }
            if let finder = revealInFinder(for: path) { matches.append(finder) }
            if let code = openInVisualStudioCode(for: path) { matches.append(code) }
            // Clipboard text is an explicit one-shot input, so even a path translates;
            // a typed path stays path-only, or every keystroke prefix would add noise.
            if pasted, let translate = translateRow(for: query, allowingPath: true) {
                matches.append(translate)
            }
            return matches
        }
        if let json = jsonFormatter(for: query) { return [json] }
        if let translate = translateRow(for: query) { matches.append(translate) }
        if let bigBang = bigBangRow(for: query) { matches.append(bigBang) }
        if let reminder = reminder(for: query) { matches.append(reminder) }
        return matches
    }

    static var hasVisualStudioCode: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app")
    }

    private static func expandedPath(_ query: String) -> String {
        NSString(string: query.trimmingCharacters(in: .whitespacesAndNewlines))
            .expandingTildeInPath
    }

    private static func openInTerminal(for path: String) -> AppEntry? {
        makeEntry(.openInTerminal, url: URL(fileURLWithPath: path), subtitle: path)
    }

    private static func revealInFinder(for path: String) -> AppEntry? {
        makeEntry(.revealInFinder, url: URL(fileURLWithPath: path), subtitle: path)
    }

    private static func openInVisualStudioCode(for path: String) -> AppEntry? {
        guard hasVisualStudioCode else { return nil }
        return makeEntry(.openInVisualStudioCode, url: URL(fileURLWithPath: path), subtitle: path)
    }

    private static func jsonFormatter(for query: String) -> AppEntry? {
        guard JSONTool.isValid(query) else { return nil }
        // The URL carries the exact source: a generic JSON command must never discard it.
        return makeEntry(.jsonFormatter, url: jsonToolURL(text: query), subtitle: "JSON")
    }

    /// Plain typed text becomes a one-keystroke reminder; paths and JSON are already taken above.
    static func reminder(for query: String) -> AppEntry? {
        let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.hasPrefix("/") else { return nil }
        return makeEntry(.createReminder, url: reminderURL(title: title), subtitle: title)
    }

    /// A content row that reuses the Translate quick action's id; only its carried text differs.
    static func translateRow(for query: String, allowingPath: Bool = false) -> AppEntry? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, allowingPath || !text.hasPrefix("/") else { return nil }
        return AppEntry(
            id: CommandID.translate.rawValue, name: "翻译", url: textURL(text: text),
            bundleID: nil, kind: .command, subtitle: text,
            alternateTitles: [CommandID.translate.englishName],
            iconOverride: appIcons[.translate])
    }

    /// Clipboard text opens the word picker directly; the generic command grabs a selection instead.
    static func bigBangRow(for query: String) -> AppEntry? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("/") else { return nil }
        return AppEntry(
            id: CommandID.bigBang.rawValue, name: "大爆炸", url: bigBangURL(text: text),
            bundleID: nil, kind: .command, subtitle: text,
            alternateTitles: [CommandID.bigBang.englishName],
            iconOverride: appIcons[.bigBang])
    }

    static func bigBangText(from entry: AppEntry) -> String? {
        guard CommandID(rawValue: entry.id) == .bigBang,
            let components = URLComponents(url: entry.url, resolvingAgainstBaseURL: false),
            let encoded = components.queryItems?.first(where: { $0.name == "text" })?.value,
            let data = Data(base64Encoded: encoded),
            let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }

    private static func bigBangURL(text: String) -> URL {
        var components = URLComponents(string: "tinycast://command/bigbang")!
        components.queryItems = [URLQueryItem(name: "text", value: Data(text.utf8).base64EncodedString())]
        return components.url!
    }

    static func translateText(from entry: AppEntry) -> String? {
        guard CommandID(rawValue: entry.id) == .translate,
            let components = URLComponents(url: entry.url, resolvingAgainstBaseURL: false),
            let encoded = components.queryItems?.first(where: { $0.name == "text" })?.value,
            let data = Data(base64Encoded: encoded),
            let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }

    private static func textURL(text: String) -> URL {
        var components = URLComponents(string: "tinycast://command/translate")!
        components.queryItems = [URLQueryItem(name: "text", value: Data(text.utf8).base64EncodedString())]
        return components.url!
    }

    static func reminderTitle(from entry: AppEntry) -> String? {
        guard CommandID(rawValue: entry.id) == .createReminder,
            let components = URLComponents(url: entry.url, resolvingAgainstBaseURL: false),
            let encoded = components.queryItems?.first(where: { $0.name == "text" })?.value,
            let data = Data(base64Encoded: encoded),
            let title = String(data: data, encoding: .utf8)
        else { return nil }
        return title
    }

    private static func reminderURL(title: String) -> URL {
        var components = URLComponents(string: "tinycast://command/create-reminder")!
        components.queryItems = [URLQueryItem(name: "text", value: Data(title.utf8).base64EncodedString())]
        return components.url!
    }

    static func jsonToolText(from entry: AppEntry) -> String? {
        guard CommandID(rawValue: entry.id) == .jsonFormatter,
            let components = URLComponents(url: entry.url, resolvingAgainstBaseURL: false),
            let encoded = components.queryItems?.first(where: { $0.name == "text" })?.value,
            let data = Data(base64Encoded: encoded),
            let text = String(data: data, encoding: .utf8), JSONTool.isValid(text)
        else { return nil }
        return text
    }

    private static func jsonToolURL(text: String) -> URL {
        var components = URLComponents(string: "tinycast://command/json-formatter")!
        components.queryItems = [URLQueryItem(name: "text", value: Data(text.utf8).base64EncodedString())]
        return components.url!
    }

    /// Absolute-path text that names nothing on disk. Chip-only feedback: typed text hits this
    /// mid-keystroke (every prefix of a real path is missing), so it must never row from typing.
    static func isMissingPath(_ text: String) -> Bool {
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && path.count > 1
            && !FileManager.default.fileExists(atPath: path)
    }

    /// A command's row, built rather than looked up — `all` holds none of the query-driven ones.
    /// Commands that act through a fixed system app draw that app's real icon, not a glyph.
    private static let appIcons: [CommandID: EntryIcon] = [
        .revealInFinder: .bundle(path: "/System/Library/CoreServices/Finder.app"),
        .openInTerminal: .bundle(path: "/System/Applications/Utilities/Terminal.app"),
        .openInVisualStudioCode: .bundle(path: "/Applications/Visual Studio Code.app"),
        // Stock-calendar red, so the web calendar reads as 日历 at tile size.
        .webCalendar: .tintedSymbol(name: "calendar", tint: .calendarRed),
        // The real Reminders app icon, so 添加提醒 reads as 提醒事项 at tile size.
        .createReminder: .bundle(path: "/System/Applications/Reminders.app"),
        .translate: .tintedSymbol(name: "translate", tint: .translateBlue),
        .bigBang: .tintedSymbol(name: "atom", tint: .bigBangPurple),
    ]

    nonisolated static func makeEntry(
        _ id: CommandID, url: URL? = nil, subtitle: String? = nil
    ) -> AppEntry {
        AppEntry(
            id: id.rawValue, name: id.name, url: url ?? placeholderURL(id), bundleID: nil,
            kind: id.entryKind, settingsOwner: id.owner, subtitle: subtitle,
            alternateTitles: [id.englishName],
            iconOverride: appIcons[id])
    }

    nonisolated private static func placeholderURL(_ id: CommandID) -> URL {
        URL(string: "tinycast://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!
    }
}

/// The commands a pane lists itself; its own switch, not `Enable Commands`, decides they exist.
extension SettingsTab {
    var ownedCommands: [CommandID] {
        switch self {
        case .commands: [.createCustomCommand, .searchCustomCommands]
        case .quicklinks:
            [.createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks]
        case .ai: [.quickAI, .aiChat]
        case .quickActions: [.fixGrammar, .rewrite, .translate, .summarize]
        case .fileSearch: [.searchFiles]
        case .notes: [.showNotes, .createNote, .searchNotes]
        case .snippets: [.searchSnippets, .createSnippet]
        case .navigation: [.switchWindows, .switchWindowsBackwards, .searchMenuItems]
        case .windowManagement:
            [.createWindowLayout, .captureWindowLayout, .switchRoom, .createRoom]
        case .clipboard: [.clipboardHistory, .pasteSequentially]
        case .emoji: [.searchEmoji]
        case .calendar:
            [.joinNextMeeting, .mySchedule, .createEvent, .copyMeetingLink, .openInCalendar]
        default: []
        }
    }
}

extension CommandID {
    /// The pane that lists this command's controls; nil leaves it to Settings › Commands.
    var owner: SettingsTab? { Self.owners[self] }

    nonisolated private static let owners: [CommandID: SettingsTab] =
        SettingsTab.allCases.reduce(into: [:]) { table, tab in
            for command in tab.ownedCommands { table[command] = tab }
        }

    var entryKind: AppEntry.Kind {
        builtInQuickAction == nil ? .command : .quickAction
    }
}
