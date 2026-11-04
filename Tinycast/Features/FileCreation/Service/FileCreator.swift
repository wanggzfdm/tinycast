import Foundation

enum FileCreator {
    enum Kind {
        case file
        case folder
    }

    enum Error: Swift.Error {
        case alreadyExists
        case creationFailed
    }

    static func create(named name: String, kind: Kind, in folder: URL, fileManager: FileManager = .default)
        throws -> URL
    {
        let destination = folder.appending(path: name, directoryHint: kind == .folder ? .isDirectory : .notDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { throw Error.alreadyExists }
        do {
            switch kind {
            case .file: try Data().write(to: destination, options: .withoutOverwriting)
            case .folder: try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            }
            return destination
        } catch {
            throw Error.creationFailed
        }
    }
}
