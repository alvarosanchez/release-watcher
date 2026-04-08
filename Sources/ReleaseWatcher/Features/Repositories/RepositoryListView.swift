import SwiftUI

struct RepositoryListView: View {
    @Environment(AppState.self) private var appState
    @Environment(RepositoryStore.self) private var repositoryStore

    @State private var owner = ""
    @State private var repositoryName = ""
    @State private var selectedRepositoryIDs = Set<UUID>()

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addRepositoryForm
            repositoryTable
            statusFooter
        }
        .padding(20)
        .task {
            await repositoryStore.requestNotificationPermission()
        }
    }

    private var addRepositoryForm: some View {
        GroupBox("Watch a repository") {
            HStack {
                TextField("Owner", text: $owner)
                Text("/")
                    .foregroundStyle(.secondary)
                TextField("Repository", text: $repositoryName)

                Button("Add") {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var repositoryTable: some View {
        Table(of: WatchedRepository.self, selection: $selectedRepositoryIDs) {
            TableColumn("Repository") { repository in
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.displayName)
                    Text(repository.latestKnownTag ?? "No release fetched yet")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            TableColumn("Latest Version") { repository in
                Text(repository.latestKnownTag ?? "—")
            }
            TableColumn("Updated") { repository in
                Text(repository.snapshots.first?.publishedAt ?? repository.addedAt, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            }
        } rows: {
            ForEach(repositoryStore.repositories) { repository in
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
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing || repositoryStore.repositories.isEmpty)

                Button(role: .destructive) {
                    removeRepositories(matching: selectedRepositoryIDs)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedRepositoryIDs.isEmpty)
            }
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = appState.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else if appState.isRefreshing {
                Text("Refreshing GitHub releases…")
                    .foregroundStyle(.secondary)
            } else if let lastRefreshAt = appState.lastRefreshAt {
                Text("Last refreshed \(lastRefreshAt, format: .relative(presentation: .named))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Add a repository, then refresh to fetch its latest release.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func addRepository() {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRepositoryName = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedOwner.isEmpty, !trimmedRepositoryName.isEmpty else {
            return
        }

        do {
            try repositoryStore.addRepository(owner: trimmedOwner, name: trimmedRepositoryName)
            owner = ""
            repositoryName = ""
            appState.lastErrorMessage = nil
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
}
