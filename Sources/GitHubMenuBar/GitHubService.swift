import Foundation
import os

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

    /// Logger for GitHubService operations
    private let logger = Logger(subsystem: "com.githubmenubar.app", category: "GitHubService")

    /// Static logger for initialization-time operations
    private static let initLogger = Logger(subsystem: "com.githubmenubar.app", category: "GitHubService.init")

    /// Cached shell environment loaded once at initialization
    /// This avoids the performance overhead of spawning a shell multiple times
    private let cachedEnvironment: [String: String]

    private init() {
        // Load shell environment once at initialization
        self.cachedEnvironment = Self.loadShellEnvironment()
    }

    /// Loads the user's shell environment to get the correct PATH.
    /// This is necessary because macOS GUI apps don't inherit the user's shell PATH by default.
    ///
    /// - Returns: Dictionary of environment variables from the user's shell
    private static func loadShellEnvironment() -> [String: String] {
        // Get the user's actual shell (e.g., /bin/bash, /bin/zsh, /usr/local/bin/fish)
        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        initLogger.debug("Loading shell environment from: \(userShell)")
        initLogger.debug("Current PATH before loading: \(ProcessInfo.processInfo.environment["PATH"] ?? "none")")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: userShell)

        // Run an interactive login shell to source all profile files, then print the environment
        // -i: interactive (sources rc files like .zshrc)
        // -l: login (sources profile files like .zprofile)
        // -c: command to execute
        process.arguments = ["-i", "-l", "-c", "env"]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "unknown error"
                initLogger.error("Shell loading failed with status \(process.terminationStatus): \(errorMessage)")
                // Fallback to process environment if shell loading fails
                return ProcessInfo.processInfo.environment
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                initLogger.error("Failed to decode shell output")
                return ProcessInfo.processInfo.environment
            }

            // Parse the env output into a dictionary
            var environment = ProcessInfo.processInfo.environment
            for line in output.components(separatedBy: .newlines) {
                guard let separatorIndex = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<separatorIndex])
                let value = String(line[line.index(after: separatorIndex)...])
                environment[key] = value
            }

            initLogger.debug("Loaded PATH from shell: \(environment["PATH"] ?? "none")")
            return environment
        } catch {
            initLogger.error("Exception loading shell environment: \(error)")
            // Fallback to process environment if anything fails
            return ProcessInfo.processInfo.environment
        }
    }

    /// Checks if the GitHub CLI (`gh`) is installed on the system.
    ///
    /// - Throws: `AppError.ghNotInstalled` if gh is not found in PATH
    func checkGHInstalled() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gh"]
        process.environment = cachedEnvironment

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
        process.environment = cachedEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw AppError.ghNotAuthenticated
        }
    }

    /// Result of a query including PRs and pagination info
    struct QueryResult {
        let pullRequests: [PullRequest]
        let hasMore: Bool
    }

    /// Helper method to execute a GraphQL query
    private func executeQuery(searchQuery: String) async throws -> QueryResult {
        let graphqlQuery = """
        {
          search(query: "\(searchQuery)", type: ISSUE, first: 50) {
            pageInfo {
              hasNextPage
            }
            edges {
              node {
                ... on PullRequest {
                  id
                  number
                  title
                  url
                  state
                  isDraft
                  reviewDecision
                  createdAt
                  repository {
                    nameWithOwner
                  }
                  author {
                    login
                  }
                  assignees(first: 10) {
                    nodes {
                      login
                    }
                  }
                  comments {
                    totalCount
                  }
                }
              }
            }
          }
        }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "api", "graphql", "-f", "query=\(graphqlQuery)"]
        process.environment = cachedEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Check for cancellation before waiting
        try Task.checkCancellation()

        // Use withTaskCancellationHandler to terminate the process if task is cancelled
        return try await withTaskCancellationHandler {
            // Wait for process to complete
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }

            // Check again after process completes
            try Task.checkCancellation()

            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AppError.commandFailed(errorMessage)
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            // Parse GraphQL response
            struct GraphQLResponse: Codable {
                let data: SearchData

                struct SearchData: Codable {
                    let search: SearchResults
                }

                struct SearchResults: Codable {
                    let pageInfo: PageInfo
                    let edges: [Edge]
                }

                struct PageInfo: Codable {
                    let hasNextPage: Bool
                }

                struct Edge: Codable {
                    let node: Node
                }

                struct Node: Codable {
                    let id: String
                    let number: Int
                    let title: String
                    let url: String
                    let state: String
                    let isDraft: Bool
                    let reviewDecision: String?
                    let createdAt: String
                    let repository: Repository
                    let author: Author
                    let assignees: Assignees
                    let comments: Comments

                    struct Repository: Codable {
                        let nameWithOwner: String
                    }

                    struct Author: Codable {
                        let login: String
                    }

                    struct Assignees: Codable {
                        let nodes: [Assignee]
                    }

                    struct Assignee: Codable {
                        let login: String
                    }

                    struct Comments: Codable {
                        let totalCount: Int
                    }
                }
            }

            let decoder = JSONDecoder()
            let response = try decoder.decode(GraphQLResponse.self, from: data)

            // Convert GraphQL response to PullRequest models
            let dateFormatter = ISO8601DateFormatter()
            let pullRequests: [PullRequest] = response.data.search.edges.compactMap { edge in
                guard let createdAt = dateFormatter.date(from: edge.node.createdAt) else {
                    return nil
                }

                return PullRequest(
                    id: edge.node.id,
                    title: edge.node.title,
                    url: edge.node.url,
                    number: edge.node.number,
                    repository: PullRequest.Repository(nameWithOwner: edge.node.repository.nameWithOwner),
                    author: PullRequest.Author(login: edge.node.author.login),
                    createdAt: createdAt,
                    assignees: edge.node.assignees.nodes.map { PullRequest.Assignee(login: $0.login) },
                    commentsCount: edge.node.comments.totalCount,
                    isDraft: edge.node.isDraft,
                    state: edge.node.state,
                    reviewDecision: edge.node.reviewDecision
                )
            }

            return QueryResult(
                pullRequests: pullRequests,
                hasMore: response.data.search.pageInfo.hasNextPage
            )
        } onCancel: {
            // Terminate the process if the task is cancelled
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Fetches all pull requests where the current user has been requested as a reviewer.
    ///
    /// Uses GraphQL API via `gh api graphql` with a multi-query strategy:
    /// - Makes separate queries for each status (draft, open, closed) to avoid 50-PR limit issues
    /// - This ensures we get up to 50 PRs of each type instead of 50 total mixed PRs
    ///
    /// - Returns: A tuple containing an array of `PullRequest` objects and a `hasMore` flag
    /// - Throws: `AppError` if gh is not installed, not authenticated, command fails, or JSON parsing fails
    /// - Throws: `CancellationError` if the task is cancelled
    func fetchReviewRequests() async throws -> (pullRequests: [PullRequest], hasMore: Bool) {
        // First check if gh is installed and authenticated
        try await checkGHInstalled()
        try await checkAuthentication()

        // Check for cancellation before starting queries
        try Task.checkCancellation()

        let included = await AppSettings.shared.includedStatuses
        if included.isEmpty {
            return (pullRequests: [], hasMore: false)
        }

        // Build filter strings for GraphQL query
        var filterParts: [String] = []

        // Add repository filters
        if let repoFilter = await AppSettings.shared.activeRepositoryFilter,
           let isWhitelist = await AppSettings.shared.isRepositoryWhitelist {
            if isWhitelist {
                // Whitelist: use multiple repo: terms (OR logic)
                for repo in repoFilter {
                    filterParts.append("repo:\(repo)")
                }
            } else {
                // Blacklist: use negative repo: terms (AND logic)
                for repo in repoFilter {
                    filterParts.append("-repo:\(repo)")
                }
            }
        }

        // Add author filters
        if let authorFilter = await AppSettings.shared.activeAuthorFilter,
           let isWhitelist = await AppSettings.shared.isAuthorWhitelist {
            if isWhitelist {
                // Whitelist: use multiple author: terms (OR logic)
                for author in authorFilter {
                    filterParts.append("author:\(author)")
                }
            } else {
                // Blacklist: use negative author: terms (AND logic)
                for author in authorFilter {
                    filterParts.append("-author:\(author)")
                }
            }
        }

        let baseFilters = filterParts.joined(separator: " ")

        let hasOpen = included.contains(.open)
        let hasDraft = included.contains(.draft)
        let hasMerged = included.contains(.merged)
        let hasClosed = included.contains(.closed)

        var allPRs: [PullRequest] = []
        var anyHasMore = false

        // Strategy: Make separate queries for each status to avoid 50-PR limit issues
        // This ensures we get up to 50 PRs of each type instead of 50 total mixed PRs

        do {
            if hasDraft {
                // Query for all drafts
                let draftQuery = "type:pr review-requested:@me is:draft \(baseFilters)".trimmingCharacters(in: .whitespaces)
                let result = try await executeQuery(searchQuery: draftQuery)
                allPRs.append(contentsOf: result.pullRequests)
                anyHasMore = anyHasMore || result.hasMore
                logger.debug("Fetched \(result.pullRequests.count) draft PRs, hasMore: \(result.hasMore)")

                // Check for cancellation between queries
                try Task.checkCancellation()
            }

            if hasOpen {
                // Query for non-draft open PRs
                let openQuery = "type:pr review-requested:@me is:open draft:false \(baseFilters)".trimmingCharacters(in: .whitespaces)
                let result = try await executeQuery(searchQuery: openQuery)
                allPRs.append(contentsOf: result.pullRequests)
                anyHasMore = anyHasMore || result.hasMore
                logger.debug("Fetched \(result.pullRequests.count) open non-draft PRs, hasMore: \(result.hasMore)")

                // Check for cancellation between queries
                try Task.checkCancellation()
            }

            if hasMerged {
                // Query for merged PRs only
                let mergedQuery = "type:pr review-requested:@me is:merged \(baseFilters)".trimmingCharacters(in: .whitespaces)
                let result = try await executeQuery(searchQuery: mergedQuery)
                allPRs.append(contentsOf: result.pullRequests)
                anyHasMore = anyHasMore || result.hasMore
                logger.debug("Fetched \(result.pullRequests.count) merged PRs, hasMore: \(result.hasMore)")

                // Check for cancellation between queries
                try Task.checkCancellation()
            }

            if hasClosed {
                // Query for closed but not merged PRs
                let closedQuery = "type:pr review-requested:@me is:closed is:unmerged \(baseFilters)".trimmingCharacters(in: .whitespaces)
                let result = try await executeQuery(searchQuery: closedQuery)
                allPRs.append(contentsOf: result.pullRequests)
                anyHasMore = anyHasMore || result.hasMore
                logger.debug("Fetched \(result.pullRequests.count) closed (unmerged) PRs, hasMore: \(result.hasMore)")

                // Check for cancellation after final query
                try Task.checkCancellation()
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

            // Filter by review decision
            let includedDecisions = await AppSettings.shared.includedReviewDecisions
            let filteredByReview = deduplicated.filter { pr in
                guard let decision = ReviewDecision(apiValue: pr.reviewDecision) else {
                    return true  // Include PRs with unknown review decision
                }
                return includedDecisions.contains(decision)
            }

            // Sort by creation date (newest first) to maintain chronological order
            // across all PR states (draft, open, closed, merged)
            let sorted = filteredByReview.sorted { $0.createdAt > $1.createdAt }

            // Limit to 50 PRs to avoid overwhelming the UI
            // Since we make multiple API calls (one per status), we could get more than 50 total
            let limited = Array(sorted.prefix(50))

            // If we had more than 50 PRs after filtering, or any query had more results available,
            // indicate that there are more PRs not being shown
            let hasMoreResults = anyHasMore || sorted.count > 50

            logger.debug("Total PRs after deduplication, review filtering, and sorting: \(sorted.count), limited to: \(limited.count), hasMore: \(hasMoreResults)")
            return (pullRequests: limited, hasMore: hasMoreResults)
        } catch is CancellationError {
            // Propagate cancellation error up
            throw CancellationError()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.decodingError(error.localizedDescription)
        }
    }
}
