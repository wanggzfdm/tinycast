import Foundation

@main
struct FileCreatorTests {
    static func main() {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "tinycast-file-creator-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let file = try! FileCreator.create(named: "notes.md", kind: .file, in: folder)
        guard FileManager.default.fileExists(atPath: file.path) else { fatalError("FAIL: creates file") }
        let directory = try! FileCreator.create(named: "Projects", kind: .folder, in: folder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { fatalError("FAIL: creates folder") }
        do {
            _ = try FileCreator.create(named: "notes.md", kind: .file, in: folder)
            fatalError("FAIL: refuses overwrite")
        } catch FileCreator.Error.alreadyExists {}
        catch { fatalError("FAIL: reports duplicate") }
        print("3 passed, 0 failed")
    }
}
