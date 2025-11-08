import Foundation

/// Enum representing the possible PR statuses that can be filtered.
enum PRStatus: String, CaseIterable {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"
    case draft = "DRAFT"

    /// Display name for the status
    var displayName: String {
        rawValue.capitalized
    }
}

/// Enum representing the filter mode (whitelist or blacklist).
enum FilterMode: String, Codable {
    case whitelist = "whitelist"
    case blacklist = "blacklist"

    /// Display name for the mode
    var displayName: String {
        switch self {
        case .whitelist:
            return "Whitelist (Include Only)"
        case .blacklist:
            return "Blacklist (Exclude)"
        }
    }
}

/// Settings manager for user preferences using UserDefaults.
///
/// This class manages persistent settings for the application, including which
/// PR statuses to exclude from the menu display.
///
/// Thread safety: This class is marked as Sendable and uses @MainActor for
/// the notification mechanism to ensure thread-safe access.
@MainActor
class AppSettings: ObservableObject {
    /// Shared singleton instance
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let excludedStatusesKey = "excludedPRStatuses"
    private let refreshIntervalKey = "refreshIntervalMinutes"
    private let groupByRepoKey = "groupByRepo"

    // Filter keys
    private let repoFilterEnabledKey = "repoFilterEnabled"
    private let repoFilterModeKey = "repoFilterMode"
    private let whitelistedRepositoriesKey = "whitelistedRepositories"
    private let blacklistedRepositoriesKey = "blacklistedRepositories"
    private let authorFilterEnabledKey = "authorFilterEnabled"
    private let authorFilterModeKey = "authorFilterMode"
    private let whitelistedAuthorsKey = "whitelistedAuthors"
    private let blacklistedAuthorsKey = "blacklistedAuthors"

    /// Notification posted when settings change
    static let didChangeNotification = Notification.Name("AppSettingsDidChange")

    private init() {
        // Initialize defaults if not set
        if defaults.array(forKey: excludedStatusesKey) == nil {
            // Default to excluding MERGED and CLOSED
            defaults.set([PRStatus.merged.rawValue, PRStatus.closed.rawValue], forKey: excludedStatusesKey)
        }

        // Initialize refresh interval if not set (default to 5 minutes)
        if defaults.object(forKey: refreshIntervalKey) == nil {
            defaults.set(5, forKey: refreshIntervalKey)
        }

        // Initialize group by repo if not set (default to true)
        if defaults.object(forKey: groupByRepoKey) == nil {
            defaults.set(true, forKey: groupByRepoKey)
        }

        // Initialize filter settings if not set
        if defaults.object(forKey: repoFilterEnabledKey) == nil {
            defaults.set(false, forKey: repoFilterEnabledKey)
        }

        if defaults.object(forKey: repoFilterModeKey) == nil {
            defaults.set(FilterMode.blacklist.rawValue, forKey: repoFilterModeKey)
        }

        if defaults.object(forKey: authorFilterEnabledKey) == nil {
            defaults.set(true, forKey: authorFilterEnabledKey)
        }

        if defaults.object(forKey: authorFilterModeKey) == nil {
            defaults.set(FilterMode.blacklist.rawValue, forKey: authorFilterModeKey)
        }

        // Initialize blacklisted authors with dependabot by default
        if defaults.array(forKey: blacklistedAuthorsKey) == nil {
            defaults.set(["dependabot", "dependabot[bot]"], forKey: blacklistedAuthorsKey)
        }
    }

