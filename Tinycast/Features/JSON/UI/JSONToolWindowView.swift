import AppKit
import SwiftUI

/// The JSON tool: a syntax-highlighted editor or a collapsible tree, a filter bar, and a full
/// format/minify/copy toolbar. A syntax error shows its line and column instead of a bare no.
struct JSONToolWindowView: View {
    let coordinator: JSONToolCoordinator
    let initialText: String

    static let initialSize = CGSize(width: 640, height: 560)

    @State private var text = ""
    @State private var error: String?
    @State private var mode: JSONEditorMode = .code
    @State private var root: JSONTreeNode?
    @State private var expanded: Set<String> = []
    @State private var filter = ""
    @State private var foldingCommand: JSONFoldingCommand?

    private var isValidJSON: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && JSONTool.isValid(text) }

    var body: some View {
        VStack(spacing: 0) {
            header
            editorOrTree
            filterBar
            if let error {
                errorBar(error)
            }
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.cardFill)
        .onAppear {
            if text.isEmpty {
                if JSONTool.isValid(initialText), let formatted = try? JSONTool.format(initialText) {
                    text = formatted
                } else {
                    text = initialText
                }
            }
            refreshTree()
        }
        .onChange(of: text) { _, _ in refreshTree() }
        .onChange(of: mode) { _, _ in refreshTree() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Label("JSON Tool", systemImage: "curlybraces")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Picker("Mode", selection: $mode) {
                ForEach(JSONEditorMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            if mode == .tree {
                Button("Collapse All", systemImage: "chevron.up") { expanded.removeAll() }
                    .help("Collapse all tree nodes")
                Button("Expand All", systemImage: "chevron.down") {
                    expanded.formUnion(root?.paths ?? [])
                }
                .help("Expand all tree nodes")
            } else {
                Button("Collapse All", systemImage: "chevron.up") { foldingCommand = .collapseAll }
                    .help("Collapse every container")
                Button("Expand All", systemImage: "chevron.down") { foldingCommand = .expandAll }
                    .help("Expand every container")
            }
            Button("Clear", systemImage: "trash") {
                text = ""
                error = nil
            }
            .disabled(text.isEmpty)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: Editor / tree

    @ViewBuilder
    private var editorOrTree: some View {
        switch mode {
        case .code:
            JSONSyntaxEditor(text: $text, foldingCommand: foldingCommand)
                .frame(maxHeight: .infinity)
                .onChange(of: foldingCommand) { _, _ in
                    Task { @MainActor in foldingCommand = nil }
                }
        case .tree:
            if let root {
                ScrollView([.vertical, .horizontal]) {
                    JSONTreeRow(node: root, depth: 0, expanded: $expanded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.lg)
                }
            } else {
                Color.clear
            }
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("Filter")
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(".items.map(x => x.val)[0]", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .padding(6)
                .background(Theme.Colors.controlSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Button("Apply", systemImage: "arrow.right.circle") { applyFilter() }
                .disabled(filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button("Format", systemImage: "text.alignleft") { format() }
                .disabled(!isValidJSON)
            Button("Minify", systemImage: "arrow.up.and.down.text.horizontal") { minify() }
                .disabled(!isValidJSON)
            Divider().frame(height: 18)
            Button("Copy", systemImage: "doc.on.doc") { coordinator.copy(text) }
                .disabled(text.isEmpty)
            Button("Copy Minified", systemImage: "doc.on.doc.fill") { copyMinified() }
                .disabled(!isValidJSON)
            Button("Copy Escaped", systemImage: "quote.bubble") { copyEscaped() }
                .disabled(!isValidJSON)
            Spacer()
            Text("\(JSONTool.logicalLineCount(text)) lines")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
    }

    private func errorBar(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(Theme.Colors.destructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: Actions

    private func run(_ operation: () throws -> String) {
        do {
            text = try operation()
            error = nil
        } catch {
            self.error = JSONToolErrorPresenter.message(for: error)
        }
    }

    private func format() { run { try JSONTool.format(text) } }

    private func minify() { run { try JSONTool.compact(text) } }

    private func copyMinified() {
        run {
            let minified = try JSONTool.compact(text)
            coordinator.copy(minified)
            return text
        }
    }

    private func copyEscaped() {
        run {
            let escaped = try JSONTool.escapedCompact(text)
            coordinator.copy(escaped)
            return text
        }
    }

    private func applyFilter() {
        let expression = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            error = String(localized: "Enter a filter expression.")
            return
        }
        do {
            let value = try JSONTool.filter(text, expression: expression)
            text = try JSONTool.compact(value)
            error = nil
        } catch {
            self.error = JSONToolErrorPresenter.message(for: error)
        }
    }

    private func refreshTree() {
        guard mode == .tree else { root = nil; return }
        do {
            let newRoot = try JSONTool.tree(text)
            root = newRoot
            expanded.formUnion(newRoot.defaultExpandedPaths)
            error = nil
        } catch {
            root = nil
            self.error = JSONToolErrorPresenter.message(for: error)
        }
    }
}

enum JSONEditorMode: String, CaseIterable, Identifiable {
    case code = "Code"
    case tree = "Tree"
    var id: String { rawValue }
}

private enum JSONToolErrorPresenter {
    static func message(for error: Error) -> String {
        if let jsonError = error as? JSONToolError {
            return "Line \(jsonError.line), column \(jsonError.column): \(jsonError.message)"
        }
        return (error as NSError).localizedDescription
    }
}

/// A command the SwiftUI side can send to the editor's coordinator.
enum JSONFoldingCommand: Equatable {
    case collapseAll
    case expandAll
}

/// A plain editor with a line-number gutter, per-kind JSON tinting and code folding. A debounce
/// keeps typing cheap; the tint rebuilds only the colour attributes, never the text.
struct JSONSyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    var foldingCommand: JSONFoldingCommand?

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
        /// Open-brace offsets collapsed in the *current* editor string, each showing `…` for its interior.
        private(set) var foldedStarts: Set<Int> = []
        /// The original interior (excluding the braces) a collapsed pair hid, keyed by open offset.
        private var originals: [Int: String] = [:]

        init(_ parent: JSONSyntaxEditor) { self.parent = parent }

        /// A fold-toggle control sits beside every open brace; `fold.line` is where it draws.
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
            // Collapse innermost first so a parent's saved interior is the already-shortened text.
            let sorted = folds.sorted { $0.depth > $1.depth }
            for fold in sorted where !foldedStarts.contains(fold.start) {
                collapseFold(fold, in: editor)
            }
            applyTint()
            ruler?.needsDisplay = true
        }

        func expandAll() {
            guard let editor else { return }
            // Expand outermost first; its saved interior still holds the inner placeholder.
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

        /// A programmatic edit: swap text without touching undo, selection or the SwiftUI binding.
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
            // A real keystroke means the user is editing the document, so clear any fold state.
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

        // MARK: Tinting

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

/// The left gutter that numbers the editor's logical lines and offers a fold toggle per container.
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
            let location = min(characterRange.location, lines.count - 1)
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
            let location = min(characterRange.location, lines.count - 1)
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

/// One row of the tree view: a disclosure key plus its type-tinted value. Expansion is tracked by
/// node path so rebuilding from a fresh parse keeps the user's open/close state.
struct JSONTreeRow: View {
    let node: JSONTreeNode
    let depth: Int
    @Binding var expanded: Set<String>

    private var isExpanded: Bool { expanded.contains(node.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if isExpanded { expanded.remove(node.path) }
                else { expanded.insert(node.path) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: node.children.isEmpty ? "circle.fill"
                        : isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 10)
                    if let key = node.key {
                        Text(key).foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        Text("root").foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text(node.type).foregroundStyle(typeColor)
                    if node.children.isEmpty {
                        Text(displayValue(node.value)).foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(depth * 16))
            if isExpanded {
                ForEach(node.children) { child in
                    JSONTreeRow(node: child, depth: depth + 1, expanded: $expanded)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var typeColor: Color {
        switch node.type {
        case "string": return .green
        case "number": return .orange
        case "bool": return .blue
        case "null": return .purple
        default: return .teal
        }
    }

    private func displayValue(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let string = value as? String { return "\"\(string)\"" }
        return String(describing: value)
    }
}

private extension JSONTreeNode {
    /// Every nested path, for "expand all" and for keeping expansion after a re-parse.
    var paths: [String] { [path] + children.flatMap { $0.paths } }

    /// Leaves and the immediate children of arrays are shown open by default.
    var defaultExpandedPaths: [String] {
        [path] + children.flatMap { child in
            child.children.isEmpty ? [child.path] : child.defaultExpandedPaths
        }
    }
}