import SwiftUI
import WebKit

/// The web tool mounted inside the palette: the page takes the keyboard, the palette's
/// header carries the tool pill, and Escape pops back to the launcher.
@MainActor
struct WebToolScreen {
    let coordinator: WebToolCoordinator
    let vm: PaletteState
}

extension WebToolScreen: PaletteScreen {

    struct Row: Identifiable {
        let id = UUID()
    }

    var rows: [Row] { [] }
    var primaryActionTitle: String { "" }
    var hidesSearchField: Bool { true }
    var toolTitle: String? { String(localized: "Web Calendar") }
    var actsWithoutRows: Bool { false }
    var landingSelection: Int { 0 }

    func hasPrimaryAction(at selection: Int) -> Bool { false }
    func isPrimaryActionEnabled(at selection: Int) -> Bool { false }
    func hasActions(at selection: Int) -> Bool { false }
    func ownsVerticalKeys(at selection: Int) -> Bool { true }
    func tabTarget(from selection: Int, backwards: Bool) -> Int? { nil }
    func tab(at selection: Int, backwards: Bool) -> Bool { false }
    func actions(at selection: Int) -> PopoverMenuContent? { nil }
    func activate(at selection: Int) {}
    func secondary(at selection: Int) -> Bool { false }
    func tertiary(at selection: Int) -> Bool { false }
    func pasteKeepingWindowOpen(at selection: Int) -> Bool { false }
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool { false }
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? { nil }

    @ViewBuilder
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            WebToolWindowView(webView: coordinator.panelWebView())
                // The page consumes Escape once it owns the keyboard; pop before it can.
                .modifier(ToolEscapePopper(onPop: coordinator.closePanel))
        )
    }
}

/// A local monitor, not a key handler: a tool screen's editor or web view eats key events
/// below SwiftUI, so Escape has to be intercepted before the screen's first responder.
struct ToolEscapePopper: ViewModifier {
    let onPop: () -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                    guard event.keyCode == 53 else { return event }
                    onPop()
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
