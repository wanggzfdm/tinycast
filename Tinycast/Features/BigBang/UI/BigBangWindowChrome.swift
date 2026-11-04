import AppKit
import SwiftUI

/// Big Bang's true glass window: the window body turns transparent (`BigBangWindowChrome`)
/// so the system glass samples the desktop, and the tool content mounts as the glass's
/// `contentView` — the only placement whose z-order the effect guarantees.
struct BigBangWindowContent: View {
    let source: String
    var phonetics: PhoneticsStore?
    var speech: SpeechSpeaker?

    var body: some View {
        BigBangScreen(source: source, phonetics: phonetics, speech: speech)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlassEffectView(cornerRadius: 0) { EmptyView() }.ignoresSafeArea())
    }
}

/// Marks Big Bang's window as a glass-backed one: the window body must be transparent, or
/// the glass samples the window's own fill instead of the desktop behind it.
@MainActor
final class BigBangWindowChrome: WindowChrome {
    func install(in window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
