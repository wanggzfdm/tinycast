enum ToolWindowLevel: Equatable {
    case normal
    case floating

    init(alwaysOnTop: Bool) {
        self = alwaysOnTop ? .floating : .normal
    }
}
