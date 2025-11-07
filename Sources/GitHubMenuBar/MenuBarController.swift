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
    /// - "Refresh" action
    /// - "Filter by Status" submenu
    /// - Separator
    /// - Status/PRs: One of:
    ///   - "Loading..." (if isLoading)
    ///   - "Error: ..." (if lastError is set)
    ///   - "No pending reviews" (if pullRequests is empty)
    ///   - List of PRs (clickable multi-line items)
    /// - Padding items (to ensure minimum height equivalent to 10 PRs)
    /// - Separator
    /// - "Quit" action
    ///
    /// Each PR menu item displays:
    /// - Line 1: "repo/owner #123: PR Title [STATUS]"
    ///   Status pill shows DRAFT (gray), OPEN (green), MERGED (purple), or CLOSED (red)
    /// - Line 2: "   opened Z ago • by author • X assignees • Y comments"
    ///   (assignees and comments only shown if applicable)
    private func updateMenu() {
        menu.removeAllItems()

        // Title
        let titleItem = NSMenuItem(title: "GitHub PR Reviews", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // Refresh action (⌘R keyboard shortcut)
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Settings submenu
        let settingsItem = NSMenuItem(title: "Filter by Status", action: nil, keyEquivalent: "")
        let settingsSubmenu = NSMenu()

        // Add a description item
        let descItem = NSMenuItem(title: "Show PRs with status:", action: nil, keyEquivalent: "")
        descItem.isEnabled = false
        settingsSubmenu.addItem(descItem)
        settingsSubmenu.addItem(NSMenuItem.separator())

        // Add checkbox items for each status
        for status in PRStatus.allCases {
            let statusItem = NSMenuItem(
                title: status.displayName,
                action: #selector(toggleStatusFilter(_:)),
                keyEquivalent: ""
            )
            statusItem.target = self
            statusItem.representedObject = status
            // Check if this status is NOT excluded (i.e., included)
            statusItem.state = AppSettings.shared.isExcluded(status) ? .off : .on
            settingsSubmenu.addItem(statusItem)
        }

        settingsItem.submenu = settingsSubmenu
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Track the number of content items we're adding (for minimum height calculation)
        var contentItemCount = 0

        if isLoading {
            let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
            contentItemCount = 1
        } else if let error = lastError {
            let errorItem = NSMenuItem(title: "Error: \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            contentItemCount = 1
        } else if pullRequests.isEmpty {
            let emptyItem = NSMenuItem(title: "No pending reviews", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            contentItemCount = 1
        } else {
            // Create a menu item for each PR
            for pr in pullRequests {
                // Build metadata line in order: age, author, assignees, comments
                var metadataParts: [String] = []

                // Age comes first for better scannability
                metadataParts.append("opened \(pr.formattedAge())")

                // Author
                metadataParts.append("by \(pr.author.login)")

                // Assignees (if any)
                let assigneeCount = pr.assignees.count
                if assigneeCount > 0 {
                    metadataParts.append("\(assigneeCount) assignee\(assigneeCount == 1 ? "" : "s")")
                }

                // Comments (if any)
                if pr.commentsCount > 0 {
                    metadataParts.append("\(pr.commentsCount) comment\(pr.commentsCount == 1 ? "" : "s")")
                }

                let metadataLine = "   " + metadataParts.joined(separator: " • ")

                // Create attributed string with styled formatting
                let attributedTitle = NSMutableAttributedString()

                // First line: repo/number (muted) + title (prominent)
                let font = NSFont.menuFont(ofSize: 0) // 0 = default menu font size

                // Muted attributes for repo name and number
                let mutedAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]

                // Normal attributes for PR title
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor
                ]

                // Add repo name and PR number (muted)
                attributedTitle.append(NSAttributedString(
                    string: "\(pr.repository.nameWithOwner) #\(pr.number): ",
                    attributes: mutedAttributes
                ))

                // Add PR title (prominent)
                attributedTitle.append(NSAttributedString(
                    string: pr.title,
                    attributes: titleAttributes
                ))

                // Add status indicator with rounded pill styling
                attributedTitle.append(NSAttributedString(string: " ", attributes: titleAttributes))

                // Determine status text and color
                let (statusText, statusColor): (String, NSColor) = {
                    if pr.isDraft {
                        return ("DRAFT", NSColor.systemGray)
                    } else {
                        switch pr.state.uppercased() {
                        case "OPEN":
                            return ("OPEN", self.githubGreen)
                        case "MERGED":
                            return ("MERGED", self.githubPurple)
                        case "CLOSED":
                            return ("CLOSED", self.githubRed)
                        default:
                            return (pr.state, NSColor.systemGray)
                        }
                    }
                }()

                // Create rounded pill image
                let pillImage = createPillImage(
                    text: statusText,
                    backgroundColor: statusColor,
                    textColor: NSColor.white
                )

                // Attach image to attributed string with proper baseline alignment
                let attachment = NSTextAttachment()
                attachment.image = pillImage

                // Calculate vertical offset to center pill with text x-height
                let yOffset = (font.xHeight - pillImage.size.height) / 2.0
                attachment.bounds = CGRect(x: 0, y: yOffset, width: pillImage.size.width, height: pillImage.size.height)

                let attachmentString = NSAttributedString(attachment: attachment)
                attributedTitle.append(attachmentString)

                // Newline
                attributedTitle.append(NSAttributedString(string: "\n"))

                // Second line: smaller size, secondary color, with proper paragraph spacing
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 2

                let metadataAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraphStyle
                ]
                attributedTitle.append(NSAttributedString(string: metadataLine, attributes: metadataAttributes))

                let prItem = NSMenuItem()
                prItem.attributedTitle = attributedTitle
                prItem.action = #selector(openPR(_:))
                prItem.keyEquivalent = ""
                prItem.target = self
                // Store the URL in representedObject so we can access it in the action
                prItem.representedObject = pr.url
                menu.addItem(prItem)
                contentItemCount += 1
            }
        }

        // Add padding items to ensure minimum height (equivalent to 10 PRs)
        let minimumContentItems = 10
        let paddingItemsNeeded = max(0, minimumContentItems - contentItemCount)

        for _ in 0..<paddingItemsNeeded {
            // Create invisible spacer items that maintain menu height
            // Using a non-breaking space to make the item take up vertical space
            let spacerItem = NSMenuItem(title: " ", action: nil, keyEquivalent: "")
            spacerItem.isEnabled = false
            menu.addItem(spacerItem)
        }

        // Quit action (⌘Q keyboard shortcut)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Helper Methods

    /// GitHub's official brand colors for PR statuses
    private var githubGreen: NSColor {
        NSColor(red: 0x2d / 255.0, green: 0xa4 / 255.0, blue: 0x4e / 255.0, alpha: 1.0)
    }

    private var githubPurple: NSColor {
        NSColor(red: 0x82 / 255.0, green: 0x50 / 255.0, blue: 0xdf / 255.0, alpha: 1.0)
    }

    private var githubRed: NSColor {
        NSColor(red: 0xcf / 255.0, green: 0x22 / 255.0, blue: 0x2e / 255.0, alpha: 1.0)
    }

    /// Creates a rounded pill image for badge display (e.g., DRAFT indicator).
    ///
    /// - Parameters:
    ///   - text: The text to display in the pill
    ///   - backgroundColor: The background color of the pill
    ///   - textColor: The text color
    /// - Returns: An NSImage of the rounded pill
    private func createPillImage(text: String, backgroundColor: NSColor, textColor: NSColor) -> NSImage {
        let font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (text as NSString).size(withAttributes: attributes)

        // Add padding around text
        let padding: CGFloat = 4
        let height: CGFloat = textSize.height + padding
        let width: CGFloat = textSize.width + padding * 2
        let cornerRadius: CGFloat = height / 2

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        // Draw rounded rectangle background
        let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        path.fill()

        // Draw text centered
        let textRect = NSRect(x: padding, y: padding / 2, width: textSize.width, height: textSize.height)
        (text as NSString).draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        return image
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

    /// Toggles the exclusion state of a PR status filter.
    ///
    /// Called when user clicks a status checkbox in the settings submenu.
    /// The status value is stored in the menu item's representedObject property.
    /// After toggling, triggers a refresh to fetch PRs with the new filter.
    @objc private func toggleStatusFilter(_ sender: NSMenuItem) {
        guard let status = sender.representedObject as? PRStatus else {
            return
        }

        // Toggle the exclusion
        AppSettings.shared.toggleExclusion(for: status)

        // Update the menu item state
        sender.state = AppSettings.shared.isExcluded(status) ? .off : .on

        // Trigger a refresh to fetch with new filters
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
