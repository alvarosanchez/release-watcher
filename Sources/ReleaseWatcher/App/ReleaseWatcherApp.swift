import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let appState = AppState()
    private let repositoryStore = RepositoryStore()
    private var managementWindowController: NSWindowController?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var eventMonitor: Any?

    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        configurePopover()

        Task { @MainActor in
            await repositoryStore.requestNotificationPermission()
            appState.startPollingIfNeeded(repositoryStore: repositoryStore, intervalMinutes: refreshIntervalMinutes)
            await repositoryStore.refreshRepositories(appState: appState)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func installStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "Release Watcher")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = popoverSize
        refreshPopoverContent()
    }

    private var popoverSize: NSSize {
        let visibleCount = repositoryStore.sortedRepositories.count
        let headerHeight: CGFloat = 74
        let footerHeight: CGFloat = 44
        let dividerHeight: CGFloat = 2
        let contentPadding: CGFloat = 24
        let rowHeight: CGFloat = 70
        let rowSpacing: CGFloat = 8

        let naturalRowsHeight = CGFloat(visibleCount) * rowHeight + CGFloat(max(visibleCount - 1, 0)) * rowSpacing
        let contentHeight = visibleCount == 0 ? 180 : min(naturalRowsHeight + 8, 420)
        let totalHeight = headerHeight + footerHeight + dividerHeight + dividerHeight + contentPadding + contentHeight

        return NSSize(width: 400, height: totalHeight)
    }

    private func refreshPopoverContent() {
        popover.contentSize = popoverSize
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                showManagementWindow: { self.showManagementWindow() }
            )
            .environment(appState)
            .environment(repositoryStore)
        )
    }

    @MainActor
    private func showManagementWindow() {
        if let window = managementWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let repositoryListView = RepositoryListView(
            launchAtLoginEnabled: loginItemEnabled,
            toggleLaunchAtLogin: { [weak self] enabled in
                if let self {
                    try self.setLaunchAtLogin(enabled: enabled)
                }
            },
            onClose: { [weak self] in
                self?.refreshPopoverContent()
            }
        )
        .environment(appState)
        .environment(repositoryStore)
        .onChange(of: refreshIntervalMinutes) { [self] _, newValue in
            self.appState.restartPolling(repositoryStore: self.repositoryStore, intervalMinutes: newValue)
            self.refreshPopoverContent()
        }

        let hostingController = NSHostingController(rootView: repositoryListView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Watch Repositories"
        window.setContentSize(NSSize(width: 620, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        managementWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            showStatusItemMenu()
        default:
            togglePopover(sender)
        }
    }

    private func showStatusItemMenu() {
        closePopover(nil)

        let menu = NSMenu()
        menu.addItem(withTitle: aboutMenuTitle, action: #selector(showManagementWindowFromMenu), keyEquivalent: "")

        if let update = repositoryStore.availableAppUpdate, update.isNewerThanInstalled {
            menu.addItem(withTitle: "Download Release Watcher \(update.latestVersion)", action: #selector(openLatestAppReleaseFromMenu), keyEquivalent: "")
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Release Watcher", action: #selector(togglePopover(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Manage Repositories", action: #selector(showManagementWindowFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private var aboutMenuTitle: String {
        "About Release Watcher \(AppMetadata.versionString)"
    }

    @objc
    private func showManagementWindowFromMenu() {
        showManagementWindow()
    }

    @objc
    private func openLatestAppReleaseFromMenu() {
        guard let url = repositoryStore.availableAppUpdate?.releaseURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func refreshFromMenu() {
        Task { @MainActor in
            await repositoryStore.refreshRepositories(appState: appState)
            self.refreshPopoverContent()
        }
    }

    @objc
    private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover()
        }
    }

    @MainActor
    private func showPopover() {
        refreshPopoverContent()

        guard let button = statusItem.button, !popover.isShown else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)

        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover(nil)
            }
        }
    }

    @objc
    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
    }

    func popoverDidClose(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

@main
struct ReleaseWatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@Observable
@MainActor
final class AppState {
    var isRefreshing = false
    var lastRefreshAt: Date?
    var lastErrorMessage: String?
    private var pollingTask: Task<Void, Never>?

    func startPollingIfNeeded(repositoryStore: RepositoryStore, intervalMinutes: Int) {
        guard pollingTask == nil else {
            return
        }

        startPolling(repositoryStore: repositoryStore, intervalMinutes: intervalMinutes)
    }

    func restartPolling(repositoryStore: RepositoryStore, intervalMinutes: Int) {
        pollingTask?.cancel()
        pollingTask = nil
        startPolling(repositoryStore: repositoryStore, intervalMinutes: intervalMinutes)
    }

    private func startPolling(repositoryStore: RepositoryStore, intervalMinutes: Int) {
        let intervalNanoseconds = UInt64(max(1, intervalMinutes) * 60) * 1_000_000_000

        pollingTask = Task { [weak self, weak repositoryStore] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }

                guard let self, let repositoryStore else {
                    break
                }

                await repositoryStore.refreshRepositories(appState: self)
            }
        }
    }
}
