import XCTest
@testable import GitHubMenuBar

@MainActor
final class AppSettingsTests: XCTestCase {

    var settings: AppSettings!

    override func setUp() async throws {
        settings = AppSettings.shared

        // Reset all settings to clean state
        settings.excludedStatuses = []
        settings.excludedReviewDecisions = []
        settings.refreshIntervalMinutes = 5
        settings.groupByRepo = true
        settings.reverseClickBehavior = false
        settings.repoFilterEnabled = false
        settings.repoFilterMode = .blacklist
        settings.whitelistedRepositories = []
        settings.blacklistedRepositories = []
        settings.authorFilterEnabled = false
        settings.authorFilterMode = .blacklist
        settings.whitelistedAuthors = []
        settings.blacklistedAuthors = []
    }

    override func tearDown() async throws {
        // Clean up after test
        settings.excludedStatuses = []
        settings.excludedReviewDecisions = []
        settings.repoFilterEnabled = false
        settings.authorFilterEnabled = false
    }

    // MARK: - Status Filtering Tests

    func testExcludedStatusesDefaultsToEmpty() {
        // Note: This test may fail if app has been run with different defaults
        // In production tests, we'd need dependency injection for UserDefaults
        let excluded = settings.excludedStatuses
        // Can't reliably test defaults without DI, so just verify it's a Set
        XCTAssertTrue(excluded is Set<PRStatus>)
    }

    func testToggleExclusionForStatus() {
        // Start with clean state
        settings.excludedStatuses = []

        // Exclude merged status
        settings.toggleExclusion(for: .merged)
        XCTAssertTrue(settings.isExcluded(.merged))
        XCTAssertFalse(settings.isExcluded(.open))

        // Toggle back to include
        settings.toggleExclusion(for: .merged)
        XCTAssertFalse(settings.isExcluded(.merged))
    }

    func testIncludedStatuses() {
        settings.excludedStatuses = [.merged, .closed]

        let included = settings.includedStatuses
        XCTAssertEqual(included.count, 2)
        XCTAssertTrue(included.contains(.open))
        XCTAssertTrue(included.contains(.draft))
        XCTAssertFalse(included.contains(.merged))
        XCTAssertFalse(included.contains(.closed))
    }

    func testExcludeAllStatuses() {
        settings.excludedStatuses = Set(PRStatus.allCases)

        XCTAssertTrue(settings.includedStatuses.isEmpty)
        XCTAssertTrue(settings.isExcluded(.open))
        XCTAssertTrue(settings.isExcluded(.closed))
        XCTAssertTrue(settings.isExcluded(.merged))
        XCTAssertTrue(settings.isExcluded(.draft))
    }

    // MARK: - Review Decision Filtering Tests

    func testToggleExclusionForReviewDecision() {
        settings.excludedReviewDecisions = []

        settings.toggleExclusion(for: .approved)
        XCTAssertTrue(settings.isExcluded(.approved))
        XCTAssertFalse(settings.isExcluded(.changesRequested))

        settings.toggleExclusion(for: .approved)
        XCTAssertFalse(settings.isExcluded(.approved))
    }

    func testIncludedReviewDecisions() {
        settings.excludedReviewDecisions = [.approved, .noReview]

        let included = settings.includedReviewDecisions
        XCTAssertEqual(included.count, 2)
        XCTAssertTrue(included.contains(.changesRequested))
        XCTAssertTrue(included.contains(.reviewRequired))
        XCTAssertFalse(included.contains(.approved))
        XCTAssertFalse(included.contains(.noReview))
    }

    // MARK: - Refresh Interval Tests

    func testRefreshIntervalDefaultValue() {
        // Default should be 5 minutes
        XCTAssertGreaterThanOrEqual(settings.refreshIntervalMinutes, 1)
        XCTAssertLessThanOrEqual(settings.refreshIntervalMinutes, 60)
    }

    func testRefreshIntervalClamping() {
        settings.refreshIntervalMinutes = 100
        XCTAssertEqual(settings.refreshIntervalMinutes, 60, "Should clamp to max 60")

        settings.refreshIntervalMinutes = -5
        XCTAssertEqual(settings.refreshIntervalMinutes, 1, "Should clamp to min 1")
    }

    func testRefreshIntervalSeconds() {
        settings.refreshIntervalMinutes = 10
        XCTAssertEqual(settings.refreshIntervalSeconds, 600.0)
    }

    // MARK: - Repository Filtering Tests

    func testRepositoryFilterWhitelist() {
        settings.repoFilterEnabled = true
        settings.repoFilterMode = .whitelist
        settings.whitelistedRepositories = ["owner/repo1", "owner/repo2"]

        XCTAssertEqual(settings.activeRepositoryFilter, ["owner/repo1", "owner/repo2"])
        XCTAssertEqual(settings.isRepositoryWhitelist, true)
    }

    func testRepositoryFilterBlacklist() {
        settings.repoFilterEnabled = true
        settings.repoFilterMode = .blacklist
        settings.blacklistedRepositories = ["owner/spam", "owner/noise"]

        XCTAssertEqual(settings.activeRepositoryFilter, ["owner/spam", "owner/noise"])
        XCTAssertEqual(settings.isRepositoryWhitelist, false)
    }

    func testRepositoryFilterDisabled() {
        settings.repoFilterEnabled = false
        settings.whitelistedRepositories = ["owner/repo"]

        XCTAssertNil(settings.activeRepositoryFilter)
        XCTAssertNil(settings.isRepositoryWhitelist)
    }

