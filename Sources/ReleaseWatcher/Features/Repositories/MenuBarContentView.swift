import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let showManagementWindow: @MainActor () -> Void

    @Environment(AppState.self) private var appState
    @Environment(RepositoryStore.self) private var repositoryStore
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 30

    private enum Layout {
        static let popoverWidth: CGFloat = 400
        static let outerPadding: CGFloat = 16
        static let sectionPadding: CGFloat = 12
        static let rowPaddingX: CGFloat = 12
        static let rowPaddingY: CGFloat = 9
        static let rowCornerRadius: CGFloat = 12
        static let rowSpacing: CGFloat = 8
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Layout.outerPadding)
                .padding(.top, Layout.sectionPadding)
                .padding(.bottom, Layout.sectionPadding)

            Divider()

            content
                .padding(.horizontal, Layout.sectionPadding)
                .padding(.vertical, Layout.sectionPadding)

            Divider()

            footer
                .padding(.horizontal, Layout.sectionPadding)
                .padding(.vertical, 10)
        }
        .frame(width: Layout.popoverWidth)
        .background(.regularMaterial)
        .onAppear {
            if repositoryStore.repositories.isEmpty {
                showManagementWindow()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("Release Watcher")
                        .font(.headline)
                }

                HStack(spacing: 6) {
                    Text(statusSummary)
                    Text("•")
                    Text("Every \(refreshIntervalMinutes)m")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                if appState.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 2)
                }

                headerIconButton(systemImage: "arrow.clockwise", help: "Refresh now") {
                    Task {
                        await repositoryStore.refreshRepositories(appState: appState)
                    }
                }
                .disabled(repositoryStore.repositories.isEmpty || appState.isRefreshing)

                headerIconButton(systemImage: "slider.horizontal.3", help: "Manage repositories") {
                    showManagementWindow()
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if repositoryStore.repositories.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text("No repositories yet")
                        .font(.headline)

                    Text("Add repositories in the management window to start tracking releases.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Add Your First Repository") {
                    showManagementWindow()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            ScrollView {
                VStack(spacing: Layout.rowSpacing) {
                    ForEach(repositoryStore.sortedRepositories) { repository in
                        repositoryRow(repository)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 280)
        }
    }

    private func repositoryRow(_ repository: WatchedRepository) -> some View {
        Button {
            openLatestRelease(for: repository)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(rowAccent(for: repository))
                        .frame(width: 8, height: 8)

                    Text(repository.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    releaseBadge(for: repository)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(repository.latestReleaseName ?? repository.latestKnownTag ?? "No published release found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Text(releaseDateText(for: repository))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if repository.latestReleaseURL != nil {
                            Image(systemName: "arrow.up.forward")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.rowPaddingX)
            .padding(.vertical, Layout.rowPaddingY)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous)
                    .fill(.quaternary.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(repository.latestReleaseURL == nil ? "No release page available yet" : "Open the latest release in your browser")
        .disabled(repository.latestReleaseURL == nil)
        .focusable(false)
    }

    private func releaseBadge(for repository: WatchedRepository) -> some View {
        Text(repository.latestKnownTag ?? "No release")
            .font(.caption.weight(.medium))
            .foregroundStyle(repository.latestKnownTag == nil ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label("\(repositoryStore.repositories.count) watched", systemImage: "number.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit")
            .keyboardShortcut("q")
            .focusable(false)
        }
    }

    private func headerIconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .focusable(false)
    }

    private func openLatestRelease(for repository: WatchedRepository) {
        guard let url = repository.latestReleaseURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private var statusSummary: String {
        if appState.isRefreshing {
            return "Refreshing…"
        }

        if let lastRefreshAt = appState.lastRefreshAt {
            return "Updated \(lastRefreshAt.formatted(.relative(presentation: .named)))"
        }

        return repositoryStore.repositories.isEmpty ? "No repositories configured" : "Watching \(repositoryStore.repositories.count) repositories"
    }

    private func rowAccent(for repository: WatchedRepository) -> Color {
        repository.latestKnownTag == nil ? .secondary : .green
    }

    private func releaseDateText(for repository: WatchedRepository) -> String {
        if let publishedAt = repository.latestReleasePublishedAt {
            return publishedAt.formatted(.relative(presentation: .named))
        }

        return "Unknown date"
    }
}
