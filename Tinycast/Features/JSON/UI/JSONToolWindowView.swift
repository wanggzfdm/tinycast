import AppKit

import SwiftUI

/// The JSON tool, a 1:1 port of ZTools' json-editor plugin: a Monaco-style code editor with
/// folding, a bottom bar carrying `this` + a JS filter input and eight tool buttons, a toast
/// for copy confirmations, and system-following dark/light theming.
struct JSONToolWindowView: View {
    let coordinator: JSONToolCoordinator
    let initialText: String

    static let initialSize = CGSize(width: 720, height: 520)

    @State private var text = ""
    @State private var error: String?
    @State private var filter = ""
    @State private var filterResult: String?
    @State private var foldingCommand: JSONFoldingCommand?
    @State private var toast: ToastState?
    @State private var hasContent = false

    @Environment(\.colorScheme) private var colorScheme

    private var isValidJSON: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && JSONTool.isValid(text) }
    private var hasFilter: Bool { !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            Theme.Colors.cardFill
            VStack(spacing: 0) {
                contentArea
                if let error {
                    errorBar(error)
                }
                footer
            }
        }
        .overlay(alignment: .bottom) { if let toast { toastView(toast) } else { EmptyView() } }
        .onAppear { seedText() }
        .onChange(of: initialText) { _, _ in seedText() }
        .onChange(of: text) { _, newValue in
            hasContent = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasFilter { applyFilter() }
        }
    }

    // MARK: Content

    private var contentArea: some View {
        HStack(spacing: 0) {
            JSONSyntaxEditor(text: $text, foldingCommand: foldingCommand, colorScheme: colorScheme)
                .frame(maxWidth: hasFilter ? .infinity : .infinity, maxHeight: .infinity)
                .onChange(of: foldingCommand) { _, _ in
                    Task { @MainActor in foldingCommand = nil }
                }
            if hasFilter {
                Divider()
                JSONOutputEditor(text: filterResult ?? "", colorScheme: colorScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if !hasContent {
                Text("URL Params、XML、YAML 粘贴自动转为 JSON")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 60)
                    .padding(.top, 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private func errorBar(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(Theme.Colors.destructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 6)
            .background(colorScheme == .dark ? Color(red: 0.2, green: 0.05, blue: 0.05) : Color(red: 1, green: 0.95, blue: 0.95))
    }

    // MARK: Footer (38px, ZTools layout: this | filter input | 8 buttons)

    private var footer: some View {
        HStack(spacing: 0) {
            Text("this")
                .font(.system(size: 16))
                .foregroundStyle(colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4))
                .frame(width: 40, height: 38)
                .userSelectDisabled()

            HStack(spacing: 0) {
                TextField("JS 过滤；示例 \u{22}.key.subkey\u{22}、\u{22}[0][1]\u{22}、\u{22}.map(x=>x.val)\u{22}", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? Color(white: 0.95) : Color(white: 0.2))
                    .onChange(of: filter) { _, _ in
                        if hasFilter { applyFilter() } else { filterResult = nil }
                    }
            }
            .padding(.trailing, 8)

            toolbarButtons
        }
        .frame(height: 38)
        .padding(.trailing, 4)
        .background(colorScheme == .dark ? Color(red: 0.19, green: 0.19, blue: 0.2) : Theme.Colors.cardFill)
        .overlay(alignment: .top) {
            Rectangle().fill(colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.9)).frame(height: 1)
        }
    }

    private var toolbarButtons: some View {
        HStack(spacing: 2) {
            toolButton("text.alignleft", "格式化", "⌥F", isValidJSON) { format() }
            toolButton("chevron.up.chevron.down", "折叠", "⌥>", true) { foldingCommand = .collapseAll }
            toolButton("chevron.down.chevron.up", "展开", "⌥⇧>", true) { foldingCommand = .expandAll }
            toolButton("slash.circle", "去注释", nil, !text.isEmpty) { stripComments() }
            divider
            toolButton("arrow.up.and.down.text.horizontal", "压缩", "⌥C", isValidJSON) { copyCompressed() }
            toolButton("quote.bubble", "转义", "⌥\\", isValidJSON) { copyEscaped() }
            toolButton("chevron.left.forwardslash.chevron.right", "转XML", nil, isValidJSON) { convertXML() }
            toolButton("type", "转TS", nil, isValidJSON) { convertTS() }
        }
    }

    private func toolButton(_ icon: String, _ label: String, _ shortcut: String?, _ enabled: Bool, action: @escaping () -> Void) -> some View {
        let helpText = shortcut != nil ? "\(label)「\(shortcut!)」" : label
        return Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundStyle(enabled ? (colorScheme == .dark ? Color.white : Color.black) : Color.secondary)
            .frame(width: 40, height: 32)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .disabled(!enabled)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    // MARK: Seeding

    private func seedText() {
        guard text.isEmpty, !initialText.isEmpty else { return }
        if JSONTool.isValid(initialText), let formatted = try? JSONTool.format(initialText) {
            text = formatted
        } else {
            text = initialText
        }
        hasContent = true
    }

    // MARK: Actions

    private func format() {
        do {
            text = try JSONTool.format(text)
            error = nil
        } catch {
            self.error = JSONToolErrorPresenter.message(for: error)
        }
    }

    private func stripComments() {
        let stripped = JSONTool.stripComments(text)
        if stripped != text {
            if JSONTool.isValid(stripped), let formatted = try? JSONTool.format(stripped) {
                text = formatted
            } else {
                text = stripped
            }
            error = nil
        }
    }

    private func copyCompressed() {
        do {
            let value = try JSONTool.compact(text)
            coordinator.copy(value)
            showToast("已复制压缩 JSON")
            error = nil
        } catch {
            self.error = JSONToolErrorPresenter.message(for: error)
        }
    }

    private func copyEscaped() {
        do {
            let value = try JSONTool.escapedCompact(text)
            coordinator.copy(value)
            showToast("已复制压缩转义 JSON")
            error = nil
        } catch {
            self.error = JSONToolErrorPresenter.message(for: error)
        }
    }

    private func convertXML() {
        guard let parsed = try? JSONTool.parse(text) else {
            error = "错误的 JSON 格式"
            return
        }
        let xml = JSONTool.toJSONXML(parsed)
        coordinator.copy(xml)
        showToast("已复制转换 XML")
        error = nil
    }

    private func convertTS() {
        guard let parsed = try? JSONTool.parse(text) else {
            error = "错误的 JSON 格式"
            return
        }
        let ts = JSONTool.toTypeScript(parsed)
        coordinator.copy(ts)
        showToast("已复制转换 TypeScript")
        error = nil
    }

    private func applyFilter() {
        let expr = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty else { filterResult = nil; return }
        do {
            let result = try JSONTool.filter(text, expression: expr)
            if let str = result as? String {
                filterResult = str
            } else if let compacted = try? JSONTool.compact(result) {
                filterResult = (try? JSONTool.format(compacted)) ?? compacted
            } else {
                filterResult = String(describing: result)
            }
            error = nil
        } catch {
            filterResult = nil
            self.error = JSONToolErrorPresenter.message(for: error)
        }
    }

    // MARK: Toast

    private struct ToastState: Equatable {
        let message: String
        let id = UUID()
    }

    private func showToast(_ message: String) {
        let state = ToastState(message: message)
        withAnimation { toast = state }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast?.id == state.id { toast = nil } }
        }
    }

    private func toastView(_ state: ToastState) -> some View {
        Text(state.message)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .offset(y: -50)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Output editor (read-only, for JS filter results)

struct JSONOutputEditor: NSViewRepresentable {
    let text: String
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let editor = NSTextView()
        editor.isEditable = false
        editor.isSelectable = true
        editor.isRichText = true
        editor.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        editor.backgroundColor = colorScheme == .dark ? NSColor(red: 0.19, green: 0.19, blue: 0.2, alpha: 1) : NSColor(red: 0.965, green: 0.97, blue: 0.97, alpha: 1)
        editor.drawsBackground = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = context.coordinator.editor, editor.string != text else { return }
        let plain = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])
        editor.textStorage?.setAttributedString(plain)
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var editor: NSTextView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
}

// MARK: - Input editor with line numbers, folding, syntax tinting

/// A plain editor with a line-number gutter, per-kind JSON tinting and code folding.
struct JSONSyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    var foldingCommand: JSONFoldingCommand?
    var colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true

        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.isRichText = true
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = editor
        context.coordinator.editor = editor

        let ruler = JSONLineNumberRuler(scrollView: scroll, orientation: .verticalRuler)
        ruler.ruleThickness = 44
        ruler.coordinator = context.coordinator
        scroll.verticalRulerView = ruler
        context.coordinator.ruler = ruler

        context.coordinator.setText(text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setText(text)
        if let foldingCommand {
            switch foldingCommand {
            case .collapseAll: context.coordinator.collapseAll()
            case .expandAll: context.coordinator.expandAll()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONSyntaxEditor
        weak var editor: NSTextView?
        weak var ruler: JSONLineNumberRuler?
        private var updating = false
        private var tintWorkItem: DispatchWorkItem?
        private(set) var foldedStarts: Set<Int> = []
        private var originals: [Int: String] = [:]

        init(_ parent: JSONSyntaxEditor) { self.parent = parent }

        var folds: [JSONFold] {
            guard let editor else { return [] }
            return JSONTool.folds(editor.string)
        }

        func toggleFold(at line: Int) {
            guard let editor, let fold = folds.first(where: { $0.line == line }) else { return }
            if foldedStarts.contains(fold.start) {
                expandFold(fold, in: editor)
            } else {
                collapseFold(fold, in: editor)
            }
            applyTint()
            ruler?.needsDisplay = true
        }

        func collapseAll() {
            guard let editor else { return }
            let sorted = folds.sorted { $0.depth > $1.depth }
            for fold in sorted where !foldedStarts.contains(fold.start) {
                collapseFold(fold, in: editor)
            }
            applyTint()
            ruler?.needsDisplay = true
        }

        func expandAll() {
            guard let editor else { return }
            let sorted = folds.sorted { $0.depth < $1.depth }
            for fold in sorted where foldedStarts.contains(fold.start) {
                expandFold(fold, in: editor)
            }
            applyTint()
            ruler?.needsDisplay = true
        }

        private func collapseFold(_ fold: JSONFold, in editor: NSTextView) {
            let interior = NSRange(location: fold.start + 1, length: fold.end - fold.start - 1)
            guard interior.length > 0 else { return }
            let original = (editor.string as NSString).substring(with: interior)
            originals[fold.start] = original
            replace(in: editor, range: interior, with: "…")
            foldedStarts.insert(fold.start)
        }

        private func expandFold(_ fold: JSONFold, in editor: NSTextView) {
            guard let original = originals.removeValue(forKey: fold.start) else { return }
            let interior = NSRange(location: fold.start + 1, length: fold.end - fold.start - 1)
            replace(in: editor, range: interior, with: original)
            foldedStarts.remove(fold.start)
        }

        private func replace(in editor: NSTextView, range: NSRange, with string: String) {
            updating = true
            defer { updating = false }
            let storage = editor.textStorage!
            let replacement = NSAttributedString(string: string, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ])
            storage.replaceCharacters(in: range, with: replacement)
            if let layout = editor.layoutManager {
                layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let editor else { return }
            foldedStarts.removeAll()
            originals.removeAll()
            parent.text = editor.string
            ruler?.needsDisplay = true
            scheduleTint()
        }

        func setText(_ value: String) {
            guard let editor, !updating, editor.string != value else { return }
            updating = true
            defer { updating = false }
            foldedStarts.removeAll()
            originals.removeAll()
            let selectedRange = editor.selectedRange()
            editor.undoManager?.disableUndoRegistration()
            let plain = NSAttributedString(string: value, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ])
            editor.textStorage?.setAttributedString(plain)
            editor.undoManager?.enableUndoRegistration()
            let location = min(selectedRange.location, value.utf16.count)
            let length = min(selectedRange.length, value.utf16.count - location)
            editor.setSelectedRange(NSRange(location: location, length: length))
            applyTint(to: value)
            ruler?.needsDisplay = true
        }

        private func scheduleTint() {
            tintWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.applyTint() }
            tintWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func applyTint() {
            guard let editor else { return }
            applyTint(to: editor.string)
        }

        private func applyTint(to value: String) {
            guard let storage = editor?.textStorage else { return }
            let colors: [JSONSyntaxKind: NSColor] = [
                .key: .systemBlue, .string: .systemGreen, .number: .systemOrange,
                .bool: .systemPurple, .null: .systemPurple, .punctuation: .secondaryLabelColor,
            ]
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            for token in JSONTool.syntaxTokens(value) {
                storage.addAttribute(.foregroundColor, value: colors[token.kind] ?? NSColor.labelColor, range: token.nsRange)
            }
            storage.endEditing()
        }
    }
}

// MARK: - Ruler

final class JSONLineNumberRuler: NSRulerView {
    weak var coordinator: JSONSyntaxEditor.Coordinator?
    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let coordinator, let textView = coordinator.editor,
              let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let visible = textView.enclosingScrollView?.contentView.bounds ?? rect
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
        let lines = JSONTool.lineNumbers(for: textView.string)
        let foldsByLine = Dictionary(grouping: coordinator.folds, by: { $0.line })
        layout.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let characterRange = layout.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let location = min(characterRange.location, max(0, lines.count - 1))
            let line = lines[location]
            let documentY = usedRect.minY + textView.textContainerInset.height
            let y = documentY - (textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0)
            let baseline = y + (usedRect.height - self.font.ascender + self.font.descender) / 2

            if let fold = foldsByLine[line]?.first {
                let isCollapsed = coordinator.foldedStarts.contains(fold.start)
                let symbol = NSAttributedString(string: isCollapsed ? "▶" : "▼", attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
                symbol.draw(at: NSPoint(x: 8, y: baseline - 2))
            }

            let label = NSAttributedString(string: String(line), attributes: [
                .font: self.font, .foregroundColor: NSColor.secondaryLabelColor,
            ])
            label.draw(at: NSPoint(x: self.bounds.width - label.size().width - 8, y: baseline))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let coordinator, let textView = coordinator.editor,
              let layout = textView.layoutManager, let container = textView.textContainer else {
            super.mouseDown(with: event)
            return
        }
        let visible = textView.enclosingScrollView?.contentView.bounds ?? bounds
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
        let foldableLines = Set(coordinator.folds.map { $0.line })
        var hitLine: Int?
        layout.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let characterRange = layout.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let lines = JSONTool.lineNumbers(for: textView.string)
            let location = min(characterRange.location, max(0, lines.count - 1))
            let line = lines[location]
            let documentY = usedRect.minY + textView.textContainerInset.height
            let y = documentY - (textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0)
            if foldableLines.contains(line), point.x < 24, point.y >= y, point.y <= y + usedRect.height {
                hitLine = line
            }
        }
        if let hitLine {
            coordinator.toggleFold(at: hitLine)
            return
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Helpers

enum JSONFoldingCommand: Equatable {
    case collapseAll
    case expandAll
}

private enum JSONToolErrorPresenter {
    static func message(for error: Error) -> String {
        if let jsonError = error as? JSONToolError {
            return "第 \(jsonError.line) 行，第 \(jsonError.column) 列：\(jsonError.message)"
        }
        return (error as NSError).localizedDescription
    }
}

private extension View {
    func userSelectDisabled() -> some View {
        self
    }
}
