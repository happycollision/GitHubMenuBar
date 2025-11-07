import AppKit
import Foundation

/// Controller for the macOS menu bar item and its associated menu.
///
/// This class manages:
/// - NSStatusItem (the menu bar icon and badge)
/// - NSMenu (the dropdown menu with PR list)
/// - Data fetching and refresh logic
/// - User interactions (clicking PRs, refresh, quit)
///
/// Concurrency: Marked as @MainActor to ensure all UI updates happen on the main thread.
/// This is critical for AppKit components which are not thread-safe.
@MainActor
class MenuBarController: NSObject {
    // MARK: - Properties

    /// The status bar item (icon in the menu bar)
    private var statusItem: NSStatusItem!

    /// The menu that appears when clicking the status item
    private var menu: NSMenu!

    /// Currently loaded pull requests
    private var pullRequests: [PullRequest] = []

    /// Whether a refresh is currently in progress
    private var isLoading = false

    /// Last error message, if any
    private var lastError: String?

    /// Timer for automatic refresh every 5 minutes
    private var refreshTimer: Timer?

    // MARK: - Initialization

    override init() {
        super.init()
        setupMenuBar()
        setupRefreshTimer()
        // Kick off initial data fetch
        Task {
            await refresh()
        }
    }

    // MARK: - Setup

    /// Sets up the menu bar status item with icon and empty menu.
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use SF Symbol for the menu bar icon
            button.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: "GitHub PRs")
        }

        menu = NSMenu()
        statusItem.menu = menu
    }

    /// Sets up a timer to automatically refresh PR data every 5 minutes.
    ///
    /// The timer uses weak self to avoid retain cycles.
    private func setupRefreshTimer() {
        // Refresh every 5 minutes (300 seconds)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task {
                await self?.refresh()
            }
        }
    }

    // MARK: - Data Fetching

    /// Fetches the latest PR review requests from GitHub.
    ///
    /// This method:
    /// 1. Sets loading state and updates menu to show "Loading..."
    /// 2. Calls GitHubService to fetch PRs
    /// 3. Updates internal state (pullRequests or lastError)
    /// 4. Clears loading state and updates menu with results
    /// 5. Updates the badge count on the menu bar icon
    @objc private func refresh() async {
        isLoading = true
        updateMenu()

        do {
            pullRequests = try await GitHubService.shared.fetchReviewRequests()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            pullRequests = []
        }

        isLoading = false
        updateMenu()
        updateBadge()
    }

    // MARK: - UI Updates

    /// Updates the badge count on the menu bar icon.
    ///
    /// Shows the number of pending PRs next to the icon, or nothing if zero.
    private func updateBadge() {
        if let button = statusItem.button {
            let count = pullRequests.count
            if count > 0 {
                button.title = " \(count)"
            } else {
                button.title = ""
            }
        }
    }

    /// Rebuilds the entire menu based on current state.
    ///
    /// The menu structure is:
    /// - Title: "GitHub PR Reviews" (disabled)
    /// - Separator
    /// - Status/PRs: One of:
    ///   - "Loading..." (if isLoading)
    ///   - "Error: ..." (if lastError is set)
    ///   - "No pending reviews" (if pullRequests is empty)
    ///   - List of PRs (clickable items)
    /// - Separator
    /// - "Refresh" action
    /// - Separator
    /// - "Quit" action
    private func updateMenu() {
        menu.removeAllItems()

        // Title
        let titleItem = NSMenuItem(title: "GitHub PR Reviews", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        if isLoading {
            let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        } else if let error = lastError {
            let errorItem = NSMenuItem(title: "Error: \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        } else if pullRequests.isEmpty {
            let emptyItem = NSMenuItem(title: "No pending reviews", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            // Create a menu item for each PR
            for pr in pullRequests {
                let prItem = NSMenuItem(
                    title: "\(pr.repository.nameWithOwner) #\(pr.number): \(pr.title)",
                    action: #selector(openPR(_:)),
                    keyEquivalent: ""
                )
                prItem.target = self
                // Store the URL in representedObject so we can access it in the action
                prItem.representedObject = pr.url
                prItem.toolTip = "by \(pr.author.login)"
                menu.addItem(prItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Refresh action (⌘R keyboard shortcut)
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Quit action (⌘Q keyboard shortcut)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    /// Opens a PR in the default web browser.
    ///
    /// Called when user clicks a PR menu item. The PR URL is stored in
    /// the menu item's representedObject property.
    @objc private func openPR(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Handles the manual "Refresh" menu action.
    ///
    /// Kicks off an async refresh operation.
    @objc private func refreshClicked() {
        Task {
            await refresh()
        }
    }

    /// Quits the application.
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Cleanup

    /// Cleanup when the controller is deallocated.
    ///
    /// Invalidates the refresh timer to prevent it from firing after deallocation.
    /// Uses MainActor.assumeIsolated since deinit is nonisolated but we need
    /// to access main-actor-isolated properties.
    nonisolated deinit {
        MainActor.assumeIsolated {
            refreshTimer?.invalidate()
        }
    }
}
