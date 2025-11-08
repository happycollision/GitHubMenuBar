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

    /// Helper method to execute a GraphQL query
    private func executeQuery(searchQuery: String) async throws -> [PullRequest] {
        let graphqlQuery = """
        {
          search(query: "\(searchQuery)", type: ISSUE, first: 50) {
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
                    let edges: [Edge]
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
            return response.data.search.edges.compactMap { edge in
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
    /// - Returns: Array of `PullRequest` objects, deduplicated by ID
    /// - Throws: `AppError` if gh is not installed, not authenticated, command fails, or JSON parsing fails
    /// - Throws: `CancellationError` if the task is cancelled
    func fetchReviewRequests() async throws -> [PullRequest] {
        // First check if gh is installed and authenticated
        try await checkGHInstalled()
        try await checkAuthentication()

        // Check for cancellation before starting queries
        try Task.checkCancellation()

        let included = await AppSettings.shared.includedStatuses
        if included.isEmpty {
            return []
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

        // Strategy: Make separate queries for each status to avoid 50-PR limit issues
        // This ensures we get up to 50 PRs of each type instead of 50 total mixed PRs

        do {
            if hasDraft {
                // Query for all drafts
                let draftQuery = "type:pr review-requested:@me is:draft \(baseFilters)".trimmingCharacters(in: .whitespaces)
                let draftPRs = try await executeQuery(searchQuery: draftQuery)
                allPRs.append(contentsOf: draftPRs)
                print("DEBUG: Fetched \(draftPRs.count) draft PRs")

                // Check for cancellation between queries
                try Task.checkCancellation()
            }

            if hasOpen {
                // Query for non-draft open PRs
                let openQuery = "type:pr review-requested:@me is:open draft:false \(baseFilters)".trimmingCharacters(in: .whitespaces)
                let openPRs = try await executeQuery(searchQuery: openQuery)
                allPRs.append(contentsOf: openPRs)
                print("DEBUG: Fetched \(openPRs.count) open non-draft PRs")

                // Check for cancellation between queries
                try Task.checkCancellation()
            }

            if hasMerged || hasClosed {
                // Query for non-draft closed PRs (includes both merged and closed)
                let closedQuery = "type:pr review-requested:@me is:closed draft:false \(baseFilters)".trimmingCharacters(in: .whitespaces)
                let closedPRs = try await executeQuery(searchQuery: closedQuery)

                // Filter to only include merged or closed as requested
                let filtered = closedPRs.filter { pr in
                    let state = pr.state.uppercased()
                    return (state == "MERGED" && hasMerged) || (state == "CLOSED" && hasClosed)
                }
                allPRs.append(contentsOf: filtered)
                print("DEBUG: Fetched \(closedPRs.count) closed PRs, kept \(filtered.count) after filtering")

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

            print("DEBUG: Total PRs after deduplication, review filtering, and sorting: \(sorted.count), limited to: \(limited.count)")
            return limited
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
