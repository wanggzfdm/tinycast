import AppKit
import SwiftUI

/// The JSON tool's window lifecycle: it is its own surface, so it owns its own window.
@MainActor
final class JSONToolCoordinator {
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: String(localized: "JSON Tool"), contentSize: JSONToolWindowView.initialSize,
        minimumSize: CGSize(width: 400, height: 320), resizable: true,
        activation: core.activationPolicy, alwaysOnTop: true)

    init(core: AppCore) {
        self.core = core
    }

    /// The palette editor's live text, synced by `JSONToolWindowView`, so a detach carries it.
    var currentText = ""

    func show(text: String) {
        window.show {
            ToolWindowChrome {
                JSONToolWindowView(coordinator: self, initialText: text)
                    .environment(self.core.settings)
            }
        }
    }

    /// The ⋮ menu's detach: the standalone window continues from the palette's current text.
    func showDetached() {
        show(text: currentText)
    }

    func focusExisting() -> Bool {
        window.focus()
    }

    func copy(_ text: String) {
        Paster.copyPlainText(text)
    }

    /// Escape from the palette mode: pop back to the launcher (or hide), like the web tool.
    func closePanel() {
        if !core.palette.pop() { core.paletteCoordinator.hidePalette() }
        core.windowController.reposition()
    }
}