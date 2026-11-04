import AppKit
import SwiftUI

@MainActor
final class MessageHUDController {
    private let presenter: HUDPresenter
    private let settings: AppSettings
    private let phonetics: PhoneticsStore
    private let speech: SpeechSpeaker

    init(
        settings: AppSettings, phonetics: PhoneticsStore, speech: SpeechSpeaker
    ) {
        self.settings = settings
        self.phonetics = phonetics
        self.speech = speech
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset),
            dwell: Theme.Duration.messageHUD,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
    }

    func show(message: String, tone: DialogTone = .success) {
        presenter.show(
            MessageHUDView(message: message, accessory: .tone(tone)).environment(\.metrics, metrics))
    }

    /// A translation result with its source text; tapping it opens Big Bang for word picking.
    func showTranslation(
        source: String, translation: String, phonetics: PhoneticsStore, speech: SpeechSpeaker,
        onOpen: @escaping () -> Void
    ) {
        presenter.show(
            TranslationHUDView(
                source: source, translation: translation,
                phonetics: phonetics, speech: speech, onOpen: onOpen),
            dwells: true,
            interactive: true)
    }

    /// Stays up until the work it reports ends and something replaces it, or `dismiss()` runs.
    func showProgress(message: String, onCancel: (() -> Void)? = nil) {
        presenter.show(
            MessageHUDView(message: message, accessory: .progress, onCancel: onCancel)
                .environment(\.metrics, metrics),
            dwells: false,
            interactive: onCancel != nil)
    }

    func dismiss() {
        presenter.dismiss()
    }

    private var metrics: InterfaceMetrics { settings.interfaceSize.metrics }
}
