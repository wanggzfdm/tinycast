import SwiftUI

/// A translation result card: original text up top, translation below, both selectable.
/// A fixed width is what makes the text wrap: HUD sizes from `fittingSize`, and Text only
/// breaks lines once width is bounded, so an adaptive card would stay one long line.
struct TranslationHUDView: View {
    let source: String
    let translation: String
    var phonetics: PhoneticsStore? = nil
    var speech: SpeechSpeaker? = nil
    var onOpen: (() -> Void)? = nil

    @State private var copied = false
    @State private var copiedReset: Task<Void, Never>?
    @State private var ipa: String?

    private static let width: CGFloat = 440
    private static let corner: CGFloat = 20
    private static let glowOpacity = 0.14
    private static let rimOpacity = 0.25

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.blue)
                Text("翻译", comment: "Translation HUD title")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if copied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("已复制", comment: "Translation HUD copied hint")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(source)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if let speech {
                        Button {
                            speech.speak(source, language: TextTranslator.sourceLanguage(of: source))
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "朗读原文", comment: "Translation HUD speak hint"))
                    }
                }
                if let ipa, !ipa.isEmpty {
                    Text(ipa)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(translation)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
                    // No textSelection here: a selectable Text hands taps to its text view,
                    // and the copy gesture below would never fire.
                    .lineLimit(12)
                    .help(String(localized: "点击译文复制", comment: "Translation HUD copy hint"))
                    .onTapGesture { copyTranslation() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: Self.width, alignment: .leading)
        .background(glow)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(Color.white.opacity(Self.rimOpacity), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(10)
        }
        .onTapGesture { onOpen?() }
        .task(id: source) {
            guard TextTranslator.isEnglishWord(source) else {
                ipa = nil
                return
            }
            ipa = await phonetics?.phonetics(for: source)
        }
    }

    /// The inner tap beats the card's open gesture; the reset task cancels so a rapid
    /// second copy never clears the checkmark early.
    private func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)
        copied = true
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private var glow: some View {
        RoundedRectangle(cornerRadius: Self.corner, style: .continuous).fill(
            LinearGradient(
                colors: [Color.blue.opacity(Self.glowOpacity), .clear],
                startPoint: .topLeading, endPoint: .bottom))
    }
}
