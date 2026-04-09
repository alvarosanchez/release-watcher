import SwiftUI

struct RepositoryListView: View {
    @Environment(AppState.self) private var appState
    @Environment(RepositoryStore.self) private var repositoryStore
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 30

    @FocusState private var focusedField: Field?
    @State private var repositoryInput = ""
    @State private var refreshIntervalInput = "30"
    @State private var selectedRepositoryIDs = Set<UUID>()
    @State private var launchAtLoginEnabled: Bool
    @State private var launchAtLoginError: String?

    let toggleLaunchAtLogin: (Bool) throws -> Void
    let onClose: () -> Void

    private enum Field: Hashable {
        case repository
        case refreshInterval
    }

    init(
        launchAtLoginEnabled: Bool = false,
        toggleLaunchAtLogin: @escaping (Bool) throws -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        _launchAtLoginEnabled = State(initialValue: launchAtLoginEnabled)
        self.toggleLaunchAtLogin = toggleLaunchAtLogin
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            addRepositoryForm
            preferencesForm
            repositoryTable
            statusFooter
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .onAppear {
            refreshIntervalInput = String(refreshIntervalMinutes)
        }
        .onDisappear {
            applyRefreshIntervalInput()
            onClose()
        }
        .onChange(of: refreshIntervalMinutes) { _, newValue in
            refreshIntervalInput = String(newValue)
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .refreshInterval, newValue != .refreshInterval {
                applyRefreshIntervalInput()
            }
        }
    }

    private var addRepositoryForm: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Watch GitHub repositories",
                    symbol: "plus.circle.fill"
                )

                TextField("github.com/owner/repo or owner/repo", text: $repositoryInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .repository)

                HStack(alignment: .center) {
                    Text("Paste a full GitHub URL or a repository slug.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Add Repository") {
                        addRepository()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var preferencesForm: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "Preferences",
                    symbol: "gearshape.fill"
                )

                HStack(alignment: .center, spacing: 12) {
                    Text("Check GitHub every")
                        .font(.body)

                    TextField("Minutes", text: $refreshIntervalInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .refreshInterval)
                        .onSubmit {
                            applyRefreshIntervalInput()
                        }

                    Text("minutes")
                        .foregroundStyle(.secondary)

                    Button("Save") {
                        applyRefreshIntervalInput()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                Toggle("Open Release Watcher at login", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)

                if let launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let notificationError = repositoryStore.lastNotificationError {
                    Label("Notifications currently unavailable: \(notificationError)", systemImage: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Release Watcher stays in the menu bar and checks GitHub releases on this schedule.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var repositoryTable: some View {
        Table(of: WatchedRepository.self, selection: $selectedRepositoryIDs) {
            TableColumn("Repository") { repository in
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.displayName)
                        if let latestReleaseName = repository.latestReleaseName, latestReleaseName != repository.latestKnownTag {
                            Text(latestReleaseName)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            TableColumn("Latest Release") { repository in
                Text(repository.latestKnownTag ?? "No releases yet")
                    .font(.caption.monospaced())
            }
            TableColumn("Released") { repository in
                if let publishedAt = repository.latestReleasePublishedAt {
                    Label {
                        Text(publishedAt, format: .relative(presentation: .named))
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Unknown")
                        .foregroundStyle(.secondary)
                }
            }
        } rows: {
            ForEach(repositoryStore.sortedRepositories) { repository in
                TableRow(repository)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Delete", role: .destructive) {
                removeRepositories(matching: ids)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await repositoryStore.refreshRepositories(appState: appState)
                    }
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }
                .help("Check all watched repositories now")
                .disabled(appState.isRefreshing || repositoryStore.repositories.isEmpty)

                Button(role: .destructive) {
                    removeRepositories(matching: selectedRepositoryIDs)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Remove the selected repositories")
                .disabled(selectedRepositoryIDs.isEmpty)
            }
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let persistenceError = repositoryStore.lastPersistenceError {
                    Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Storage: \(repositoryStore.storageLocationDescription)")
                        .foregroundStyle(.secondary)
                } else if let error = appState.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if appState.isRefreshing {
                    Label("Checking GitHub for new releases…", systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                } else if let lastRefreshAt = appState.lastRefreshAt {
                    Label("Last checked \(lastRefreshAt, format: .relative(presentation: .named)).", systemImage: "clock")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Add one or more repositories. The menu bar app will keep checking them automatically.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            VStack(alignment: .leading, spacing: 4) {
                Link(destination: URL(string: "https://github.com/alvarosanchez/release-watcher")!) {
                    Label("Visit the project page, report issues, or star Release Watcher if you enjoy it", systemImage: "arrow.up.forward.square")
                }
                .font(.caption)

                Text("Crafted with love, care, and a little sparkle by Álvaro Sánchez-Mariscal.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionHeader(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { newValue in
                do {
                    try toggleLaunchAtLogin(newValue)
                    launchAtLoginEnabled = newValue
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    private func addRepository() {
        let trimmedInput = repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedInput.isEmpty else {
            return
        }

        do {
            try repositoryStore.addRepository(from: trimmedInput)
            repositoryInput = ""
            appState.lastErrorMessage = nil

            Task {
                try? await Task.sleep(for: .seconds(0.2))
                await repositoryStore.refreshRepositories(appState: appState)
            }
        } catch {
            appState.lastErrorMessage = error.localizedDescription
        }
    }

    private func removeRepositories(matching identifiers: Set<UUID>) {
        do {
            try repositoryStore.removeRepositories(withIDs: identifiers)
            selectedRepositoryIDs.subtract(identifiers)
        } catch {
            appState.lastErrorMessage = error.localizedDescription
        }
    }

    private func applyRefreshIntervalInput() {
        let digits = refreshIntervalInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsedValue = Int(digits) else {
            refreshIntervalInput = String(refreshIntervalMinutes)
            return
        }

        let clampedValue = min(max(parsedValue, 1), 1440)
        refreshIntervalMinutes = clampedValue
        refreshIntervalInput = String(clampedValue)
    }
}
