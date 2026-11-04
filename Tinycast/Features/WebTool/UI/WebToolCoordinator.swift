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
        // Only load when the destination actually differs, so reopening never resets the page.
        if webView.url != url { webView.load(URLRequest(url: url)) }
    }

    func focusExisting() -> Bool {
        window.focus()
    }

    /// The panel-mode web view: loads the calendar on first use, then keeps the session alive.
    func panelWebView() -> WKWebView {
        if webView.url == nil { webView.load(URLRequest(url: Self.calendarURL)) }
        return webView
    }

    /// Escape from the panel mode: pop the palette back to the launcher, or hide it outright.
    func closePanel() {
        if !core.palette.pop() { core.paletteCoordinator.hidePalette() }
        core.windowController.reposition()
    }

    static let calendarURL = URL(string: "https://toy.lion1ou.tech/calendar/#/")!
}
