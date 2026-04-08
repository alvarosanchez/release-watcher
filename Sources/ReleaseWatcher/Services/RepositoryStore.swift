import Foundation
import UserNotifications

@Observable
@MainActor
final class RepositoryStore {
    private(set) var repositories: [WatchedRepository] = []

    private let releaseService = GitHubReleaseService()
    private let persistence: RepositoryPersistence

    init(persistence: RepositoryPersistence = RepositoryPersistence()) {
        self.persistence = persistence
        load()
    }

    func addRepository(owner: String, name: String) throws {
        let repository = WatchedRepository(owner: owner, name: name)
        repositories.insert(repository, at: 0)
        try save()
    }

    func removeRepositories(withIDs ids: Set<UUID>) throws {
        repositories.removeAll { ids.contains($0.id) }
        try save()
    }

    func refreshRepositories(appState: AppState) async {
        appState.isRefreshing = true
        defer {
            appState.isRefreshing = false
            appState.lastRefreshAt = .now
        }

        do {
            for index in repositories.indices {
                let release = try await releaseService.latestRelease(for: repositories[index])
                let previousTag = repositories[index].latestKnownTag
                repositories[index].latestKnownTag = release.tagName

                if let snapshotIndex = repositories[index].snapshots.firstIndex(where: { $0.tagName == release.tagName }) {
                    repositories[index].snapshots[snapshotIndex].releaseName = release.name
                    repositories[index].snapshots[snapshotIndex].htmlURL = release.htmlURL
                    repositories[index].snapshots[snapshotIndex].publishedAt = release.publishedAt
                } else {
                    let snapshot = ReleaseSnapshot(
                        tagName: release.tagName,
                        releaseName: release.name,
                        publishedAt: release.publishedAt,
                        htmlURL: release.htmlURL
                    )
                    repositories[index].snapshots.insert(snapshot, at: 0)
                }

                if let previousTag, previousTag != release.tagName {
                    try await sendNotification(for: repositories[index], release: release)
                }
            }

            try save()
            appState.lastErrorMessage = nil
        } catch {
            appState.lastErrorMessage = error.localizedDescription
        }
    }

    func requestNotificationPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
        }
    }

    private func load() {
        do {
            repositories = try persistence.loadRepositories()
        } catch {
            repositories = []
        }
    }

    private func save() throws {
        try persistence.saveRepositories(repositories)
    }

    private func sendNotification(for repository: WatchedRepository, release: GitHubReleaseService.Release) async throws {
        let content = UNMutableNotificationContent()
        content.title = repository.displayName
        content.body = "New release: \(release.tagName)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "release-\(repository.id.uuidString)-\(release.tagName)",
            content: content,
            trigger: nil
        )

        try await UNUserNotificationCenter.current().add(request)
    }
}

struct RepositoryPersistence {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("ReleaseWatcher", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path()) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storageURL = directory.appendingPathComponent("repositories.json")
    }

    func loadRepositories() throws -> [WatchedRepository] {
        guard FileManager.default.fileExists(atPath: storageURL.path()) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        return try decoder.decode([WatchedRepository].self, from: data)
    }

    func saveRepositories(_ repositories: [WatchedRepository]) throws {
        let data = try encoder.encode(repositories)
        try data.write(to: storageURL, options: .atomic)
    }
}
