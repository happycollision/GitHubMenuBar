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

    /// Whether there are more PRs available beyond what's displayed
    private var hasMorePRs = false

    /// Whether a refresh is currently in progress
    private var isLoading = false

    /// Last error message, if any
    private var lastError: String?

    /// Timer for automatic refresh (interval configured in AppSettings)
    private var refreshTimer: Timer?

    /// Currently running refresh task (to support cancellation)
    private var currentRefreshTask: Task<Void, Never>?

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
            // Use composite menu bar icon: anchor crossed out with slash
            button.image = createMenuBarIcon()
        }

        menu = NSMenu()
        statusItem.menu = menu
    }

    /// Creates a composite menu bar icon by layering an anchor character with a nosign (circle with slash) symbol.
    ///
    /// - Returns: An NSImage suitable for the menu bar
    private func createMenuBarIcon() -> NSImage? {
        // Menu bar icons are typically around 22x22 points
        let size = NSSize(width: 22, height: 22)

        // Get the nosign symbol (circle with slash) - thin weight for subtlety
        let nosignConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .thin)
        guard let nosignImage = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)?
            .withSymbolConfiguration(nosignConfig) else {
            // Fallback to previous icon if symbol not available
            return NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: "GitHub PRs")
        }

        // Create composite image
        let compositeImage = NSImage(size: size)
        compositeImage.lockFocus()

        // Save graphics state for rotation
        NSGraphicsContext.current?.saveGraphicsState()

        // Draw nosign centered and rotated 90 degrees
        let nosignSize = nosignImage.size
        let centerX = size.width / 2
        let centerY = size.height / 2

        // Set up rotation transform around the center
        var transform = AffineTransform()
        transform.translate(x: centerX, y: centerY)
        transform.rotate(byDegrees: 90)
        transform.translate(x: -nosignSize.width / 2, y: -nosignSize.height / 2)

        // Apply the transform
        (transform as NSAffineTransform).concat()

        // Draw the rotated nosign
        nosignImage.draw(at: .zero, from: NSRect(origin: .zero, size: nosignSize), operation: .sourceOver, fraction: 1.0)

        // Restore graphics state
        NSGraphicsContext.current?.restoreGraphicsState()

        // Draw anchor character using Unicode (U+2693 with text presentation selector U+FE0E)
        let anchorChar = "\u{2693}\u{FE0E}"  // ⚓︎ (text style, not emoji)
        let anchorFont = NSFont.systemFont(ofSize: 20, weight: .medium)
        let anchorAttributes: [NSAttributedString.Key: Any] = [
            .font: anchorFont,
            .foregroundColor: NSColor.labelColor
        ]

        let anchorString = anchorChar as NSString
        let anchorSize = anchorString.size(withAttributes: anchorAttributes)

        // Center the anchor and move it up by 2 pixels and right by 1 pixel relative to the circle
        let anchorRect = NSRect(
            x: (size.width - anchorSize.width) / 2 + 1,  // Move right by 1 pixel
            y: (size.height - anchorSize.height) / 2 + 1,  // Move up by 2 pixels (was +2, now +1)
            width: anchorSize.width,
            height: anchorSize.height
        )

        anchorString.draw(in: anchorRect, withAttributes: anchorAttributes)

        compositeImage.unlockFocus()
        compositeImage.isTemplate = true // Allow system to apply proper tinting
        compositeImage.accessibilityDescription = "GitHub PRs"

        return compositeImage
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
    /// 1. Cancels any ongoing refresh to prevent race conditions
    /// 2. Sets loading state and updates menu to show "Loading..."
    /// 3. Calls GitHubService to fetch PRs
    /// 4. Updates internal state (pullRequests or lastError)
    /// 5. Clears loading state and updates menu with results
    /// 6. Updates the badge count on the menu bar icon
    @objc private func refresh() async {
        // Cancel any ongoing refresh task to prevent race conditions
        currentRefreshTask?.cancel()

        // Create a new task for this refresh operation
        currentRefreshTask = Task { @MainActor in
            isLoading = true
            updateMenu()

            do {
                let result = try await GitHubService.shared.fetchReviewRequests()
                pullRequests = result.pullRequests
                hasMorePRs = result.hasMore
                lastError = nil
            } catch is CancellationError {
                // Task was cancelled, don't update state
                return
            } catch {
                lastError = error.localizedDescription
                pullRequests = []
                hasMorePRs = false
            }

            isLoading = false
            updateMenu()
            updateBadge()
        }

        // Wait for the task to complete
        await currentRefreshTask?.value
    }

    // MARK: - UI Updates

    /// Updates the badge count on the menu bar icon.
    ///
    /// Shows the number of pending PRs next to the icon, or nothing if zero.
    /// If there are more PRs available beyond the displayed limit, shows "50+".
    private func updateBadge() {
        if let button = statusItem.button {
            let count = pullRequests.count
            if count > 0 {
                if hasMorePRs {
                    button.title = " 50+"
                } else {
                    button.title = " \(count)"
                }
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

        // Create attributed string with bold text for title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
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
        let containerWidth: CGFloat = 500
        let containerHeight: CGFloat = 32
        let leftPadding: CGFloat = 12
        let rightPadding: CGFloat = 12
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))

        // Position title on the left
        titleLabel.frame.origin = NSPoint(x: leftPadding, y: (containerHeight - titleLabel.frame.height) / 2)

        // Position button on the right
        refreshButton.frame.origin = NSPoint(
            x: containerWidth - buttonWidth - rightPadding,
            y: (containerHeight - refreshButton.frame.height) / 2
        )

        containerView.addSubview(titleLabel)
        containerView.addSubview(refreshButton)

        let headerItem = NSMenuItem()
        headerItem.view = containerView
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

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
            let errorItem = NSMenuItem()
            let errorView = createErrorView(error: error)
            errorItem.view = errorView
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

                    // Add repository header with bold text
                    let prCount = repoPRs.count
                    let headerText = "\(repoName) (\(prCount) PR\(prCount == 1 ? "" : "s"))"

                    let headerAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                        .foregroundColor: NSColor.labelColor
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

    /// Custom clickable view for menu items that forwards clicks to the menu item's action.
    private class ClickablePRView: NSView {
        var onClick: (() -> Void)?
        var onCopy: (() -> Void)?
        private var trackingArea: NSTrackingArea?
        private var isHovered = false {
            didSet {
                needsDisplay = true
            }
        }
        private var showCopyFeedback = false {
            didSet {
                needsDisplay = true
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupTrackingArea()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupTrackingArea()
        }

        private func setupTrackingArea() {
            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea!)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let existingArea = trackingArea {
                removeTrackingArea(existingArea)
            }

            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea!)
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
        }

        override func mouseUp(with event: NSEvent) {
            let isCommandClick = event.modifierFlags.contains(.command)
            let reverseMode = AppSettings.shared.reverseClickBehavior

            // Determine action based on click type and reverse mode setting:
            // Normal mode: regular click = open, cmd-click = copy
            // Reverse mode: regular click = copy, cmd-click = open
            let shouldCopy = isCommandClick != reverseMode

            if shouldCopy {
                onCopy?()
                showCopyFeedback(animated: true)
            } else {
                onClick?()
            }

            // Close the menu after click
            self.enclosingMenuItem?.menu?.cancelTracking()
        }

        private func showCopyFeedback(animated: Bool) {
            guard animated else { return }

            showCopyFeedback = true

            // Reset after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.showCopyFeedback = false
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            if showCopyFeedback {
                // Show green flash for copy feedback
                NSColor.systemGreen.withAlphaComponent(0.3).setFill()
                bounds.fill()
            } else if isHovered {
                // Use a subtle highlight color for hover effect
                NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
                bounds.fill()
            }
        }
    }

    /// Creates a custom view for displaying a PR menu item with pills on the second line.
    ///
    /// - Parameters:
    ///   - pr: The pull request to create a view for
    ///   - includeRepoName: Whether to include the repository name in the title
    /// - Returns: A configured NSView ready to be used as menu item view
    private func createPRView(pr: PullRequest, includeRepoName: Bool) -> NSView {
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

        // Create status pill image with fixed width for alignment
        // Calculate width needed for "MERGED" (longest status text) to ensure consistent alignment
        let font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let longestStatusText = "MERGED"
        let statusMinWidth = (longestStatusText as NSString).size(withAttributes: [.font: font]).width
        let statusPillImage = createPillImage(text: statusText, backgroundColor: statusColor, textColor: .white, minWidth: statusMinWidth)

        // Create review decision pill if available
        var reviewPillImage: NSImage? = nil
        var reviewTooltip: String? = nil
        if let decision = ReviewDecision(apiValue: pr.reviewDecision) {
            let (reviewText, reviewColor): (String, NSColor)
            switch decision {
            case .approved:
                reviewText = "✓"
                reviewColor = githubGreen
                reviewTooltip = "Review Status: Approved"
            case .changesRequested:
                reviewText = "⚠"
                reviewColor = NSColor(red: 0xbf / 255.0, green: 0x8b / 255.0, blue: 0x00 / 255.0, alpha: 1.0)
                reviewTooltip = "Review Status: Changes Requested"
            case .reviewRequired:
                reviewText = "○"
                reviewColor = .systemGray
                reviewTooltip = "Review Status: Review Required"
            case .noReview:
                reviewText = "∅"
                reviewColor = .systemGray
                reviewTooltip = "Review Status: No Review Required"
            }
            reviewPillImage = createPillImage(text: reviewText, backgroundColor: reviewColor, textColor: .white)
        }

        // Build first line text
        let firstLineText: String
        if includeRepoName {
            firstLineText = "\(pr.repository.nameWithOwner) #\(pr.number): \(pr.title)"
        } else {
            firstLineText = "#\(pr.number): \(pr.title)"
        }

        // Build second line metadata
        var metadataParts: [String] = []
        metadataParts.append("opened \(pr.formattedAge())")
        metadataParts.append("by \(pr.author.login)")
        if !pr.assignees.isEmpty {
            metadataParts.append("\(pr.assignees.count) assignee\(pr.assignees.count == 1 ? "" : "s")")
        }
        if pr.commentsCount > 0 {
            metadataParts.append("\(pr.commentsCount) comment\(pr.commentsCount == 1 ? "" : "s")")
        }
        let metadataText = metadataParts.joined(separator: " • ")

        // Create container view with extra height for spacing
        let containerView = ClickablePRView(frame: NSRect(x: 0, y: 0, width: 500, height: 50))

        // Create first line label
        let firstLineLabel = NSTextField(labelWithString: firstLineText)
        firstLineLabel.isEditable = false
        firstLineLabel.isSelectable = false
        firstLineLabel.isBordered = false
        firstLineLabel.drawsBackground = false
        firstLineLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        firstLineLabel.textColor = .labelColor
        firstLineLabel.frame = NSRect(x: 12, y: 26, width: 476, height: 18)
        containerView.addSubview(firstLineLabel)

        // Create second line with pills and metadata
        var xOffset: CGFloat = 12

        // Add status pill
        let statusImageView = NSImageView(image: statusPillImage)
        statusImageView.frame = NSRect(x: xOffset, y: 8, width: statusPillImage.size.width, height: statusPillImage.size.height)
        containerView.addSubview(statusImageView)
        xOffset += statusPillImage.size.width + 4

        // Add review pill if available
        if let reviewImage = reviewPillImage {
            let reviewImageView = NSImageView(image: reviewImage)
            reviewImageView.frame = NSRect(x: xOffset, y: 8, width: reviewImage.size.width, height: reviewImage.size.height)

            // Add tooltip to the review pill
            if let tooltip = reviewTooltip {
                reviewImageView.toolTip = tooltip
            }

            containerView.addSubview(reviewImageView)
            xOffset += reviewImage.size.width + 4
        }

        // Add metadata label
        let metadataLabel = NSTextField(labelWithString: metadataText)
        metadataLabel.isEditable = false
        metadataLabel.isSelectable = false
        metadataLabel.isBordered = false
        metadataLabel.drawsBackground = false
        metadataLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.frame = NSRect(x: xOffset, y: 6, width: 476 - (xOffset - 12), height: 16)
        containerView.addSubview(metadataLabel)

        return containerView
    }

    /// Creates a menu item for a pull request with formatted title and metadata.
    ///
    /// - Parameters:
    ///   - pr: The pull request to create a menu item for
    ///   - includeRepoName: Whether to include the repository name in the title
    /// - Returns: A configured NSMenuItem ready to be added to the menu
    private func createPRMenuItem(pr: PullRequest, includeRepoName: Bool) -> NSMenuItem {
        let menuItem = NSMenuItem()
        let prView = createPRView(pr: pr, includeRepoName: includeRepoName)

        // Set up click handlers
        if let clickableView = prView as? ClickablePRView {
            clickableView.onClick = {
                guard let url = URL(string: pr.url) else { return }
                NSWorkspace.shared.open(url)
            }

            clickableView.onCopy = {
                guard let url = URL(string: pr.url) else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.absoluteString, forType: .string)
            }
        }

        menuItem.view = prView
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

    /// Custom view class for error display that allows buttons to receive mouse events
    private class ErrorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Let subviews (like buttons) receive their own mouse events
            for subview in subviews.reversed() {
                let convertedPoint = convert(point, to: subview)
                if let hitView = subview.hitTest(convertedPoint) {
                    return hitView
                }
            }
            return super.hitTest(point)
        }
    }

    /// Creates an error view with a copy icon for displaying error messages.
    ///
    /// - Parameter error: The error message to display
    /// - Returns: An NSView containing the error message and copy icon
    private func createErrorView(error: String) -> NSView {
        // Match PR item height for consistency (50px total)
        let containerView = ErrorView(frame: NSRect(x: 0, y: 0, width: 500, height: 50))

        // Error label with normal readable color - centered vertically
        let errorLabel = NSTextField(labelWithString: "Error: \(error)")
        errorLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        errorLabel.textColor = .labelColor
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.maximumNumberOfLines = 1
        errorLabel.frame = NSRect(x: 12, y: 16, width: 440, height: 18)
        containerView.addSubview(errorLabel)

        // Copy icon button - larger and more visible
        let copyButton = NSButton(frame: NSRect(x: 450, y: 11, width: 36, height: 28))
        copyButton.bezelStyle = .rounded
        copyButton.isBordered = true
        copyButton.title = ""

        // Create and configure the button image - using larger symbol configuration
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular, scale: .large)
        if let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy error message")?.withSymbolConfiguration(symbolConfig) {
            // Configure the image to be visible
            image.isTemplate = true
            copyButton.image = image
            copyButton.imagePosition = .imageOnly
        }

        copyButton.contentTintColor = .controlAccentColor
        copyButton.toolTip = "Copy error message to clipboard"
        copyButton.target = self
        copyButton.action = #selector(copyErrorToClipboard(_:))

        // Store the error message in the button's identifier
        copyButton.identifier = NSUserInterfaceItemIdentifier(error)

        containerView.addSubview(copyButton)

        return containerView
    }

    /// Copies the error message to the clipboard.
    @objc private func copyErrorToClipboard(_ sender: NSButton) {
        guard let error = sender.identifier?.rawValue else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(error, forType: .string)

        // Visual feedback: briefly change the icon
        if let originalImage = sender.image {
            sender.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
            sender.contentTintColor = githubGreen

            // Reset after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                sender.image = originalImage
                sender.contentTintColor = .secondaryLabelColor
            }
        }
    }

    /// Creates a rounded pill image for badge display (e.g., DRAFT indicator).
    ///
    /// - Parameters:
    ///   - text: The text to display in the pill
    ///   - backgroundColor: The background color of the pill
    ///   - textColor: The text color
    ///   - minWidth: Optional minimum width for the pill (excluding padding)
    /// - Returns: An NSImage of the rounded pill
    private func createPillImage(text: String, backgroundColor: NSColor, textColor: NSColor, minWidth: CGFloat? = nil) -> NSImage {
        let font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (text as NSString).size(withAttributes: attributes)

        // Add padding around text
        let padding: CGFloat = 4
        let height: CGFloat = textSize.height + padding

        // Use minimum width if specified, otherwise use text width
        let contentWidth = minWidth ?? textSize.width
        let width: CGFloat = max(contentWidth, textSize.width) + padding * 2
        let cornerRadius: CGFloat = height / 2

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        // Draw rounded rectangle background
        let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        path.fill()

        // Draw text centered horizontally and vertically
        let textX = (width - textSize.width) / 2
        let textY = padding / 2
        let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
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

}
