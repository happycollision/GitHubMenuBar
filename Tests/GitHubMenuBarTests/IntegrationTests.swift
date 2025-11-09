import XCTest
@testable import GitHubMenuBar

/// Integration tests that exercise multiple components together
///
/// These tests verify that components work correctly when integrated,
/// including realistic data flows through the application.
@MainActor
final class IntegrationTests: XCTestCase {

    var settings: AppSettings!

    override func setUp() async throws {
        settings = AppSettings.shared
        // Reset to clean state
        settings.excludedStatuses = []
        settings.excludedReviewDecisions = []
        settings.repoFilterEnabled = false
        settings.authorFilterEnabled = false
    }

    // MARK: - PR Filtering Integration Tests

    func testPRFilteringWithMultipleStatuses() {
        // Create test PRs in different states
        let openPR = createTestPR(id: "1", state: "OPEN", isDraft: false)
        let draftPR = createTestPR(id: "2", state: "OPEN", isDraft: true)
        let mergedPR = createTestPR(id: "3", state: "MERGED", isDraft: false)
        let closedPR = createTestPR(id: "4", state: "CLOSED", isDraft: false)

        let allPRs = [openPR, draftPR, mergedPR, closedPR]

        // Test 1: Exclude merged and closed (default)
        settings.excludedStatuses = [.merged, .closed]
        let filtered1 = filterPRsByStatus(allPRs)
        XCTAssertEqual(filtered1.count, 2)
        XCTAssertTrue(filtered1.contains { $0.id == "1" })
        XCTAssertTrue(filtered1.contains { $0.id == "2" })

        // Test 2: Exclude only drafts
        settings.excludedStatuses = [.draft]
        let filtered2 = filterPRsByStatus(allPRs)
        XCTAssertEqual(filtered2.count, 3)
        XCTAssertFalse(filtered2.contains { $0.id == "2" })

        // Test 3: Include everything
        settings.excludedStatuses = []
        let filtered3 = filterPRsByStatus(allPRs)
        XCTAssertEqual(filtered3.count, 4)
    }

    func testPRFilteringWithReviewDecisions() {
        let approvedPR = createTestPR(id: "1", reviewDecision: "APPROVED")
        let changesRequestedPR = createTestPR(id: "2", reviewDecision: "CHANGES_REQUESTED")
        let reviewRequiredPR = createTestPR(id: "3", reviewDecision: "REVIEW_REQUIRED")
        let noReviewPR = createTestPR(id: "4", reviewDecision: nil)

        let allPRs = [approvedPR, changesRequestedPR, reviewRequiredPR, noReviewPR]

        // Exclude approved PRs
        settings.excludedReviewDecisions = [.approved]
        let filtered = filterPRsByReviewDecision(allPRs)
        XCTAssertEqual(filtered.count, 3)
        XCTAssertFalse(filtered.contains { $0.id == "1" })
    }

