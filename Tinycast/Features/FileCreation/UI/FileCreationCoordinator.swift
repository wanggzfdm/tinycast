import Foundation

@MainActor
final class FileCreationCoordinator {
    private let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    var finderWasFrontmost: Bool {
        FinderFolderAccess.isFinder(core.paletteCoordinator.targetApp)
    }

    func createFile() {
        create(kind: .file)
    }

    func createFolder() {
        create(kind: .folder)
    }

    private func create(kind: FileCreator.Kind) {
        let finderWasFrontmost = self.finderWasFrontmost
        Task { @MainActor in
            guard let folder = await FinderFolderAccess.currentFolder(
                finderWasFrontmost: finderWasFrontmost
            ) else { return }
            guard let name = await core.requestFileCreationName(kind: kind, folder: folder) else { return }
            switch FileCreationName.validate(name) {
            case .failure(let error):
                core.showMessage(message(for: error), tone: .danger)
            case .success(let validName):
                create(validName, kind: kind, in: folder)
            }
        }
    }

    private func create(_ name: String, kind: FileCreator.Kind, in folder: URL) {
        do {
            let item = try FileCreator.create(named: name, kind: kind, in: folder)
            AppLauncher.showInFinder(item)
            core.showMessage(kind == .file ? String(localized: "Created file") : String(localized: "Created folder"))
        } catch FileCreator.Error.alreadyExists {
            core.showMessage(String(localized: "An item with that name already exists."), tone: .danger)
        } catch {
            core.showMessage(String(localized: "Couldn't create the item."), tone: .danger)
        }
    }

    private func message(for error: FileCreationName.Error) -> String {
        switch error {
        case .empty: return String(localized: "Enter a name.")
        case .reserved: return String(localized: "That name isn't available.")
        case .containsPathSeparator: return String(localized: "Names can't contain a slash.")
        }
    }
}
