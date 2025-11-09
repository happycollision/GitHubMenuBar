import XCTest
@testable import GitHubMenuBar

@MainActor
final class ModelsTests: XCTestCase {

    // MARK: - PRStatus Tests

    func testPRStatusDisplayNames() {
        XCTAssertEqual(PRStatus.open.displayName, "Open")
        XCTAssertEqual(PRStatus.closed.displayName, "Closed")
        XCTAssertEqual(PRStatus.merged.displayName, "Merged")
        XCTAssertEqual(PRStatus.draft.displayName, "Draft")
    }

    func testPRStatusAllCases() {
        let allCases = PRStatus.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.open))
        XCTAssertTrue(allCases.contains(.closed))
        XCTAssertTrue(allCases.contains(.merged))
        XCTAssertTrue(allCases.contains(.draft))
    }

    // MARK: - ReviewDecision Tests

    func testReviewDecisionDisplayNames() {
        XCTAssertEqual(ReviewDecision.approved.displayName, "Approved")
        XCTAssertEqual(ReviewDecision.changesRequested.displayName, "Changes Requested")
        XCTAssertEqual(ReviewDecision.reviewRequired.displayName, "Review Required")
        XCTAssertEqual(ReviewDecision.noReview.displayName, "No Review")
    }

    func testReviewDecisionInitFromAPIValue() {
        XCTAssertEqual(ReviewDecision(apiValue: "APPROVED"), .approved)
        XCTAssertEqual(ReviewDecision(apiValue: "CHANGES_REQUESTED"), .changesRequested)
        XCTAssertEqual(ReviewDecision(apiValue: "REVIEW_REQUIRED"), .reviewRequired)
        XCTAssertEqual(ReviewDecision(apiValue: nil), .noReview)
        XCTAssertNil(ReviewDecision(apiValue: "INVALID"))
    }

    // MARK: - FilterMode Tests

    func testFilterModeDisplayNames() {
        XCTAssertEqual(FilterMode.whitelist.displayName, "Whitelist (Include Only)")
        XCTAssertEqual(FilterMode.blacklist.displayName, "Blacklist (Exclude)")
    }

    func testFilterModeCodable() throws {
        let whitelist = FilterMode.whitelist
        let blacklist = FilterMode.blacklist

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let whitelistData = try encoder.encode(whitelist)
        let blacklistData = try encoder.encode(blacklist)

        let decodedWhitelist = try decoder.decode(FilterMode.self, from: whitelistData)
        let decodedBlacklist = try decoder.decode(FilterMode.self, from: blacklistData)

        XCTAssertEqual(decodedWhitelist, .whitelist)
        XCTAssertEqual(decodedBlacklist, .blacklist)
    }

    // MARK: - PullRequest Tests

    func testPullRequestFormattedAge() {
        let now = Date()

        // Test "just now"
        let justNow = PullRequest(
            id: "1",
            title: "Test PR",
            url: "https://github.com/test/repo/pull/1",
            number: 1,
            repository: PullRequest.Repository(nameWithOwner: "test/repo"),
            author: PullRequest.Author(login: "testuser"),
            createdAt: now,
            assignees: [],
            commentsCount: 0,
            isDraft: false,
            state: "OPEN",
            reviewDecision: nil
        )
        XCTAssertEqual(justNow.formattedAge(), "just now")

        // Test "1 minute ago"
        let oneMinuteAgo = PullRequest(
            id: "2",
            title: "Test PR",
            url: "https://github.com/test/repo/pull/2",
            number: 2,
            repository: PullRequest.Repository(nameWithOwner: "test/repo"),
            author: PullRequest.Author(login: "testuser"),
            createdAt: now.addingTimeInterval(-60),
            assignees: [],
            commentsCount: 0,
            isDraft: false,
            state: "OPEN",
            reviewDecision: nil
        )
        XCTAssertEqual(oneMinuteAgo.formattedAge(), "1 minute ago")

        // Test "5 minutes ago"
        let fiveMinutesAgo = PullRequest(
            id: "3",
            title: "Test PR",
            url: "https://github.com/test/repo/pull/3",
            number: 3,
            repository: PullRequest.Repository(nameWithOwner: "test/repo"),
            author: PullRequest.Author(login: "testuser"),
            createdAt: now.addingTimeInterval(-5 * 60),
            assignees: [],
            commentsCount: 0,
            isDraft: false,
            state: "OPEN",
            reviewDecision: nil
        )
        XCTAssertEqual(fiveMinutesAgo.formattedAge(), "5 minutes ago")

        // Test "1 hour ago"
        let oneHourAgo = PullRequest(
            id: "4",
            title: "Test PR",
            url: "https://github.com/test/repo/pull/4",
            number: 4,
            repository: PullRequest.Repository(nameWithOwner: "test/repo"),
            author: PullRequest.Author(login: "testuser"),
            createdAt: now.addingTimeInterval(-60 * 60),
            assignees: [],
            commentsCount: 0,
            isDraft: false,
            state: "OPEN",
            reviewDecision: nil
        )
        XCTAssertEqual(oneHourAgo.formattedAge(), "1 hour ago")

        // Test "2 days ago"
        let twoDaysAgo = PullRequest(
            id: "5",
            title: "Test PR",
            url: "https://github.com/test/repo/pull/5",
            number: 5,
            repository: PullRequest.Repository(nameWithOwner: "test/repo"),
            author: PullRequest.Author(login: "testuser"),
            createdAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            assignees: [],
            commentsCount: 0,
            isDraft: false,
            state: "OPEN",
            reviewDecision: nil
        )
        XCTAssertEqual(twoDaysAgo.formattedAge(), "2 days ago")
    }

    func testPullRequestCodable() throws {
        let pr = PullRequest(
            id: "PR_123",
            title: "Add new feature",
            url: "https://github.com/owner/repo/pull/42",
            number: 42,
            repository: PullRequest.Repository(nameWithOwner: "owner/repo"),
            author: PullRequest.Author(login: "testuser"),
            createdAt: Date(),
            assignees: [
                PullRequest.Assignee(login: "reviewer1"),
                PullRequest.Assignee(login: "reviewer2")
            ],
            commentsCount: 5,
            isDraft: true,
            state: "OPEN",
            reviewDecision: "CHANGES_REQUESTED"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(pr)
        let decoded = try decoder.decode(PullRequest.self, from: data)

        XCTAssertEqual(decoded.id, pr.id)
        XCTAssertEqual(decoded.title, pr.title)
        XCTAssertEqual(decoded.url, pr.url)
        XCTAssertEqual(decoded.number, pr.number)
        XCTAssertEqual(decoded.repository.nameWithOwner, pr.repository.nameWithOwner)
        XCTAssertEqual(decoded.author.login, pr.author.login)
        XCTAssertEqual(decoded.assignees.count, pr.assignees.count)
        XCTAssertEqual(decoded.commentsCount, pr.commentsCount)
        XCTAssertEqual(decoded.isDraft, pr.isDraft)
        XCTAssertEqual(decoded.state, pr.state)
        XCTAssertEqual(decoded.reviewDecision, pr.reviewDecision)
    }
}
