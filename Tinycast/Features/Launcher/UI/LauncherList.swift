import SwiftUI

struct LauncherList: View {

    @Environment(\.metrics) private var metrics
    let results: [AppEntry]
    /// The flat row id the screen has selected, not an entry id: a fallback can repeat a result.
    let selectedRowID: String?
    let favoriteCount: Int
    let meetingCount: Int
    let suggestionCount: Int
    let matchCount: Int
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    /// The card at flat index 0, when one leads. At most one ever does.
    var card: LeadCard?
    var cardSelected = false
    var onActivateCard: () -> Void = {}
    var onCardActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onDropped: () -> Void
    var files: FileSection?
    /// The `Use "…" with` section, always last; nil when nothing is typed.
    var fallbacks: FallbackSection?
    @Environment(RunningAppsMonitor.self) private var runningApps

    /// What the fallback section draws and where its rows go, addressed by position.
    struct FallbackSection {
        let title: String
        let entries: [AppEntry]
        let onActivate: (Int) -> Void
        let onActions: (Int) -> Void
        let onConfigure: () -> Void
    }

    struct FileSection {
        let results: [FileSearchResult]
        let onActivate: (Int) -> Void
        let onActions: (Int) -> Void
    }

    /// Calc answers a typed query and the card an empty one, so only one ever leads.
    enum LeadCard: Equatable {
        case calc(CalcResult)
        case meeting(MeetingEvent, now: Date)
        case color(ColorValue)

        var sectionTitle: String {
            switch self {
            case .calc: return String(localized: "Calculator")
            case .meeting: return String(localized: "Meeting")
            case .color: return String(localized: "Color")
            }
        }

