import SwiftUI

/// The JSON tool mounted inside the palette: the editor takes the keyboard, the palette's
/// header carries the back button, and Escape pops to the launcher the summon came from.
@MainActor
struct JSONToolScreen {
    let coordinator: JSONToolCoordinator
    let initialText: String
    let vm: PaletteState
}

extension JSONToolScreen: PaletteScreen {

    struct Row: Identifiable {
        let id = UUID()
    }

    var rows: [Row] { [] }
    var primaryActionTitle: String { "" }
    var hidesSearchField: Bool { true }
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

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        PaletteHeaderAccessory(
            width: 0, fieldNames: [], firstIncompleteField: nil,
            placement: .besideSearchField,
            view: AnyView(
                Text("JSON Tool")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)))
    }

    @ViewBuilder
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            JSONToolWindowView(coordinator: coordinator, initialText: vm.jsonToolText))
    }
}