    func testRepositoryWhitelistFiltering() {
        let repo1PR = createTestPR(id: "1", repo: "owner/repo1")
        let repo2PR = createTestPR(id: "2", repo: "owner/repo2")
        let repo3PR = createTestPR(id: "3", repo: "owner/repo3")

        let allPRs = [repo1PR, repo2PR, repo3PR]

        // Enable whitelist for repo1 and repo2
        settings.repoFilterEnabled = true
        settings.repoFilterMode = .whitelist
        settings.whitelistedRepositories = ["owner/repo1", "owner/repo2"]

        let filtered = filterPRsByRepository(allPRs)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == "1" })
        XCTAssertTrue(filtered.contains { $0.id == "2" })
        XCTAssertFalse(filtered.contains { $0.id == "3" })
    }

    func testRepositoryBlacklistFiltering() {
        let repo1PR = createTestPR(id: "1", repo: "owner/repo1")
        let repo2PR = createTestPR(id: "2", repo: "owner/repo2")
        let repo3PR = createTestPR(id: "3", repo: "owner/repo3")

        let allPRs = [repo1PR, repo2PR, repo3PR]

        // Enable blacklist for repo3
        settings.repoFilterEnabled = true
        settings.repoFilterMode = .blacklist
        settings.blacklistedRepositories = ["owner/repo3"]

        let filtered = filterPRsByRepository(allPRs)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == "1" })
        XCTAssertTrue(filtered.contains { $0.id == "2" })
        XCTAssertFalse(filtered.contains { $0.id == "3" })
    }

    func testAuthorWhitelistFiltering() {
        let alicePR = createTestPR(id: "1", author: "alice")
        let bobPR = createTestPR(id: "2", author: "bob")
        let charliePR = createTestPR(id: "3", author: "charlie")

        let allPRs = [alicePR, bobPR, charliePR]

        // Enable whitelist for alice and bob
        settings.authorFilterEnabled = true
        settings.authorFilterMode = .whitelist
        settings.whitelistedAuthors = ["alice", "bob"]

        let filtered = filterPRsByAuthor(allPRs)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == "1" })
        XCTAssertTrue(filtered.contains { $0.id == "2" })
        XCTAssertFalse(filtered.contains { $0.id == "3" })
    }

    func testAuthorBlacklistFiltering() {
        let alicePR = createTestPR(id: "1", author: "alice")
        let dependabotPR = createTestPR(id: "2", author: "dependabot[bot]")
        let bobPR = createTestPR(id: "3", author: "bob")

        let allPRs = [alicePR, dependabotPR, bobPR]

        // Enable blacklist for dependabot
        settings.authorFilterEnabled = true
        settings.authorFilterMode = .blacklist
        settings.blacklistedAuthors = ["dependabot[bot]"]

        let filtered = filterPRsByAuthor(allPRs)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == "1" })
        XCTAssertFalse(filtered.contains { $0.id == "2" })
        XCTAssertTrue(filtered.contains { $0.id == "3" })
    }

    func testCombinedFiltering() {
        // Create diverse set of PRs
        let prs = [
            createTestPR(id: "1", state: "OPEN", repo: "owner/repo1", author: "alice", reviewDecision: "APPROVED"),
            createTestPR(id: "2", state: "OPEN", repo: "owner/repo2", author: "bob", reviewDecision: "CHANGES_REQUESTED"),
            createTestPR(id: "3", state: "MERGED", repo: "owner/repo1", author: "alice", reviewDecision: "APPROVED"),
            createTestPR(id: "4", state: "OPEN", repo: "owner/repo3", author: "dependabot[bot]", reviewDecision: nil),
            createTestPR(id: "5", isDraft: true, repo: "owner/repo1", author: "charlie", reviewDecision: nil),
        ]

        // Configure complex filtering:
        // - Exclude merged and drafts
        // - Exclude approved PRs
        // - Blacklist dependabot
        // - Whitelist repo1 and repo2
        settings.excludedStatuses = [.merged, .draft]
        settings.excludedReviewDecisions = [.approved]
        settings.authorFilterEnabled = true
        settings.authorFilterMode = .blacklist
        settings.blacklistedAuthors = ["dependabot[bot]"]
        settings.repoFilterEnabled = true
        settings.repoFilterMode = .whitelist
        settings.whitelistedRepositories = ["owner/repo1", "owner/repo2"]

        // Apply all filters
        var filtered = filterPRsByStatus(prs)
        filtered = filterPRsByReviewDecision(filtered)
        filtered = filterPRsByRepository(filtered)
        filtered = filterPRsByAuthor(filtered)

        // Should only have PR #2 (bob's changes_requested PR in repo2)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "2")
    }

    func testPRSortingByDate() {
        let now = Date()
        let pr1 = createTestPR(id: "1", createdAt: now.addingTimeInterval(-3600)) // 1 hour ago
        let pr2 = createTestPR(id: "2", createdAt: now.addingTimeInterval(-7200)) // 2 hours ago
        let pr3 = createTestPR(id: "3", createdAt: now.addingTimeInterval(-1800)) // 30 minutes ago

        let sorted = [pr1, pr2, pr3].sorted { $0.createdAt > $1.createdAt }

        XCTAssertEqual(sorted[0].id, "3") // Most recent
        XCTAssertEqual(sorted[1].id, "1")
        XCTAssertEqual(sorted[2].id, "2") // Oldest
    }

    func testPRGroupingByRepository() {
        let repo1PR1 = createTestPR(id: "1", repo: "owner/repo1")
        let repo1PR2 = createTestPR(id: "2", repo: "owner/repo1")
        let repo2PR1 = createTestPR(id: "3", repo: "owner/repo2")
        let repo3PR1 = createTestPR(id: "4", repo: "owner/repo3")

        let allPRs = [repo1PR1, repo2PR1, repo1PR2, repo3PR1]

        let grouped = Dictionary(grouping: allPRs) { $0.repository.nameWithOwner }

        XCTAssertEqual(grouped.keys.count, 3)
        XCTAssertEqual(grouped["owner/repo1"]?.count, 2)
        XCTAssertEqual(grouped["owner/repo2"]?.count, 1)
        XCTAssertEqual(grouped["owner/repo3"]?.count, 1)
    }

    // MARK: - Helper Methods

    /// Helper to create a test PR with customizable properties
    private func createTestPR(
        id: String,
        state: String = "OPEN",
        isDraft: Bool = false,
        repo: String = "owner/repo",
        author: String = "testuser",
        reviewDecision: String? = nil,
        createdAt: Date = Date()
    ) -> PullRequest {
        return PullRequest(
            id: id,
            title: "Test PR \(id)",
            url: "https://github.com/\(repo)/pull/\(id)",
            number: Int(id) ?? 1,
            repository: PullRequest.Repository(nameWithOwner: repo),
            author: PullRequest.Author(login: author),
            createdAt: createdAt,
            assignees: [],
            commentsCount: 0,
            isDraft: isDraft,
            state: state,
            reviewDecision: reviewDecision
        )
    }

    /// Simulate status filtering logic from GitHubService
    private func filterPRsByStatus(_ prs: [PullRequest]) -> [PullRequest] {
        let included = settings.includedStatuses

        return prs.filter { pr in
            let status: PRStatus
            if pr.isDraft {
                status = .draft
            } else if pr.state == "MERGED" {
                status = .merged
            } else if pr.state == "CLOSED" {
                status = .closed
            } else {
                status = .open
            }
            return included.contains(status)
        }
    }

    /// Simulate review decision filtering logic
    private func filterPRsByReviewDecision(_ prs: [PullRequest]) -> [PullRequest] {
        let included = settings.includedReviewDecisions

        return prs.filter { pr in
            guard let decision = ReviewDecision(apiValue: pr.reviewDecision) else {
                return true
            }
            return included.contains(decision)
        }
    }

    /// Simulate repository filtering logic
    private func filterPRsByRepository(_ prs: [PullRequest]) -> [PullRequest] {
        guard let filter = settings.activeRepositoryFilter,
              let isWhitelist = settings.isRepositoryWhitelist else {
            return prs
        }

        return prs.filter { pr in
            let matches = filter.contains(pr.repository.nameWithOwner)
            return isWhitelist ? matches : !matches
        }
    }

    /// Simulate author filtering logic
    private func filterPRsByAuthor(_ prs: [PullRequest]) -> [PullRequest] {
        guard let filter = settings.activeAuthorFilter,
              let isWhitelist = settings.isAuthorWhitelist else {
            return prs
        }

        return prs.filter { pr in
            let matches = filter.contains(pr.author.login)
            return isWhitelist ? matches : !matches
        }
    }
}
