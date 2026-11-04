import SwiftUI
import WebKit

/// The web tool's whole surface: the coordinator's retained web view, filling the window.
struct WebToolWindowView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
