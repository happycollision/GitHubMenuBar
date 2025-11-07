import Foundation

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
