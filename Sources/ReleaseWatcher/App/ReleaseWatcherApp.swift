import SwiftUI

@main
struct ReleaseWatcherApp: App {
    @State private var appState = AppState()
    @State private var repositoryStore = RepositoryStore()

    var body: some Scene {
        WindowGroup("Repositories") {
            RepositoryListView()
                .environment(appState)
                .environment(repositoryStore)
        }
        .defaultSize(width: 520, height: 420)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(repositoryStore)
        }

        MenuBarExtra {
            MenuBarContentView()
                .environment(appState)
                .environment(repositoryStore)
        } label: {
            Label("Release Watcher", systemImage: "dot.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
    }
}

@Observable
final class AppState {
    var isRefreshing = false
    var lastRefreshAt: Date?
    var lastErrorMessage: String?
}
