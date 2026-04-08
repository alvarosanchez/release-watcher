import Foundation

struct WatchedRepository: Identifiable, Codable, Hashable {
    let id: UUID
    var owner: String
    var name: String
    var addedAt: Date
    var isWatchingPrereleases: Bool
    var latestKnownTag: String?
    var snapshots: [ReleaseSnapshot]

    init(
        id: UUID = UUID(),
        owner: String,
        name: String,
        addedAt: Date = .now,
        isWatchingPrereleases: Bool = false,
        latestKnownTag: String? = nil,
        snapshots: [ReleaseSnapshot] = []
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.addedAt = addedAt
        self.isWatchingPrereleases = isWatchingPrereleases
        self.latestKnownTag = latestKnownTag
        self.snapshots = snapshots
    }

    var displayName: String {
        "\(owner)/\(name)"
    }
}