        var rowID: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            case .color: return "color-card"
            }
        }
    }

    private enum Row: Identifiable {
        case header(String)
        /// Its own case, because only this header carries a gear.
        case fallbackHeader(String)
        case card(LeadCard)
        /// `slot` is the row's ⌘-digit, carried from the section build rather than searched.
        case app(AppEntry, slot: Character?)
        case file(FileSearchResult, index: Int)
        case fallback(AppEntry, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .fallbackHeader: return "fallback-header"
            case .card(let card): return card.rowID
            case .app(let app, _): return app.id
            case .file(let result, _): return "file-" + result.id
            case .fallback(let app, _): return "fallback-" + app.id
            }
        }
    }

    private var firstRowSelected: Bool {
        card != nil ? cardSelected : selectedRowID != nil && selectedRowID == results.first?.id
    }

    private var fileRows: [Row] {
        guard let files else { return [] }
        return [.header(String(localized: "Files"))]
            + files.results.enumerated().map { Row.file($1, index: $0) }
    }

    /// Every row the fallback section contributes, always after the results.
    private var fallbackRows: [Row] {
        guard let fallbacks else { return [] }
        return [.fallbackHeader(fallbacks.title)]
            + fallbacks.entries.enumerated().map { Row.fallback($1, index: $0) }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let card { rows = [.header(card.sectionTitle), .card(card)] }
        let favorites = results.prefix(favoriteCount)
        let meetings = results.dropFirst(favoriteCount).prefix(meetingCount)
        let suggestions = results.dropFirst(favoriteCount + meetingCount).prefix(suggestionCount)
        let pinnedCount = favoriteCount + meetingCount + suggestionCount
        let matches = results.dropFirst(pinnedCount).prefix(matchCount)
        let rest = results.dropFirst(pinnedCount + matchCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !favorites.isEmpty {
            rows.append(.header(String(localized: "Favorites")))
            rows.append(
                contentsOf: favorites.enumerated().map {
                    .app($1, slot: FavoriteSlots.digit(at: $0))
                })
        }
        if !meetings.isEmpty {
            rows.append(.header(String(localized: AppEntry.Kind.meeting.descriptor.sectionTitle)))
            rows.append(contentsOf: meetings.map { .app($0, slot: nil) })
        }
        if !suggestions.isEmpty {
            rows.append(.header(String(localized: "Suggestions")))
            rows.append(contentsOf: suggestions.map { .app($0, slot: nil) })
        }
        if !matches.isEmpty {
            rows.append(.header(String(localized: "Results")))
            rows.append(contentsOf: matches.map { .app($0, slot: nil) })
        }
        // Publication order, so rows match the flat index.
        let kinds: [AppEntry.Kind] = [
            .meeting, .application, .systemSettings, .extensionCommand, .quicklink, .appleShortcut,
            .snippet, .systemAction, .windowLayout, .windowRoom, .windowCommand, .customCommand,
            .quickAction, .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(String(localized: kind.descriptor.sectionTitle)))
            rows.append(contentsOf: group.map { .app($0, slot: nil) })
        }
        // A missing kind would make every later row activate its neighbour: assert instead.
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return rows + fileRows + fallbackRows
    }

    /// A run of app rows renders as one grid; anything else stands alone as a vertical row.
    private enum Block: Identifiable {
        case single(Row)
        case grid([Row])
        var id: String {
            switch self {
            case .single(let row): return row.id
            case .grid(let rows): return "grid-" + (rows.first?.id ?? "grid")
            }
        }
    }

    /// Collapse each run of adjacent app rows into a grid block so tiles lay out side by side.
    private var blocks: [Block] {
        let rows = rows
        var blocks: [Block] = []
        var run: [Row] = []
        func flush() {
            guard !run.isEmpty else { return }
            blocks.append(.grid(run))
            run = []
        }
        for row in rows {
            if case .app = row {
                run.append(row)
            } else {
                flush()
                blocks.append(.single(row))
            }
        }
        flush()
        return blocks
    }

    private var gridColumns: Int { 6 }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && card == nil && files == nil && fallbacks == nil {
                EmptyResults(text: String(localized: "No apps found"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(blocks) { block in
                                switch block {
                                case .grid(let appRows):
                                    AppGridBlock(
                                        tiles: appRows.compactMap {
                                            guard case .app(let app, let slot) = $0 else { return nil }
                                            return AppGridBlock.Tile(app: app, slot: slot)
                                        },
                                        columns: gridColumns,
                                        selectedRowID: selectedRowID,
                                        running: { runningApps.isRunning($0) },
                                        onActivate: onActivate,
                                        onActions: onActions,
                                        dragFor: { drag(for: $0) })
                                case .single(let row):
                                    switch row {
                                    case .header(let title):
                                        SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                    case .fallbackHeader(let title):
                                        SectionHeader(
                                            title: title, isFirst: row.id == rows.first?.id,
                                            configure: fallbacks?.onConfigure,
                                            configureHelp: String(localized: "Configure Fallbacks…"))
                                    case .card(let card):
                                        LeadCardView(card: card, selected: cardSelected)
                                            .contentShape(Rectangle())
                                            .onTapGesture(perform: onActivateCard)
                                            .onRightClick(perform: onCardActions)
                                            .padding(.bottom, metrics.spacing.xs)
                                            .selectionFrame(cardSelected)
                                    case .app(let app, let slot):
                                        AppRow(
                                            app: app,
                                            selected: app.id == selectedRowID,
                                            running: runningApps.isRunning(app),
                                            slot: slot
                                        )
                                        .contentShape(Rectangle())
                                        .onRowTap(drag: drag(for: app)) { onActivate(app) }
                                        .onRightClick { onActions(app) }
                                        .selectionFrame(app.id == selectedRowID)
                                    case .file(let result, let index):
                                        FileSearchRow(
                                            result: result, selected: row.id == selectedRowID,
                                            showsLocation: true
                                        )
                                        .contentShape(Rectangle())
                                        .onRowTap(drag: result.rowDrag(dropped: onDropped)) {
                                            files?.onActivate(index)
                                        }
                                        .onRightClick { files?.onActions(index) }
                                        .selectionFrame(row.id == selectedRowID)
                                    case .fallback(let app, let index):
                                        AppRow(
                                            app: app, selected: row.id == selectedRowID, running: false,
                                            slot: nil
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture { fallbacks?.onActivate(index) }
                                        .onRightClick { fallbacks?.onActions(index) }
                                        .selectionFrame(row.id == selectedRowID)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, metrics.spacing.md)
                        .padding(.top, metrics.spacing.xs)
                        .padding(.bottom, metrics.spacing.md)
                        .hideNativeScrollers()
                        .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    // Snap to the origin on the first row so its header shows too.
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }

    /// Cache-only icon: the row holds its own smaller bitmap, and a decode would stall the drag.
    private func drag(for app: AppEntry) -> RowDrag? {
        guard app.canDragOut else { return nil }
        return RowDrag(
            item: { .file(app.url, image: IconCache.cached(app.iconSource, fileURL: app.url)) },
            dropped: onDropped)
    }
}

/// Draws whichever card leads; each feature still owns how its own card looks.
private struct LeadCardView: View {
    let card: LauncherList.LeadCard
    let selected: Bool

    var body: some View {
        switch card {
        case .calc(let result):
            CalculatorCard(result: result, selected: selected)
        case .meeting(let meeting, let now):
            MeetingCard(meeting: meeting, now: now, selected: selected)
        case .color(let color):
            ColorCard(color: color, selected: selected)
        }
    }
}

private struct AppRow: View {

    @Environment(\.metrics) private var metrics
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// This row's ⌘-digit, or nil for a row no chord launches.
    let slot: Character?
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @Environment(HotKeyManager.self) private var hotKeys
    /// Observed for the same reason: an alias edit re-renders the row's badge at once.
    @Environment(AliasStore.self) private var aliases
    /// Observed here rather than up in the list, so a ⌘ press re-renders rows and not the palette.
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            AppIconView(app: app, pointSize: metrics.size.resultRowIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            if app.kind == .meeting {
                MeetingEntryContent(entryID: app.id) { meeting, _ in
                    CalendarBar(color: meeting.calendarColor)
                }
            }
            Text(app.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            if let refresh = app.backgroundRefresh {
                ExtensionRefreshIndicator(state: refresh)
                    .font(metrics.typography.rowTrailing)
            }
            if let slot, palette.commandHeld {
                HStack(spacing: metrics.spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            } else if app.kind == .meeting {
                MeetingEntryContent(entryID: app.id) { MeetingTiming(meeting: $0, now: $1) }
            } else {
                Text(app.kindLabel)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// A section's app rows laid out as side-by-side tiles: icon on top, name below, the
/// uTools-style block grid the launcher presents its results in.
private struct AppGridBlock: View {

    struct Tile: Identifiable {
        let app: AppEntry
        let slot: Character?
        var id: String { app.id }
    }

    @Environment(\.metrics) private var metrics
    let tiles: [Tile]
    let columns: Int
    let selectedRowID: String?
    let running: (AppEntry) -> Bool
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let dragFor: (AppEntry) -> RowDrag?

    private var tileColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: metrics.spacing.xs), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: tileColumns, spacing: metrics.spacing.xs) {
            ForEach(tiles) { tile in
                AppTile(
                    app: tile.app, slot: tile.slot,
                    selected: tile.app.id == selectedRowID,
                    running: running(tile.app),
                    drag: dragFor(tile.app),
                    onActivate: { onActivate(tile.app) },
                    onActions: { onActions(tile.app) })
            }
        }
        .padding(.vertical, metrics.spacing.xs)
    }
}

/// One tile in the results grid: a square icon and a two-line name, with a selection ring.
private struct AppTile: View {

    @Environment(\.metrics) private var metrics
    let app: AppEntry
    let slot: Character?
    let selected: Bool
    let running: Bool
    let drag: RowDrag?
    let onActivate: () -> Void
    let onActions: () -> Void

    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        VStack(spacing: metrics.spacing.xs) {
            AppIconView(app: app, pointSize: 40)
                .frame(width: 40, height: 40)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle().fill(.secondary).frame(width: 5, height: 5).offset(y: 1)
                    }
                }
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if let slot, palette.commandHeld {
                HStack(spacing: metrics.spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
                .allowsHitTesting(false)
            }
        }
        .padding(.vertical, metrics.spacing.sm)
        .padding(.horizontal, metrics.spacing.xxs)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .strokeBorder(selected ? Theme.Colors.selection : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onRowTap(drag: drag, perform: onActivate)
        .onRightClick(perform: onActions)
        .armedHover($hovered)
    }
}
