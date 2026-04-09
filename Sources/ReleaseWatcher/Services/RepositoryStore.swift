import Foundation
import UserNotifications

@Observable
@MainActor
final class RepositoryStore {
    private(set) var repositories: [WatchedRepository] = []
    private(set) var lastPersistenceError: String?
    private(set) var didLoadPersistedRepositories = false
    private(set) var lastNotificationError: String?
    private(set) var availableAppUpdate: AppUpdateInfo?

    private let releaseService = GitHubReleaseService()
    private let persistence: RepositoryPersistence
    private let notificationsEnabled: Bool

    init(
        persistence: RepositoryPersistence = RepositoryPersistence(),
        notificationsEnabled: Bool = AppRuntimeCapabilities.supportsUserNotifications
    ) {
        self.persistence = persistence
        self.notificationsEnabled = notificationsEnabled
        load()
        ensureSystemRepositories()
    }

    var storageLocationDescription: String {
        persistence.storageURL.path(percentEncoded: false)
    }

    var hasRepositories: Bool {
        !visibleRepositories.isEmpty
    }

    var visibleRepositories: [WatchedRepository] {
        repositories.filter { !$0.isSystemDefined }
    }

    var sortedRepositories: [WatchedRepository] {
        visibleRepositories.sorted(by: repositorySortComparator)
    }

    func addRepository(from input: String) throws {
        let parsed = try RepositoryInputParser.parse(input)
        let repository = WatchedRepository(owner: parsed.owner, name: parsed.name)

        guard !repositories.contains(where: { $0.owner.caseInsensitiveCompare(parsed.owner) == .orderedSame && $0.name.caseInsensitiveCompare(parsed.name) == .orderedSame }) else {
            throw RepositoryInputParserError.duplicateRepository(parsed.slug)
        }

        repositories.append(repository)
        try save()
    }

    func removeRepositories(withIDs ids: Set<UUID>) throws {
        repositories.removeAll { ids.contains($0.id) && !$0.isSystemDefined }
        try save()
    }

    func refreshRepositories(appState: AppState) async {
        guard didLoadPersistedRepositories else {
            appState.lastErrorMessage = lastPersistenceError ?? "Release Watcher could not load the saved repository list."
            return
        }

        guard !appState.isRefreshing else {
            return
        }

        appState.isRefreshing = true
        defer {
            appState.isRefreshing = false
            appState.lastRefreshAt = .now
        }

        var visibleRepositoryErrors: [String] = []
        availableAppUpdate = nil

        for index in repositories.indices {
            do {
                let release = try await releaseService.latestRelease(for: repositories[index])
                let previousTag = repositories[index].latestKnownTag
                repositories[index].latestKnownTag = release.tagName
                repositories[index].latestReleaseName = release.name
                repositories[index].latestReleaseURL = release.htmlURL
                repositories[index].latestReleasePublishedAt = release.publishedAt

                if repositories[index].isSystemDefined {
                    availableAppUpdate = AppUpdateInfo(
                        latestVersion: release.tagName,
                        releaseName: release.name,
                        releaseURL: release.htmlURL,
                        publishedAt: release.publishedAt,
                        isNewerThanInstalled: AppMetadata.isVersionNewer(release.tagName)
                    )
                }

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
            } catch {
                if repositories[index].isSystemDefined {
                    availableAppUpdate = nil
                } else {
                    visibleRepositoryErrors.append("\(repositories[index].displayName): \(error.localizedDescription)")
                }
            }
        }

        do {
            try save()
        } catch {
            appState.lastErrorMessage = error.localizedDescription
            return
        }

        appState.lastErrorMessage = visibleRepositoryErrors.isEmpty ? nil : visibleRepositoryErrors.joined(separator: "\n")
    }

