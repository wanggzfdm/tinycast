import SwiftUI

@MainActor
@Observable
final class FileCreationNameState {
    var name = ""
}

struct FileCreationNameField: View {
    @Bindable var state: FileCreationNameState

    var body: some View {
        TextField(String(localized: "Name"), text: $state.name)
            .dialogTextField()
            .onAppear { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
    }
}
