import Foundation

struct GitHubReleaseService {
    struct Release: Decodable, Equatable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let prerelease: Bool
        let publishedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case prerelease
            case publishedAt = "published_at"
        }
    }

    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func latestRelease(for repository: WatchedRepository) async throws -> Release {
        let endpoint = URL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ReleaseWatcher/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            throw GitHubReleaseServiceError.invalidResponse(statusCode)
        }

        return try decoder.decode(Release.self, from: data)
    }
}

enum GitHubReleaseServiceError: LocalizedError {
    case invalidResponse(Int)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(statusCode):
            return "GitHub API returned status code \(statusCode)."
        }
    }
}
