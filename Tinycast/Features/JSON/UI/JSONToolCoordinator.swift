import AppKit
import SwiftUI

/// The JSON tool's window lifecycle: it is its own surface, so it owns its own window.
@MainActor
final class JSONToolCoordinator {
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: String(localized: "JSON Tool"), contentSize: JSONToolWindowView.initialSize,
        minimumSize: CGSize(width: 400, height: 320), resizable: true,
        activation: core.activationPolicy)

    init(core: AppCore) {
        self.core = core
    }

    func show(text: String) {
        window.show {
            JSONToolWindowView(coordinator: self, initialText: text)
                .environment(self.core.settings)
        }
    }

    func focusExisting() -> Bool {
        window.focus()
    }

    func copy(_ text: String) {
        Paster.copyPlainText(text)
    }
}