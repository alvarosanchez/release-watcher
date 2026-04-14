import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class RepositoryStore {
    private(set) var repositories: [WatchedRepository] = []
    private(set) var lastPersistenceError: String?
    private(set) var didLoadPersistedRepositories = false
    private(set) var lastNotificationError: String?
    private(set) var availableAppUpdate: AppUpdateInfo?
    private(set) var lastMenuBarOpenedAt: Date?

    private let releaseService = GitHubReleaseService()
    private let persistence: RepositoryPersistence
    private let notificationsEnabled: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onStateChange: (@MainActor () -> Void)?

    private static let lastMenuBarOpenedAtKey = "menuBarLastOpenedAt"

    init(
        persistence: RepositoryPersistence = RepositoryPersistence(),
        notificationsEnabled: Bool = AppRuntimeCapabilities.supportsUserNotifications,
        defaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.notificationsEnabled = notificationsEnabled
        self.defaults = defaults

        lastMenuBarOpenedAt = defaults.object(forKey: Self.lastMenuBarOpenedAtKey) as? Date

        load()
        ensureSystemRepositories()
        seedUnreadBaselinesFromKnownReleases()
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

    var unreadReleaseCount: Int {
        visibleRepositories.reduce(0) { $0 + unreadReleaseCount(for: $1) }
    }

    func addRepository(from input: String) throws {
        let parsed = try RepositoryInputParser.parse(input)
        let repository = WatchedRepository(owner: parsed.owner, name: parsed.name)

        guard !repositories.contains(where: { $0.owner.caseInsensitiveCompare(parsed.owner) == .orderedSame && $0.name.caseInsensitiveCompare(parsed.name) == .orderedSame }) else {
            throw RepositoryInputParserError.duplicateRepository(parsed.slug)
        }

        repositories.append(repository)
        try save()
        notifyStateChange()
    }

    func removeRepositories(withIDs ids: Set<UUID>) throws {
        repositories.removeAll { ids.contains($0.id) && !$0.isSystemDefined }
        try save()
        notifyStateChange()
    }

    func recordMenuBarInteraction(at date: Date = .now) {
        lastMenuBarOpenedAt = date
        defaults.set(date, forKey: Self.lastMenuBarOpenedAtKey)
        notifyStateChange()
    }

    func unreadReleaseCount(for repository: WatchedRepository) -> Int {
        let baseline = effectiveUnreadBaseline(for: repository)

        return repository.snapshots.reduce(into: 0) { total, snapshot in
            guard snapshotDate(for: snapshot) > baseline else {
                return
            }

            total += 1
        }
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
                if lastMenuBarOpenedAt == nil, repositories[index].unreadBaselineAt == nil {
                    repositories[index].unreadBaselineAt = knownReleaseDate(for: repositories[index])
                }

                let releases = try await releaseService.releases(for: repositories[index])
                guard let release = releases.first else {
                    throw GitHubReleaseServiceError.noPublishedReleases
                }

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

                mergeSnapshots(from: releases, into: &repositories[index])

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
        notifyStateChange()
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

    private func seedUnreadBaselinesFromKnownReleases() {
        guard lastMenuBarOpenedAt == nil else {
            return
        }

        for index in repositories.indices where repositories[index].unreadBaselineAt == nil {
            repositories[index].unreadBaselineAt = knownReleaseDate(for: repositories[index])
        }
    }

    private func mergeSnapshots(from releases: [GitHubReleaseService.Release], into repository: inout WatchedRepository) {
        var snapshotsByTag: [String: ReleaseSnapshot] = [:]

        for snapshot in repository.snapshots {
            snapshotsByTag[snapshot.tagName] = snapshot
        }

        for release in releases {
            if var existingSnapshot = snapshotsByTag[release.tagName] {
                existingSnapshot.releaseName = release.name
                existingSnapshot.htmlURL = release.htmlURL
                existingSnapshot.publishedAt = release.publishedAt
                snapshotsByTag[release.tagName] = existingSnapshot
            } else {
                snapshotsByTag[release.tagName] = ReleaseSnapshot(
                    tagName: release.tagName,
                    releaseName: release.name,
                    publishedAt: release.publishedAt,
                    htmlURL: release.htmlURL
                )
            }
        }

        repository.snapshots = snapshotsByTag.values.sorted {
            snapshotDate(for: $0) > snapshotDate(for: $1)
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

    private func snapshotDate(for snapshot: ReleaseSnapshot) -> Date {
        snapshot.publishedAt ?? snapshot.createdAt
    }

    private func effectiveUnreadBaseline(for repository: WatchedRepository) -> Date {
        let baseline = lastMenuBarOpenedAt
            ?? repository.unreadBaselineAt
            ?? repository.addedAt

        return max(baseline, repository.addedAt)
    }

    private func knownReleaseDate(for repository: WatchedRepository) -> Date? {
        var dates = repository.snapshots.map(snapshotDate)
        if let latestReleasePublishedAt = repository.latestReleasePublishedAt {
            dates.append(latestReleasePublishedAt)
        }

        return dates.max()
    }

    private func notifyStateChange() {
        onStateChange?()
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
