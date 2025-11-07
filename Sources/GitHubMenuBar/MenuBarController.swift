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

    /// Timer for automatic refresh (interval configured in AppSettings)
    private var refreshTimer: Timer?

    // MARK: - Initialization

    override init() {
        super.init()
        setupMenuBar()
        setupRefreshTimer()

        // Wire up settings window callback to trigger refresh
        SettingsWindowController.shared.onSettingsChanged = { [weak self] in
            Task {
                await self?.refresh()
            }
        }

        // Observe settings changes to update refresh interval
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: AppSettings.didChangeNotification,
            object: nil
        )

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

    /// Sets up a timer to automatically refresh PR data based on user's configured interval.
    ///
    /// The timer uses weak self to avoid retain cycles.
    /// The interval is read from AppSettings.shared.refreshIntervalSeconds.
    private func setupRefreshTimer() {
        // Invalidate any existing timer first
        refreshTimer?.invalidate()

        // Create new timer with configured interval
        let interval = AppSettings.shared.refreshIntervalSeconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.refresh()
            }
        }
    }

    /// Called when AppSettings change notification is received.
    ///
    /// Recreates the refresh timer with the new interval.
    @objc private func settingsDidChange() {
        setupRefreshTimer()
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
    /// - Title: "GitHub PR Reviews" or "GitHub PR Reviews (Refreshing...)"
    /// - Separator
    /// - "Refresh" button
    /// - "Settings..." menu item (⌘,)
    /// - Separator
    /// - Status/PRs: One of:
    ///   - "Loading..." (if isLoading AND no cached PRs)
    ///   - "Error: ..." (if lastError is set AND no cached PRs)
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

        // Title and Refresh button combined on one line to save vertical space
        let titleText: String
        if isLoading && !pullRequests.isEmpty {
            titleText = "GitHub PR Reviews (Refreshing...)"
        } else {
            titleText = "GitHub PR Reviews"
        }

        // Create attributed string with bold, black text for title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.black
        ]
        let attributedTitle = NSAttributedString(string: titleText, attributes: titleAttributes)

        // Create title label
        let titleLabel = NSTextField(labelWithAttributedString: attributedTitle)
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.sizeToFit()

        // Create refresh button
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .recessed
        refreshButton.isBordered = true
        refreshButton.alignment = .center
        refreshButton.sizeToFit()

        // Size button slightly wider for better appearance
        let buttonWidth = max(refreshButton.frame.width + 16, 80)
        refreshButton.frame.size.width = buttonWidth

        // Set container width to match typical PR item width in the menu
        // PR items are typically 450-550px wide, so we use a fixed width that matches
        // This ensures the button aligns to the right edge of the entire menu
        // TODO: Improve button alignment - currently uses fixed width which doesn't perfectly
        // match the dynamic menu width. Consider calculating actual menu width or using
        // NSMenu's intrinsic width to ensure perfect right alignment.
        let containerWidth: CGFloat = 500
        let containerHeight: CGFloat = 32
        let leftPadding: CGFloat = 12
        let rightPadding: CGFloat = 12
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))

        // Position title on the left
        titleLabel.frame.origin = NSPoint(x: leftPadding, y: (containerHeight - titleLabel.frame.height) / 2)

        // Position button on the right (truly aligned to the right)
        refreshButton.frame.origin = NSPoint(
            x: containerWidth - buttonWidth - rightPadding,
            y: (containerHeight - refreshButton.frame.height) / 2
        )

        containerView.addSubview(titleLabel)
        containerView.addSubview(refreshButton)

        let headerItem = NSMenuItem()
        headerItem.view = containerView
        menu.addItem(headerItem)

        // Settings menu item
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Track the number of content items we're adding (for minimum height calculation)
        var contentItemCount = 0

        // Show loading/error states only if we have no cached PR data
        // This allows users to see previously fetched PRs while refreshing
        if isLoading && pullRequests.isEmpty {
            let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
            contentItemCount = 1
        } else if let error = lastError, pullRequests.isEmpty {
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
    /// Kicks off an async refresh operation. The menu stays open during the refresh.
    @objc private func refreshClicked() {
        Task {
            await refresh()
        }
    }

    /// Opens the settings window.
    ///
    /// Called when user clicks the "Settings..." button in the menu.
    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }

    /// Quits the application.
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Cleanup

    /// Cleanup when the controller is deallocated.
    ///
    /// Invalidates timers to prevent them from firing after deallocation.
    /// Uses MainActor.assumeIsolated since deinit is nonisolated but we need
    /// to access main-actor-isolated properties.
    nonisolated deinit {
        MainActor.assumeIsolated {
            refreshTimer?.invalidate()
        }
    }
}
