import Foundation

struct GitHubReleaseService {
    struct Release: Decodable, Equatable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let publishedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case draft
            case prerelease
            case publishedAt = "published_at"
        }
    }

    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func releases(for repository: WatchedRepository) async throws -> [Release] {
        let perPage = 100
        var page = 1
        var releases: [Release] = []

        while true {
            let endpoint = URL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases?per_page=\(perPage)&page=\(page)")!
            let data = try await performRequest(to: endpoint)
            let pageReleases = try decoder.decode([Release].self, from: data)

            releases.append(
                contentsOf: pageReleases.filter { release in
                    guard !release.draft else {
                        return false
                    }

                    return repository.isWatchingPrereleases || !release.prerelease
                }
            )

            if pageReleases.count < perPage {
                break
            }

            page += 1
        }

        let sortedReleases = releases
            .sorted(by: { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) })

        guard !sortedReleases.isEmpty else {
            throw GitHubReleaseServiceError.noPublishedReleases
        }

        return sortedReleases
    }

    private func performRequest(to endpoint: URL) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ReleaseWatcher/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            throw GitHubReleaseServiceError.invalidResponse(statusCode)
        }

        return data
    }
}

enum GitHubReleaseServiceError: LocalizedError {
    case invalidResponse(Int)
    case noPublishedReleases

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(statusCode):
            return "GitHub API returned status code \(statusCode)."
        case .noPublishedReleases:
            return "No published releases were found for this repository."
        }
    }
}