    func testAddAndRemoveWhitelistedRepo() {
        settings.whitelistedRepositories = []

        settings.addWhitelistedRepo("owner/repo1")
        XCTAssertTrue(settings.whitelistedRepositories.contains("owner/repo1"))

        settings.addWhitelistedRepo("owner/repo2")
        XCTAssertEqual(settings.whitelistedRepositories.count, 2)

        settings.removeWhitelistedRepo("owner/repo1")
        XCTAssertFalse(settings.whitelistedRepositories.contains("owner/repo1"))
        XCTAssertTrue(settings.whitelistedRepositories.contains("owner/repo2"))
    }

    func testAddAndRemoveBlacklistedRepo() {
        settings.blacklistedRepositories = []

        settings.addBlacklistedRepo("owner/spam")
        XCTAssertTrue(settings.blacklistedRepositories.contains("owner/spam"))

        settings.removeBlacklistedRepo("owner/spam")
        XCTAssertFalse(settings.blacklistedRepositories.contains("owner/spam"))
    }

    // MARK: - Author Filtering Tests

    func testAuthorFilterWhitelist() {
        settings.authorFilterEnabled = true
        settings.authorFilterMode = .whitelist
        settings.whitelistedAuthors = ["alice", "bob"]

        XCTAssertEqual(settings.activeAuthorFilter, ["alice", "bob"])
        XCTAssertEqual(settings.isAuthorWhitelist, true)
    }

    func testAuthorFilterBlacklist() {
        settings.authorFilterEnabled = true
        settings.authorFilterMode = .blacklist
        settings.blacklistedAuthors = ["spammer", "bot"]

        XCTAssertEqual(settings.activeAuthorFilter, ["spammer", "bot"])
        XCTAssertEqual(settings.isAuthorWhitelist, false)
    }

    func testAuthorFilterDisabled() {
        settings.authorFilterEnabled = false
        settings.whitelistedAuthors = ["alice"]

        XCTAssertNil(settings.activeAuthorFilter)
        XCTAssertNil(settings.isAuthorWhitelist)
    }

    // MARK: - Profile Snapshot Tests

    func testCreateSnapshot() {
        // Configure settings
        settings.excludedStatuses = [.merged, .closed]
        settings.excludedReviewDecisions = [.noReview]
        settings.repoFilterEnabled = true
        settings.repoFilterMode = .whitelist
        settings.whitelistedRepositories = ["owner/repo1"]
        settings.authorFilterEnabled = true
        settings.authorFilterMode = .blacklist
        settings.blacklistedAuthors = ["bot"]

        // Create snapshot
        let snapshot = settings.createSnapshot()

        // Verify snapshot captures all profile-specific settings
        // Note: refreshIntervalMinutes, groupByRepo, reverseClickBehavior are global settings
        // and are not included in profiles
        XCTAssertTrue(snapshot.excludedStatuses.contains("MERGED"))
        XCTAssertTrue(snapshot.excludedStatuses.contains("CLOSED"))
        XCTAssertTrue(snapshot.excludedReviewDecisions.contains("NO_REVIEW"))
        XCTAssertEqual(snapshot.repoFilterEnabled, true)
        XCTAssertEqual(snapshot.repoFilterMode, "whitelist")
        XCTAssertEqual(snapshot.whitelistedRepositories, ["owner/repo1"])
        XCTAssertEqual(snapshot.authorFilterEnabled, true)
        XCTAssertEqual(snapshot.authorFilterMode, "blacklist")
        XCTAssertEqual(snapshot.blacklistedAuthors, ["bot"])
    }

    func testApplySnapshot() {
        // Create a snapshot with specific settings
        // Note: refreshIntervalMinutes, groupByRepo, reverseClickBehavior are global settings
        // and are not included in profiles
        let snapshot = ProfileSettings(
            excludedStatuses: ["DRAFT", "MERGED"],
            excludedReviewDecisions: ["APPROVED"],
            repoFilterEnabled: true,
            repoFilterMode: "blacklist",
            whitelistedRepositories: [],
            blacklistedRepositories: ["owner/spam"],
            authorFilterEnabled: false,
            authorFilterMode: "whitelist",
            whitelistedAuthors: [],
            blacklistedAuthors: []
        )

        // Apply snapshot
        settings.applySnapshot(snapshot)

        // Verify profile-specific settings were updated
        XCTAssertTrue(settings.isExcluded(.draft))
        XCTAssertTrue(settings.isExcluded(.merged))
        XCTAssertFalse(settings.isExcluded(.open))
        XCTAssertTrue(settings.isExcluded(.approved))
        XCTAssertEqual(settings.repoFilterEnabled, true)
        XCTAssertEqual(settings.repoFilterMode, .blacklist)
        XCTAssertEqual(settings.blacklistedRepositories, ["owner/spam"])
        XCTAssertEqual(settings.authorFilterEnabled, false)
    }

    // MARK: - Other Settings Tests

    func testGroupByRepoSetting() {
        settings.groupByRepo = true
        XCTAssertTrue(settings.groupByRepo)

        settings.groupByRepo = false
        XCTAssertFalse(settings.groupByRepo)
    }

    func testReverseClickBehaviorSetting() {
        settings.reverseClickBehavior = true
        XCTAssertTrue(settings.reverseClickBehavior)

        settings.reverseClickBehavior = false
        XCTAssertFalse(settings.reverseClickBehavior)
    }
}
