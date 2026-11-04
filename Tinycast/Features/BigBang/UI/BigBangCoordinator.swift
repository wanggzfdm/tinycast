import AppKit
import SwiftUI

/// The Big Bang surface's window lifecycle: one floating window, re-seeded per translation.
@MainActor
final class BigBangCoordinator {
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: String(localized: "选择词语翻译"), contentSize: CGSize(width: 720, height: 520),
        minimumSize: CGSize(width: 480, height: 360), resizable: true,
        activation: core.activationPolicy, alwaysOnTop: true, transparentBody: true)

    init(core: AppCore) {
        self.core = core
    }

    /// Opens with the translation card's source text; a second open re-seeds in place.
    func open(text: String) {
        window.show(chrome: BigBangWindowChrome()) {
            BigBangWindowContent(
                source: text, phonetics: self.core.phoneticsStore,
                speech: self.core.speechSpeaker)
        }
    }
}
