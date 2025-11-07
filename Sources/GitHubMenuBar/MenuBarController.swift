import AppKit
import Foundation

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var pullRequests: [PullRequest] = []
    private var isLoading = false
    private var lastError: String?
    private var refreshTimer: Timer?

    override init() {
        super.init()
        setupMenuBar()
        setupRefreshTimer()
        Task {
            await refresh()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: "GitHub PRs")
        }

        menu = NSMenu()
        statusItem.menu = menu
    }

    private func setupRefreshTimer() {
        // Refresh every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task {
                await self?.refresh()
            }
        }
    }

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
            for pr in pullRequests {
                let prItem = NSMenuItem(
                    title: "\(pr.repository.nameWithOwner) #\(pr.number): \(pr.title)",
                    action: #selector(openPR(_:)),
                    keyEquivalent: ""
                )
                prItem.target = self
                prItem.representedObject = pr.url
                prItem.toolTip = "by \(pr.author.login)"
                menu.addItem(prItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Refresh action
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Quit action
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openPR(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshClicked() {
        Task {
            await refresh()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    nonisolated deinit {
        MainActor.assumeIsolated {
            refreshTimer?.invalidate()
        }
    }
}