    func requestNotificationPermission() async {
        guard notificationsEnabled else {
            return
        }

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            lastNotificationError = nil
        } catch {
            lastNotificationError = error.localizedDescription
        }
    }

    private func load() {
        do {
            repositories = try persistence.loadRepositories()
            didLoadPersistedRepositories = true
            lastPersistenceError = nil
        } catch {
            didLoadPersistedRepositories = false
            lastPersistenceError = "Could not load saved repositories from \(persistence.storageURL.path(percentEncoded: false)): \(error.localizedDescription)"
        }
    }

    private func save() throws {
        do {
            try persistence.saveRepositories(repositories)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = "Could not save repositories to \(persistence.storageURL.path(percentEncoded: false)): \(error.localizedDescription)"
            throw error
        }
    }

    private func sendNotification(for repository: WatchedRepository, release: GitHubReleaseService.Release) async throws {
        guard notificationsEnabled else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = repository.isSystemDefined ? "Release Watcher" : repository.displayName
        content.body = repository.isSystemDefined ? "A new version is available: \(release.tagName)" : "New release: \(release.tagName)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "release-\(repository.id.uuidString)-\(release.tagName)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            lastNotificationError = error.localizedDescription
            throw error
        }
    }

    private func ensureSystemRepositories() {
        let appRepository = AppRepository.releaseWatcherRepository

        guard !repositories.contains(where: { $0.owner == appRepository.owner && $0.name == appRepository.name }) else {
            return
        }

        repositories.append(appRepository)
        try? save()
    }

    private var repositorySortComparator: (WatchedRepository, WatchedRepository) -> Bool {
        { lhs, rhs in
            switch (lhs.latestReleasePublishedAt, rhs.latestReleasePublishedAt) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate > rightDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.addedAt != rhs.addedAt {
                    return lhs.addedAt > rhs.addedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }
}

struct AppUpdateInfo {
    let latestVersion: String
    let releaseName: String?
    let releaseURL: URL
    let publishedAt: Date?
    let isNewerThanInstalled: Bool
}

enum AppRepository {
    static let releaseWatcherRepository = WatchedRepository(
        owner: "alvarosanchez",
        name: "release-watcher",
        isSystemDefined: true
    )
}

struct AppMetadata {
    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    static func isVersionNewer(_ latestTag: String) -> Bool {
        compareVersion(normalize(latestTag), normalize(versionString)) == .orderedDescending
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0

            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }

        return .orderedSame
    }
}

struct AppRuntimeCapabilities {
    static var supportsUserNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static let storageDirectoryName = "com.alvarosanchez.ReleaseWatcher"
}

struct RepositoryPersistence {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    let storageURL: URL

    init(fileManager: FileManager = .default) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent(AppRuntimeCapabilities.storageDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storageURL = directory.appendingPathComponent("repositories.json")
    }

    func loadRepositories() throws -> [WatchedRepository] {
        try migrateIfNeeded()

        guard FileManager.default.fileExists(atPath: storageURL.path(percentEncoded: false)) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        return try decoder.decode([WatchedRepository].self, from: data)
    }

    func saveRepositories(_ repositories: [WatchedRepository]) throws {
        let data = try encoder.encode(repositories)
        try data.write(to: storageURL, options: .atomic)
    }

    private func migrateIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: storageURL.path(percentEncoded: false)) else {
            return
        }

        for candidate in legacyStorageURLs {
            guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else {
                continue
            }

            let data = try Data(contentsOf: candidate)
            try data.write(to: storageURL, options: .atomic)
            return
        }
    }

    private var legacyStorageURLs: [URL] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory

        return [
            appSupport.appendingPathComponent("ReleaseWatcher", isDirectory: true).appendingPathComponent("repositories.json"),
            appSupport.appendingPathComponent("com.alvarosanchez.release-watcher", isDirectory: true).appendingPathComponent("repositories.json"),
        ]
        .filter { $0 != storageURL }
    }
}

enum RepositoryInputParser {
    static func parse(_ input: String) throws -> ParsedRepository {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmed.isEmpty else {
            throw RepositoryInputParserError.invalidFormat
        }

        if let url = URL(string: trimmed), let host = url.host(), host.contains("github.com") {
            let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard components.count >= 2 else {
                throw RepositoryInputParserError.invalidFormat
            }

            return ParsedRepository(owner: components[0], name: sanitizedRepositoryName(components[1]))
        }

        let components = trimmed.split(separator: "/").map(String.init)
        guard components.count == 2, !components[0].isEmpty, !components[1].isEmpty else {
            throw RepositoryInputParserError.invalidFormat
        }

        return ParsedRepository(owner: components[0], name: sanitizedRepositoryName(components[1]))
    }

    private static func sanitizedRepositoryName(_ raw: String) -> String {
        raw.replacingOccurrences(of: ".git", with: "")
    }
}

struct ParsedRepository: Equatable {
    let owner: String
    let name: String

    var slug: String {
        "\(owner)/\(name)"
    }
}

enum RepositoryInputParserError: LocalizedError {
    case invalidFormat
    case duplicateRepository(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Enter a GitHub repository as owner/repo or a full github.com URL."
        case let .duplicateRepository(slug):
            return "\(slug) is already being watched."
        }
    }
}
