import SwiftUI

/// The system glass material as a backdrop; content and corner radius are forwarded to
/// `NSGlassEffectView`, whose `contentView` is the only placement it guarantees z-order for.
struct GlassEffectView<Content: View>: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    @ViewBuilder var content: () -> Content

    init(cornerRadius: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.contentView = NSHostingView(rootView: content())
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        guard let hosting = nsView.contentView as? NSHostingView<Content> else { return }
        hosting.rootView = content()
        nsView.cornerRadius = cornerRadius
    }
}

/// The callers that want only the material, with no content to embed.
extension GlassEffectView where Content == EmptyView {
    init() {
        self.init(cornerRadius: 0) { EmptyView() }
    }
}
