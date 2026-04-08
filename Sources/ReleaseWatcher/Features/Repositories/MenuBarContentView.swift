import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(RepositoryStore.self) private var repositoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Release Watcher")
                    .font(.headline)
                Spacer()
                if appState.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if repositoryStore.repositories.isEmpty {
                ContentUnavailableView(
                    "No repositories yet",
                    systemImage: "shippingbox",
                    description: Text("Add a GitHub repository in the main window.")
                )
                .frame(width: 320)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(repositoryStore.repositories) { repository in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repository.displayName)
                                    .fontWeight(.medium)
                                Text(repository.latestKnownTag ?? "Unknown release")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .frame(width: 320)
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task {
                        await repositoryStore.refreshRepositories(appState: appState)
                    }
                }
                .disabled(repositoryStore.repositories.isEmpty || appState.isRefreshing)

                Spacer()

                SettingsLink {
                    Text("Settings")
                }
            }
        }
        .padding(14)
    }
}
