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
