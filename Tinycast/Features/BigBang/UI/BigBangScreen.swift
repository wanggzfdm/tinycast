import NaturalLanguage
import SwiftUI

/// The Smartisan-style surface: the source explodes into word pills, the reader picks a few,
/// and only the picked words get translated.
struct BigBangScreen: View {
    let source: String
    var phonetics: PhoneticsStore? = nil
    var speech: SpeechSpeaker? = nil

    @State private var words: [BigBangWord] = []
    @State private var selected: Set<Int> = []
    @State private var selectionAnchor: Int?
    @State private var translation: String?
    @State private var loading = false
    @State private var error: String?
    @State private var copied = false
    @State private var copiedReset: Task<Void, Never>?
    @State private var resultHovered = false
    @State private var ipa: String?
    /// Drag selection: the pill frames the gesture hit-tests, and where the drag started.
    @State private var pillFrames: [Int: CGRect] = [:]
    @State private var dragAnchor: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.Colors.separator)
            ScrollView {
                WordFlowLayout(spacing: 10) {
                    ForEach(words) { word in
                        BigBangPill(word: word, isSelected: selected.contains(word.index)) {
                            toggle(word.index)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: PillFrameKey.self, value: [word.index: geo.frame(in: .named("pillSpace"))])
                            })
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(name: "pillSpace")
                .onPreferenceChange(PillFrameKey.self) { pillFrames.merge($0) { _, new in new } }
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("pillSpace"))
                    .onChanged { value in
                        if let anchor = dragAnchor {
                            selected = BigBang.dragSelection(tapped: hitPill(at: value.location) ?? anchor, anchor: anchor)
                        } else if let start = hitPill(at: value.startLocation) {
                            dragAnchor = start
                            selected = [start]
                        }
                    }
                    .onEnded { _ in dragAnchor = nil }
            )
            Divider().overlay(Theme.Colors.separator)
            footer
        }
        .background(Theme.Colors.cardFill)
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { words = BigBang.words(in: source) }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.contains(.command), !loading, !selected.isEmpty else {
                return .ignored
            }
            translateSelection()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "atom")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.purple)
            Text("选择词语翻译", comment: "Big Bang window title")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.85))
            Spacer()
            if !selected.isEmpty {
                Button("清空") {
                    selected.removeAll()
                    selectionAnchor = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func toggle(_ index: Int) {
        let extending = NSEvent.modifierFlags.contains(.shift)
        selected = BigBang.togglingSelection(
            selected, tapped: index, anchor: selectionAnchor, extending: extending)
        selectionAnchor = index
    }

    /// A drag selects the interval it swept: from its anchor to the pill under its head.
    private func hitPill(at point: CGPoint) -> Int? {
        pillFrames.first { $0.value.contains(point) }?.key
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    translateSelection()
                } label: {
                    HStack(spacing: 6) {
                        if loading { ProgressView().controlSize(.small) }
                        Text(loading ? "翻译中…" : "翻译所选")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(loading ? 0.5 : 0.9), Color.cyan.opacity(loading ? 0.35 : 0.7)],
                                startPoint: .top, endPoint: .bottom)))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.blue.opacity(loading ? 0 : 0.3), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(loading || selected.isEmpty)
                .opacity(selected.isEmpty ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(selectedDescription)
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
                    if !selectedText.isEmpty {
                        Text(selectedText)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color(white: 0.8))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
            }
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            if let translation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(translation)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 10) {
                            if let ipa, !ipa.isEmpty {
                                Text(ipa)
                                    .font(.system(size: 13, design: .serif))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            if let speech, let spoken = spokenText {
                                Button {
                                    speech.speak(
                                        spoken, language: TextTranslator.sourceLanguage(of: spoken))
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(String(localized: "朗读原文", comment: "Translation HUD speak hint"))
                            }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                            if resultHovered {
                                Button {
                                    copyTranslation()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(Theme.Colors.controlHover))
                                }
                                .buttonStyle(.plain)
                                .help(String(localized: "点击译文复制", comment: "Translation HUD copy hint"))
                                .padding(6)
                            }
                        }
                        .onHover { resultHovered = $0 }
                    }
                .frame(maxHeight: 170)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Colors.controlSurface))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.Colors.separator, lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var selectedDescription: String {
        selected.isEmpty ? "点选词语后翻译 · ⌘↵" : "已选 \(selected.count) 个词 · ⌘↵ 翻译"
    }

    /// Speech follows the translated text, not the whole source: the selection is what the
    /// reader is studying, and Big Bang exists precisely to narrow it down.
    private var spokenText: String? {
        selected.isEmpty ? nil : selectedText
    }

    private var selectedText: String {
        BigBang.join(words.filter { selected.contains($0.index) }, in: source)
    }

    private func translateSelection() {
        let text = selectedText
        guard !text.isEmpty else { return }
        loading = true
        error = nil
        Task {
            do {
                let result = try await TextTranslator.translateAuto(text)
                translation = result
                ipa = TextTranslator.isEnglishWord(text)
                    ? await phonetics?.phonetics(for: text) : nil
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    /// The reset task cancels, so a rapid second copy never clears the checkmark early.
    private func copyTranslation() {
        guard let translation else { return }
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
}

/// One pickable word: raised on hover, glowing blue when selected.
private struct BigBangPill: View {
    let word: BigBangWord
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Text(word.text)
            .font(.system(size: 15, weight: isSelected ? .semibold : .regular, design: .rounded))
            .foregroundStyle(isSelected ? Color.white : Color(white: hovered ? 0.92 : 0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(fillGradient)
                        : AnyShapeStyle(Color.white.opacity(hovered ? 0.14 : 0.07))))
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? Color.cyan.opacity(0.6) : Color.white.opacity(0.10),
                    lineWidth: 1)
            }
            .shadow(color: isSelected ? Color.blue.opacity(0.35) : .clear, radius: 6, y: 2)
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.7)],
            startPoint: .top, endPoint: .bottom)
    }
}

/// A wrap-around row: pills flow left to right and break to the next line at the edge.
struct WordFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Each pill reports its frame in the shared coordinate space; the drag hit-tests them.
struct PillFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
