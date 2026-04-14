import Foundation

struct WatchedRepository: Identifiable, Codable, Hashable {
    let id: UUID
    var owner: String
    var name: String
    var addedAt: Date
    var isWatchingPrereleases: Bool
    var isSystemDefined: Bool
    var latestKnownTag: String?
    var latestReleaseName: String?
    var latestReleaseURL: URL?
    var latestReleasePublishedAt: Date?
    var unreadBaselineAt: Date?
    var snapshots: [ReleaseSnapshot]

    init(
        id: UUID = UUID(),
        owner: String,
        name: String,
        addedAt: Date = .now,
        isWatchingPrereleases: Bool = false,
        isSystemDefined: Bool = false,
        latestKnownTag: String? = nil,
        latestReleaseName: String? = nil,
        latestReleaseURL: URL? = nil,
        latestReleasePublishedAt: Date? = nil,
        unreadBaselineAt: Date? = nil,
        snapshots: [ReleaseSnapshot] = []
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.addedAt = addedAt
        self.isWatchingPrereleases = isWatchingPrereleases
        self.isSystemDefined = isSystemDefined
        self.latestKnownTag = latestKnownTag
        self.latestReleaseName = latestReleaseName
        self.latestReleaseURL = latestReleaseURL
        self.latestReleasePublishedAt = latestReleasePublishedAt
        self.unreadBaselineAt = unreadBaselineAt
        self.snapshots = snapshots
    }

    var displayName: String {
        "\(owner)/\(name)"
    }
}
