import Foundation

@main
struct FileCreationNameTests {
    static func expect(
        _ actual: Result<String, FileCreationName.Error>,
        _ expected: Result<String, FileCreationName.Error>, _ message: String
    ) {
        guard actual == expected else {
            print("FAIL: \(message) — got \(actual), want \(expected)")
            exit(1)
        }
    }

    static func main() {
        expect(FileCreationName.validate("notes.md"), .success("notes.md"), "keeps file extension")
        expect(FileCreationName.validate("  Projects  "), .success("Projects"), "trims folder name")
        expect(FileCreationName.validate("  \n"), .failure(.empty), "rejects blank names")
        expect(FileCreationName.validate("."), .failure(.reserved), "rejects current folder")
        expect(FileCreationName.validate(".."), .failure(.reserved), "rejects parent folder")
        expect(FileCreationName.validate("nested/name"), .failure(.containsPathSeparator), "rejects paths")
        print("6 passed, 0 failed")
    }
}
