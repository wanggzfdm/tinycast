# Fork Ledger

This fork is one squashed commit on top of `upstream/main`: every difference from upstream
lives in that single commit, and this ledger says what is in it and why. Keep it updated with
the commit — it is the checklist for the next rebase.

## Syncing with upstream

```sh
git fetch upstream
git rebase upstream/main main   # replays the one fork commit; resolve conflicts per this ledger
git push --force-with-lease origin main
```

Conflicts historically land in: `project.yml` (the dev-channel removal vs upstream's Debug
config), `docs/development.md` (same), `BundleLocalization.swift` (upstream evolves its own
Chinese-region handling), `Localizable.xcstrings` (both sides add keys), and the launcher UI
files (upstream rewrites rows; the grid and content rows below must be re-applied).

## What the fork commit carries

1. **No Dev channel, no software update** — `project.yml` has no Debug overrides
   (`Tinycast.app` / `com.tinycast.app` at every configuration) and the check-for-updates
   command, settings and `UpdateCoordinator` wiring are deleted. Never restore either: builds
   install straight into `/Applications` (see `docs/development.md`), and updates come from git.
2. **JSON tool** — `Features/JSON/` (model, screen, coordinator, tests) plus its seams:
   `PaletteMode.jsonTool`, `PaletteState.jsonToolText`, `LauncherCoordinator` navigation,
   `CommandID.jsonFormatter`, a `RootPaletteView` screen case, and wide-panel sizing in
   `PaletteWindowController.positionPanel`. Evaluates JS expressions via JavaScriptCore.
3. **Paste chip + content matching** — `PasteToChipInterceptor` and `PastedTextChip` in
   `RootPaletteView`, `PaletteState.pastedText`, `ClipboardAutofillPolicy` (5-minute
   freshness), and `CommandCatalog.contentMatches` (path → Finder/Terminal rows, JSON →
   formatter, plus the clipboard-file row). `LauncherScreen` inserts these rows after the
   favorites slice and passes `pastedText` as the activation query.
4. **Results grid** — `LauncherList` collapses runs of app/favorite rows into
   `AppGridBlock`/`AppTile`; `LauncherScreen.move(_:axis:from:)` navigates the grid by
   section. Upstream renders vertical rows and has no grid navigation — expect this hunk to
   conflict on every launcher-list rewrite upstream.
5. **Chinese apps and commands** — `BundleLocalization.scriptForms` maximizes a region-only
   tag (zh-CN → zh-Hans) so `zh-Hans.lproj` names are indexed; the launcher therefore
   displays and matches 微信-style names. Also: `.bundle(path:)` real-app icons for the
   Finder/Terminal rows, and localization entries for the three newer command names.
6. **Tool chrome** — a `PaletteScreen.toolTitle` (default `nil`) docks a ZTools-style pill
   (`ToolTitleBar` in `RootPaletteView`) where the search field sits: badge, name, ✕. The pill
   replaces the back chevron, and the header grows a bottom margin while it shows. Screens set
   `toolTitle` to opt in — today the JSON tool and extension forms. Note: the requirement must
   live in the protocol declaration itself; an extension-only default is statically dispatched
   through the `any PaletteScreen` existential and silently ignores overrides.
7. **Toolchain compatibility** — `HyperKeyEngine` spells out the init that Xcode 27's
   memberwise rules no longer need, so one source compiles on Xcode 26 and 27. Drop this when
   the repo requires Xcode 27 everywhere.
8. **Web calendar** — `Features/WebTool/` renders `toy.lion1ou.tech/calendar` (the URL is
   user-specific, see `WebToolCoordinator.calendarURL`) in a retained `WKWebView` with a
   persistent data store. The `webCalendar` command opens it as a `.webTool` palette mode —
   tool pill on top, page below, JSON-tool sizing (900×680). Both tool screens mount
   `ToolEscapePopper` (in `WebToolScreen.swift`), a local Escape monitor that pops to the
   launcher before the page or editor swallows the key. The coordinator also carries an
   unused standalone-window path (`show(url:)`) for a later surface.
9. **Deep-link consent** — `DeepLinkConsentPolicy` classes the fork's own commands
   (`.jsonFormatter`, `.openInTerminal`, `.revealInFinder`, `.webCalendar`) and never
   references the deleted `.checkForUpdates`.
