import Foundation

enum FileCreationName {
    enum Error: Swift.Error, Equatable {
        case empty
        case reserved
        case containsPathSeparator
    }

    static func validate(_ input: String) -> Result<String, Error> {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.empty) }
        guard name != ".", name != ".." else { return .failure(.reserved) }
        guard !name.contains("/") else { return .failure(.containsPathSeparator) }
        return .success(name)
    }
}
