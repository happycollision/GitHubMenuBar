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
            // Check if grouping by repository is enabled
            if AppSettings.shared.groupByRepo {
                // Group PRs by repository
                var prsByRepo: [String: [PullRequest]] = [:]
                for pr in pullRequests {
                    let repoName = pr.repository.nameWithOwner
                    if prsByRepo[repoName] == nil {
                        prsByRepo[repoName] = []
                    }
                    prsByRepo[repoName]?.append(pr)
                }

                // Sort repositories by most recent PR (earliest createdAt date)
                let sortedRepos = prsByRepo.keys.sorted { repo1, repo2 in
                    let mostRecentPR1 = prsByRepo[repo1]?.min(by: { $0.createdAt > $1.createdAt })
                    let mostRecentPR2 = prsByRepo[repo2]?.min(by: { $0.createdAt > $1.createdAt })

                    if let pr1 = mostRecentPR1, let pr2 = mostRecentPR2 {
                        return pr1.createdAt > pr2.createdAt // More recent first
                    }
                    return repo1 < repo2 // Fallback to alphabetical
                }

                // Display grouped PRs
                for repoName in sortedRepos {
                    guard let repoPRs = prsByRepo[repoName] else { continue }

                    // Add repository header with bold, black text
                    let prCount = repoPRs.count
                    let headerText = "\(repoName) (\(prCount) PR\(prCount == 1 ? "" : "s"))"

                    let headerAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                        .foregroundColor: NSColor.black
                    ]
                    let attributedHeader = NSAttributedString(string: headerText, attributes: headerAttributes)

                    let headerLabel = NSTextField(labelWithAttributedString: attributedHeader)
                    headerLabel.isEditable = false
                    headerLabel.isSelectable = false
                    headerLabel.isBordered = false
                    headerLabel.drawsBackground = false
                    headerLabel.sizeToFit()

                    // Add padding around the header
                    let headerPadding: CGFloat = 12
                    let headerContainer = NSView(frame: NSRect(
                        x: 0,
                        y: 0,
                        width: headerLabel.frame.width + headerPadding * 2,
                        height: headerLabel.frame.height + 4
                    ))
                    headerLabel.frame.origin = NSPoint(x: headerPadding, y: 2)
                    headerContainer.addSubview(headerLabel)

                    let headerItem = NSMenuItem()
                    headerItem.view = headerContainer
                    menu.addItem(headerItem)
                    contentItemCount += 1

                    // Add separator after header
                    menu.addItem(NSMenuItem.separator())

                    // Add PRs for this repository (without repo name in title)
                    for pr in repoPRs {
                        let prMenuItem = createPRMenuItem(pr: pr, includeRepoName: false)
                        menu.addItem(prMenuItem)
                        contentItemCount += 1
                    }

                    // Add separator after repo's PRs
                    menu.addItem(NSMenuItem.separator())
                }
            } else {
                // Flat list mode: Create a menu item for each PR (with repo name)
                for pr in pullRequests {
                    let prMenuItem = createPRMenuItem(pr: pr, includeRepoName: true)
                    menu.addItem(prMenuItem)
                    contentItemCount += 1
                }
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

    /// Creates a menu item for a pull request with formatted title and metadata.
    ///
    /// - Parameters:
    ///   - pr: The pull request to create a menu item for
    ///   - includeRepoName: Whether to include the repository name in the title
    /// - Returns: A configured NSMenuItem ready to be added to the menu
    private func createPRMenuItem(pr: PullRequest, includeRepoName: Bool) -> NSMenuItem {
        // Format the metadata line (age, author, assignees, comments)
        var metadataParts: [String] = []
        metadataParts.append("opened \(pr.formattedAge())")
        metadataParts.append("by \(pr.author.login)")

        if !pr.assignees.isEmpty {
            metadataParts.append("\(pr.assignees.count) assignee\(pr.assignees.count == 1 ? "" : "s")")
        }

        if pr.commentsCount > 0 {
            metadataParts.append("\(pr.commentsCount) comment\(pr.commentsCount == 1 ? "" : "s")")
        }

        let metadataLine = "   " + metadataParts.joined(separator: " • ")

        // Determine status text and color
        let (statusText, statusColor): (String, NSColor)
        if pr.isDraft {
            statusText = "DRAFT"
            statusColor = .systemGray
        } else {
            switch pr.state.uppercased() {
            case "OPEN":
                statusText = "OPEN"
                statusColor = githubGreen
            case "MERGED":
                statusText = "MERGED"
                statusColor = githubPurple
            case "CLOSED":
                statusText = "CLOSED"
                statusColor = githubRed
            default:
                statusText = pr.state.uppercased()
                statusColor = .systemGray
            }
        }

        // Create status pill image
        let pillImage = createPillImage(text: statusText, backgroundColor: statusColor, textColor: .white)

        // Create attributed string for the first line
        let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let mutedFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let attributedTitle = NSMutableAttributedString()

        // Add repo name/PR number or just PR number based on includeRepoName parameter
        if includeRepoName {
            let repoText = "\(pr.repository.nameWithOwner) #\(pr.number): "
            let repoAttributes: [NSAttributedString.Key: Any] = [
                .font: mutedFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            attributedTitle.append(NSAttributedString(string: repoText, attributes: repoAttributes))
        } else {
            let numberText = "#\(pr.number): "
            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: mutedFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            attributedTitle.append(NSAttributedString(string: numberText, attributes: numberAttributes))
        }

        // Add PR title (normal color)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor
        ]
        attributedTitle.append(NSAttributedString(string: pr.title, attributes: titleAttributes))

        // Add status pill with proper baseline alignment
        attributedTitle.append(NSAttributedString(string: " "))
        let attachment = NSTextAttachment()
        attachment.image = pillImage

        // Calculate baseline offset to align pill with text
        // Using xHeight (height of lowercase 'x') as baseline reference
        let fontMetrics = titleFont.xHeight
        let imageHeight = pillImage.size.height
        let baselineOffset = (fontMetrics - imageHeight) / 2

        let attachmentString = NSAttributedString(attachment: attachment)
        let mutableAttachment = NSMutableAttributedString(attributedString: attachmentString)
        mutableAttachment.addAttribute(.baselineOffset, value: baselineOffset, range: NSRange(location: 0, length: 1))
        attributedTitle.append(mutableAttachment)

        // Combine both lines
        let fullTitle = attributedTitle.mutableCopy() as! NSMutableAttributedString
        fullTitle.append(NSAttributedString(string: "\n"))

        let metadataAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        fullTitle.append(NSAttributedString(string: metadataLine, attributes: metadataAttributes))

        // Create menu item with attributed string
        let menuItem = NSMenuItem()
        menuItem.attributedTitle = fullTitle
        menuItem.action = #selector(openPR(_:))
        menuItem.target = self
        menuItem.representedObject = pr.url

        return menuItem
    }

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
    deinit {
        refreshTimer?.invalidate()
    }
}
