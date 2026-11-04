enum ToolDetachShortcut {
    static func matches(
        command: Bool, shift: Bool, option: Bool, control: Bool,
        showsToolChrome: Bool, isControlListOpen: Bool, isCollapsed: Bool
    ) -> Bool {
        command && !shift && !option && !control && showsToolChrome
            && !isControlListOpen && !isCollapsed
    }
}
