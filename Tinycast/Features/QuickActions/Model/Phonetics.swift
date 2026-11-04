import Foundation

/// One dictionaryapi.dev entry: only the IPA matters here, the API's audio stays unused.
struct PhoneticsEntry: Codable, Sendable {
    struct Variant: Codable, Sendable {
        let text: String?
        let audio: String?
    }

    let word: String?
    let phonetic: String?
    let phonetics: [Variant]?

    /// The API's shape is loose: `phonetic` may be absent and `phonetics[i].text` may be empty.
    static func ipa(from data: Data) -> String? {
        guard let entries = try? JSONDecoder().decode([PhoneticsEntry].self, from: data) else {
            return nil
        }
        return ipa(from: entries)
    }

    static func ipa(from entries: [PhoneticsEntry]) -> String? {
        for entry in entries {
            if let text = entry.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            { return text }
            for variant in entry.phonetics ?? [] {
                if let text = variant.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty
                { return text }
            }
        }
        return nil
    }
}
