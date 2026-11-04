import Foundation

/// English-word IPA lookups from dictionaryapi.dev. The free API needs no key; the in-memory
/// cache includes misses, so an unlisted word costs one request instead of one per view.
@MainActor
final class PhoneticsStore {
    private nonisolated static let endpoint = "https://api.dictionaryapi.dev/api/v2/entries/en/"

    private var cache: [String: String] = [:]

    func phonetics(for word: String) async -> String? {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }
        let ipa = await Self.fetch(key)
        cache[key] = ipa ?? ""
        return ipa
    }

    /// Cacheless, never `URLSession.shared`, so no other copy of a response lands on disk.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private nonisolated static func fetch(_ word: String) async -> String? {
        guard
            let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: endpoint + encoded)
        else { return nil }
        let request = URLRequest(url: url, timeoutInterval: 10)
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return PhoneticsEntry.ipa(from: data)
    }
}