    /// Get the set of excluded PR statuses.
    ///
    /// - Returns: Set of PRStatus values that should be excluded from display
    var excludedStatuses: Set<PRStatus> {
        get {
            let rawValues = defaults.stringArray(forKey: excludedStatusesKey) ?? []
            return Set(rawValues.compactMap { PRStatus(rawValue: $0) })
        }
        set {
            let rawValues = newValue.map { $0.rawValue }
            defaults.set(rawValues, forKey: excludedStatusesKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Check if a specific status is excluded.
    ///
    /// - Parameter status: The status to check
    /// - Returns: True if the status is excluded, false otherwise
    func isExcluded(_ status: PRStatus) -> Bool {
        return excludedStatuses.contains(status)
    }

    /// Toggle the exclusion state of a specific status.
    ///
    /// - Parameter status: The status to toggle
    func toggleExclusion(for status: PRStatus) {
        var excluded = excludedStatuses
        if excluded.contains(status) {
            excluded.remove(status)
        } else {
            excluded.insert(status)
        }
        excludedStatuses = excluded
    }

    /// Get the set of included (non-excluded) PR statuses.
    ///
    /// - Returns: Set of PRStatus values that should be included in queries
    var includedStatuses: Set<PRStatus> {
        let allStatuses = Set(PRStatus.allCases)
        return allStatuses.subtracting(excludedStatuses)
    }

    /// Get or set the refresh interval in minutes.
    ///
    /// The interval determines how often the app polls GitHub for updates.
    /// Valid range is 1-60 minutes. Values outside this range will be clamped.
    ///
    /// - Returns: The current refresh interval in minutes (default: 5)
    var refreshIntervalMinutes: Int {
        get {
            let interval = defaults.integer(forKey: refreshIntervalKey)
            // Ensure we always return a valid value (default to 5 if 0)
            return interval > 0 ? interval : 5
        }
        set {
            // Clamp the value between 1 and 60 minutes
            let clampedValue = max(1, min(60, newValue))
            defaults.set(clampedValue, forKey: refreshIntervalKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get the refresh interval in seconds (for use with Timer).
    ///
    /// - Returns: The refresh interval in seconds
    var refreshIntervalSeconds: TimeInterval {
        return TimeInterval(refreshIntervalMinutes * 60)
    }

    /// Get or set whether PRs should be grouped by repository.
    ///
    /// When enabled, PRs in the menu will be organized by repository with headers
    /// showing the repository name and PR count. When disabled, PRs are shown in a
    /// flat list sorted by creation date.
    ///
    /// - Returns: True if grouping is enabled (default: true), false otherwise
    var groupByRepo: Bool {
        get {
            return defaults.bool(forKey: groupByRepoKey)
        }
        set {
            defaults.set(newValue, forKey: groupByRepoKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    // MARK: - Repository Filtering

    /// Get or set whether repository filtering is enabled.
    var repoFilterEnabled: Bool {
        get {
            return defaults.bool(forKey: repoFilterEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: repoFilterEnabledKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get or set the repository filter mode (whitelist or blacklist).
    var repoFilterMode: FilterMode {
        get {
            let rawValue = defaults.string(forKey: repoFilterModeKey) ?? FilterMode.blacklist.rawValue
            return FilterMode(rawValue: rawValue) ?? .blacklist
        }
        set {
            defaults.set(newValue.rawValue, forKey: repoFilterModeKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get or set the set of whitelisted repositories.
    var whitelistedRepositories: Set<String> {
        get {
            let array = defaults.stringArray(forKey: whitelistedRepositoriesKey) ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: whitelistedRepositoriesKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get or set the set of blacklisted repositories.
    var blacklistedRepositories: Set<String> {
        get {
            let array = defaults.stringArray(forKey: blacklistedRepositoriesKey) ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: blacklistedRepositoriesKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get the active repository filter based on enabled state and mode.
    ///
    /// - Returns: The set of repositories to filter, or nil if filtering is disabled
    var activeRepositoryFilter: Set<String>? {
        guard repoFilterEnabled else { return nil }
        return repoFilterMode == .whitelist ? whitelistedRepositories : blacklistedRepositories
    }

    /// Get the repository filter type (include or exclude).
    ///
    /// - Returns: True for whitelist (include only), false for blacklist (exclude), nil if disabled
    var isRepositoryWhitelist: Bool? {
        guard repoFilterEnabled else { return nil }
        return repoFilterMode == .whitelist
    }

    // MARK: - Author Filtering

    /// Get or set whether author filtering is enabled.
    var authorFilterEnabled: Bool {
        get {
            return defaults.bool(forKey: authorFilterEnabledKey)
        }
        set {
            defaults.set(newValue, forKey: authorFilterEnabledKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get or set the author filter mode (whitelist or blacklist).
    var authorFilterMode: FilterMode {
        get {
            let rawValue = defaults.string(forKey: authorFilterModeKey) ?? FilterMode.blacklist.rawValue
            return FilterMode(rawValue: rawValue) ?? .blacklist
        }
        set {
            defaults.set(newValue.rawValue, forKey: authorFilterModeKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get or set the set of whitelisted authors.
    var whitelistedAuthors: Set<String> {
        get {
            let array = defaults.stringArray(forKey: whitelistedAuthorsKey) ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: whitelistedAuthorsKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get or set the set of blacklisted authors.
    var blacklistedAuthors: Set<String> {
        get {
            let array = defaults.stringArray(forKey: blacklistedAuthorsKey) ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: blacklistedAuthorsKey)
            NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
        }
    }

    /// Get the active author filter based on enabled state and mode.
    ///
    /// - Returns: The set of authors to filter, or nil if filtering is disabled
    var activeAuthorFilter: Set<String>? {
        guard authorFilterEnabled else { return nil }
        return authorFilterMode == .whitelist ? whitelistedAuthors : blacklistedAuthors
    }

    /// Get the author filter type (include or exclude).
    ///
    /// - Returns: True for whitelist (include only), false for blacklist (exclude), nil if disabled
    var isAuthorWhitelist: Bool? {
        guard authorFilterEnabled else { return nil }
        return authorFilterMode == .whitelist
    }

    // MARK: - Helper Methods for Repository Filtering

    /// Add a repository to the whitelist.
    func addWhitelistedRepo(_ repo: String) {
        var repos = whitelistedRepositories
        repos.insert(repo)
        whitelistedRepositories = repos
    }

    /// Remove a repository from the whitelist.
    func removeWhitelistedRepo(_ repo: String) {
        var repos = whitelistedRepositories
        repos.remove(repo)
        whitelistedRepositories = repos
    }

    /// Add a repository to the blacklist.
    func addBlacklistedRepo(_ repo: String) {
        var repos = blacklistedRepositories
        repos.insert(repo)
        blacklistedRepositories = repos
    }

    /// Remove a repository from the blacklist.
    func removeBlacklistedRepo(_ repo: String) {
        var repos = blacklistedRepositories
        repos.remove(repo)
        blacklistedRepositories = repos
    }

    // MARK: - Helper Methods for Author Filtering

    /// Add an author to the whitelist.
    func addWhitelistedAuthor(_ author: String) {
        var authors = whitelistedAuthors
        authors.insert(author)
        whitelistedAuthors = authors
    }

    /// Remove an author from the whitelist.
    func removeWhitelistedAuthor(_ author: String) {
        var authors = whitelistedAuthors
        authors.remove(author)
        whitelistedAuthors = authors
    }

    /// Add an author to the blacklist.
    func addBlacklistedAuthor(_ author: String) {
        var authors = blacklistedAuthors
        authors.insert(author)
        blacklistedAuthors = authors
    }

    /// Remove an author from the blacklist.
    func removeBlacklistedAuthor(_ author: String) {
        var authors = blacklistedAuthors
        authors.remove(author)
        blacklistedAuthors = authors
    }
}

/// Data model for a GitHub pull request.
///
/// This model matches the JSON output from `gh search prs --json ...` command.
/// Fields are chosen to provide enough information for the menu display and
/// linking to the PR in the browser.
///
/// Note: We use `gh search prs` instead of `gh pr list` because the search
/// command works globally (from any directory), while `pr list` requires being
/// in a git repository.
struct PullRequest: Codable, Identifiable {
    /// Unique identifier for the PR (used by SwiftUI's Identifiable)
    let id: String

    /// PR title
    let title: String

    /// Full URL to the PR on GitHub
    let url: String

    /// PR number within the repository
    let number: Int

    /// Repository information
    let repository: Repository

    /// Author information
    let author: Author

    /// When the PR was created
    let createdAt: Date

    /// List of users assigned to this PR
    let assignees: [Assignee]

    /// Number of comments on this PR
    let commentsCount: Int

    /// Whether this PR is a draft
    let isDraft: Bool

    /// The state of the PR (OPEN, CLOSED, MERGED)
    let state: String

    /// Repository information from GitHub.
    ///
    /// Note: Only includes nameWithOwner (e.g., "TrilliantHealth/engineering-frontend")
    /// which is sufficient for display purposes.
    struct Repository: Codable {
        /// Full repository name including owner (e.g., "owner/repo")
        let nameWithOwner: String
    }

    /// Author information from GitHub.
    struct Author: Codable {
        /// GitHub username
        let login: String
    }

    /// Assignee information from GitHub.
    struct Assignee: Codable {
        /// GitHub username
        let login: String
    }

    /// Formats the PR age as a human-readable string (e.g., "2 days ago", "3 hours ago").
    ///
    /// - Returns: A string describing how long ago the PR was created
    func formattedAge() -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: createdAt,
            to: now
        )

        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        } else if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        } else if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "just now"
        }
    }
}

/// Application-specific errors.
///
/// These errors cover the main failure modes: missing/misconfigured gh CLI,
/// command execution failures, and JSON parsing errors.
enum AppError: Error, LocalizedError {
    /// GitHub CLI is not installed on the system
    case ghNotInstalled

    /// GitHub CLI is installed but not authenticated
    case ghNotAuthenticated

    /// A gh command failed with an error message
    case commandFailed(String)

    /// Failed to decode JSON response from gh
    case decodingError(String)

    /// User-friendly error descriptions for display in the menu
    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com"
        case .ghNotAuthenticated:
            return "Not authenticated with GitHub. Run 'gh auth login' in Terminal."
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .decodingError(let message):
            return "Failed to parse data: \(message)"
        }
    }
}
