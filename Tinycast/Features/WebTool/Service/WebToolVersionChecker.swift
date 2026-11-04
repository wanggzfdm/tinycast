import Foundation

/// A cheap uncached revalidation of the document that names the hashed web assets.
enum WebToolVersionChecker {
    nonisolated static func version(at url: URL) async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await session.data(for: request),
            let response = response as? HTTPURLResponse
        else { return nil }
        return response.value(forHTTPHeaderField: "ETag")
            ?? response.value(forHTTPHeaderField: "Last-Modified")
    }
}
