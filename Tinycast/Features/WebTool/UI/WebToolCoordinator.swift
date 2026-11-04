import AppKit
import SwiftUI
import WebKit

/// The web tool's window lifecycle, JSON tool style: one surface whose web view is retained,
/// so the page — and any login the site granted — survives closing and reopening the window.
@MainActor
final class WebToolCoordinator {
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: String(localized: "Web Calendar"), contentSize: CGSize(width: 900, height: 680),
        minimumSize: CGSize(width: 480, height: 360), resizable: true,
        activation: core.activationPolicy, alwaysOnTop: true)
    @ObservationIgnored private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // Persistent store: the calendar's sign-in outlives the app, like a real browser would.
        configuration.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    @ObservationIgnored private var pageVersion: String?
    @ObservationIgnored private var refreshPending = false

    init(core: AppCore) {
        self.core = core
    }

    /// The ⋮ menu's detach target: wherever the panel was, or the calendar itself.
    func currentPageURL() -> URL {
        webView.url ?? Self.calendarURL
    }

    func show(url: URL) {
        // Explicitly leave the old hierarchy first; SwiftUI's teardown would race the re-add.
        webView.removeFromSuperview()
        window.show {
            ToolWindowChrome {
                WebToolWindowView(webView: self.webView)
            }
        }
        load(url, policy: WebToolLoadPolicy.resolve(
            hasLoadedPage: webView.url != nil, refreshPending: false))
    }

    func focusExisting() -> Bool {
        window.focus()
    }

    /// Opens immediately from the retained page, then checks for an update without delaying paint.
    func openPanel() {
        let policy = WebToolLoadPolicy.resolve(
            hasLoadedPage: webView.url != nil, refreshPending: refreshPending)
        refreshPending = false
        load(Self.calendarURL, policy: policy)
        checkForUpdate()
    }

    private func checkForUpdate() {
        Task { [weak self] in
            guard let version = await WebToolVersionChecker.version(at: Self.calendarDocumentURL) else { return }
            guard let self else { return }
            if let pageVersion, pageVersion != version { refreshPending = true }
            pageVersion = version
        }
    }

    /// The panel-mode web view only mounts the retained page; network work belongs to `openPanel()`.
    func panelWebView() -> WKWebView {
        webView
    }

    private func load(_ url: URL, policy: WebToolLoadPolicy?) {
        switch policy {
        case .initial:
            webView.load(URLRequest(url: url))
        case .refresh:
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(request)
        case nil:
            break
        }
    }

    /// Escape from the panel mode: pop the palette back to the launcher, or hide it outright.
    func closePanel() {
        if !core.palette.pop() { core.paletteCoordinator.hidePalette() }
        core.windowController.reposition()
    }

    static let calendarURL = URL(string: "https://toy.lion1ou.tech/calendar/#/")!
    private static let calendarDocumentURL = URL(string: "https://toy.lion1ou.tech/calendar/")!
}
