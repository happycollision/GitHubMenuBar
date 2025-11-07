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

    /// Helper method to execute a single gh search query
    private func executeQuery(arguments: [String]) async throws -> [PullRequest] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var finalArgs = arguments
        finalArgs.append(contentsOf: [
            "--json", "id,title,url,number,repository,author,createdAt,assignees,commentsCount,isDraft,state",
            "--limit", "50"
        ])
        process.arguments = finalArgs

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AppError.commandFailed(errorMessage)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PullRequest].self, from: data)
    }

    /// Fetches all pull requests where the current user has been requested as a reviewer.
    ///
    /// Uses `gh search prs --review-requested=@me` with a multi-query strategy:
    /// - When draft is included with other statuses, makes separate queries and merges results
    /// - This avoids the 50-PR limit hiding results when most PRs are in one category
    ///
    /// - Returns: Array of `PullRequest` objects, deduplicated by ID
    /// - Throws: `AppError` if gh is not installed, not authenticated, command fails, or JSON parsing fails
    func fetchReviewRequests() async throws -> [PullRequest] {
        // First check if gh is installed and authenticated
        try await checkGHInstalled()
        try await checkAuthentication()

        let included = await AppSettings.shared.includedStatuses
        if included.isEmpty {
            return []
        }

        let hasOpen = included.contains(.open)
        let hasDraft = included.contains(.draft)
        let hasMerged = included.contains(.merged)
        let hasClosed = included.contains(.closed)

        var allPRs: [PullRequest] = []

        // Strategy: Make separate queries for each status to avoid 50-PR limit issues
        // This ensures we get up to 50 PRs of each type instead of 50 total mixed PRs

        do {
            if hasDraft {
                // Query for all drafts
                let draftArgs = ["gh", "search", "prs", "--review-requested=@me", "--draft"]
                let draftPRs = try await executeQuery(arguments: draftArgs)
                allPRs.append(contentsOf: draftPRs)
                print("DEBUG: Fetched \(draftPRs.count) draft PRs")
            }

            if hasOpen {
                // Query for non-draft open PRs
                let openArgs = ["gh", "search", "prs", "--review-requested=@me", "--state=open", "--draft=false"]
                let openPRs = try await executeQuery(arguments: openArgs)
                allPRs.append(contentsOf: openPRs)
                print("DEBUG: Fetched \(openPRs.count) open non-draft PRs")
            }

            if hasMerged || hasClosed {
                // Query for non-draft closed PRs (includes both merged and closed)
                let closedArgs = ["gh", "search", "prs", "--review-requested=@me", "--state=closed", "--draft=false"]
                let closedPRs = try await executeQuery(arguments: closedArgs)

                // Filter to only include merged or closed as requested
                let filtered = closedPRs.filter { pr in
                    let state = pr.state.lowercased()
                    return (state == "merged" && hasMerged) || (state == "closed" && hasClosed)
                }
                allPRs.append(contentsOf: filtered)
                print("DEBUG: Fetched \(closedPRs.count) closed PRs, kept \(filtered.count) after filtering")
            }

            // Deduplicate by ID (in case a PR appears in multiple queries)
            var seenIDs = Set<String>()
            let deduplicated = allPRs.filter { pr in
                if seenIDs.contains(pr.id) {
                    return false
                }
                seenIDs.insert(pr.id)
                return true
            }

            print("DEBUG: Total PRs after deduplication: \(deduplicated.count)")
            return deduplicated
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.decodingError(error.localizedDescription)
        }
    }
}
