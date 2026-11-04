import AVFoundation

/// Local, permission-free TTS: one synthesizer owned by AppCore, callers only ask to speak.
@MainActor
final class SpeechSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: Locale.Language?) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        if let code = language?.languageCode?.identifier {
            utterance.voice = AVSpeechSynthesisVoice(language: code)
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
