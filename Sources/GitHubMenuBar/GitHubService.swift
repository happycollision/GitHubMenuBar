import Foundation

/// Service layer for interacting with the GitHub CLI (`gh`).
///
/// This service uses the `gh` CLI tool via shell commands instead of direct API calls.
/// Benefits of this approach:
/// - No need to manage GitHub tokens (gh handles authentication)
/// - Users already familiar with gh CLI for their workflow
/// - Simpler implementation without API client dependencies
///
/// Thread safety: This class is marked as `Sendable` to be safely used from async contexts.
/// It's stateless (singleton pattern with no mutable state), making it inherently thread-safe.
final class GitHubService: Sendable {
    /// Shared singleton instance
    static let shared = GitHubService()

    private init() {}

    /// Checks if the GitHub CLI (`gh`) is installed on the system.
    ///
    /// - Throws: `AppError.ghNotInstalled` if gh is not found in PATH
    func checkGHInstalled() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gh"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw AppError.ghNotInstalled
        }
    }

    /// Checks if the user is authenticated with GitHub via gh CLI.
    ///
    /// - Throws: `AppError.ghNotAuthenticated` if not logged in
    func checkAuthentication() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw AppError.ghNotAuthenticated
        }
    }

    /// Fetches all pull requests where the current user has been requested as a reviewer.
    ///
    /// Uses `gh search prs --review-requested=@me` which:
    /// - Works from any directory (not tied to a specific repo)
    /// - Returns PRs across all accessible repositories
    /// - Currently limited to 50 results (can be adjusted)
    ///
    /// - Returns: Array of `PullRequest` objects sorted by GitHub's search algorithm
    /// - Throws: `AppError` if gh is not installed, not authenticated, command fails, or JSON parsing fails
    func fetchReviewRequests() async throws -> [PullRequest] {
        // First check if gh is installed and authenticated
        try await checkGHInstalled()
        try await checkAuthentication()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "gh", "search", "prs",
            "--review-requested=@me",
            "--json", "id,title,url,number,repository,author,createdAt,assignees,commentsCount,isDraft,state",
            "--limit", "50"  // Adjust this if you need more/fewer results
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AppError.commandFailed(errorMessage)
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            // Parse JSON using ISO 8601 date format (GitHub's standard)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let prs = try decoder.decode([PullRequest].self, from: data)

            return prs
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.decodingError(error.localizedDescription)
        }
    }
}
