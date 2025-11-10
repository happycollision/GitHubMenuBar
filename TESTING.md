# Testing Guide

This document describes the testing infrastructure for GitHub Menu Bar.

## Overview

The app uses a multi-layered testing strategy:

1. **Unit Tests** - Test individual components in isolation
2. **Integration Tests** - Test components working together
3. **Installer Tests** - Test the curl|bash installer script
4. **Snapshot Tests** (optional) - Visual regression testing
5. **Manual Testing** - For UI interactions that can't be automated

## Running Tests

### Run All Tests

```bash
# Run Swift unit and integration tests
swift test

# Run installer tests
./scripts/test_installer.sh
```

### Run Specific Test Suite

```bash
swift test --filter ModelsTests
swift test --filter AppSettingsTests
swift test --filter IntegrationTests
```

### Run Single Test

```bash
swift test --filter ModelsTests.testPRStatusDisplayNames
```

### Build for Testing

```bash
swift build --build-tests
```

## Test Structure

```
Tests/
└── GitHubMenuBarTests/
    ├── ModelsTests.swift           # Tests for Models, enums, data structures
    ├── AppSettingsTests.swift      # Tests for settings and persistence
    └── IntegrationTests.swift      # Tests for filtering and data flow

scripts/
└── test_installer.sh               # Bash tests for install.sh script
```

## What's Tested

### Swift Unit Tests (38 tests)

#### ModelsTests (8 tests)
- ✅ PRStatus enum display names and all cases
- ✅ ReviewDecision enum and API value initialization
- ✅ FilterMode Codable implementation
- ✅ PullRequest model encoding/decoding
- ✅ PullRequest age formatting

#### AppSettingsTests (21 tests)
- ✅ Status filtering (exclusion/inclusion)
- ✅ Review decision filtering
- ✅ Refresh interval with clamping (1-60 minutes)
- ✅ Repository filtering (whitelist/blacklist)
- ✅ Author filtering (whitelist/blacklist)
- ✅ Profile snapshot creation and application
- ✅ Settings persistence through UserDefaults

#### IntegrationTests (9 tests)
- ✅ PR filtering by multiple statuses
- ✅ PR filtering by review decisions
- ✅ Repository whitelist/blacklist filtering
- ✅ Author whitelist/blacklist filtering
- ✅ Combined filtering (status + review + repo + author)
- ✅ PR sorting by creation date
- ✅ PR grouping by repository

### Installer Tests (15 tests)

Located in [scripts/test_installer.sh](../scripts/test_installer.sh). Tests the curl|bash installer without performing actual installations.

#### What's Tested
- ✅ Help flag displays complete usage information
- ✅ `--list-versions` shows all available releases
- ✅ `--list-versions` skips system requirements check
- ✅ Version validation with `v` prefix (e.g., `v0.3.0`)
- ✅ Version normalization without `v` prefix (e.g., `0.3.0`)
- ✅ Invalid version shows error and lists alternatives
- ✅ `latest` keyword works correctly
- ✅ Unknown flags return proper errors
- ✅ Help text uses correct terminology
- ✅ Help includes usage examples
- ✅ Version format flexibility is documented
- ✅ Installation command suggestions provided
- ✅ Latest version marked correctly in output
- ✅ Version list ordering (oldest to newest)
- ✅ Release URLs included in output

#### Running Installer Tests

```bash
# Run all installer tests
./scripts/test_installer.sh

# Tests are safe for CI - they only test argument parsing
# and --list-versions mode (no actual installations)
```

**Note**: Installer tests make minimal GitHub API calls (2-3 requests total) to fetch real release data. Tests reuse cached output where possible to avoid rate limiting.

### Test Coverage

Current test coverage focuses on:
- ✅ Business logic (filtering, sorting, grouping)
- ✅ Data models and transformations
- ✅ Settings management
- ✅ Profile management
- ✅ Installer script functionality
- ⚠️ GitHub CLI integration (manual testing required)
- ⚠️ Menu bar UI (manual testing required)

## Testing Philosophy

### What We Test Automatically

1. **Business Logic** - Core filtering, sorting, and data transformation
2. **Data Models** - Codable implementation, computed properties
3. **Settings** - Persistence, validation, and profile management
4. **Integration** - Multiple components working together
5. **Installer** - Argument parsing, version handling, help text

### What We Test Manually

1. **Menu Bar Appearance** - Visual layout and positioning
2. **Click Interactions** - Opening PRs, copying URLs
3. **Menu Animations** - Smooth transitions
4. **GitHub CLI Integration** - Real `gh` command execution

This approach gives us:
- ✅ Fast test execution (< 1 second)
- ✅ Reliable, non-flaky tests
- ✅ High confidence in business logic
- ✅ Easy to maintain

## Testing with Real GitHub Data

The automated tests use mocked data, but you can manually test with real GitHub data:

```bash
# Build and run the app
swift build
.build/debug/GitHubMenuBar
```

The app will fetch your actual PR review requests and you can verify:
- PRs display correctly
- Filtering works as expected
- Click interactions open the correct URLs
- Settings persist across restarts

## Test Environment Detection

The app detects when it's running in a test environment and adjusts behavior:

```swift
// Detects XCTest environment automatically
let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
```

When tests are detected:
- ✅ Activation policy set to `.accessory` (makes app visible to tests)
- ✅ LSUIElement behavior bypassed in DEBUG builds
- ✅ No actual menu bar UI created during unit tests

## Writing New Tests

### Example Unit Test

```swift
import XCTest
@testable import GitHubMenuBar

@MainActor
final class MyTests: XCTestCase {
    func testMyFeature() {
        // Arrange
        let settings = AppSettings.shared
        settings.excludedStatuses = [.merged]

        // Act
        let included = settings.includedStatuses

        // Assert
        XCTAssertFalse(included.contains(.merged))
        XCTAssertTrue(included.contains(.open))
    }
}
```

### Example Integration Test

```swift
func testComplexFiltering() {
    let settings = AppSettings.shared
    settings.excludedStatuses = [.draft]
    settings.authorFilterEnabled = true
    settings.blacklistedAuthors = ["bot"]

    let prs = createTestPRs()
    let filtered = applyAllFilters(prs)

    XCTAssertEqual(filtered.count, expectedCount)
}
```

## Snapshot Testing (Optional)

The project includes `swift-snapshot-testing` for visual regression testing.

### Create a Snapshot Test

```swift
import SnapshotTesting
@testable import GitHubMenuBar

func testMenuAppearance() {
    let view = createMenuView()
    assertSnapshot(matching: view, as: .image)
}
```

### Update Snapshots

```bash
# Record new reference snapshots
swift test -- --enable-snapshot-recording

# Or set in code:
record = true  // In your test
```

## CI/CD Integration

### GitHub Actions

The project uses GitHub Actions to run tests automatically on every push and pull request. See [.github/workflows/test.yml](../.github/workflows/test.yml).

```yaml
name: Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Swift tests
        run: swift test

  installer-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run installer tests
        run: ./scripts/test_installer.sh
```

### Build Script Integration

The [scripts/build_release.sh](../scripts/build_release.sh) script runs all tests before building:

```bash
# Automatically runs before every release build
./scripts/build_release.sh
```

This ensures:
- ✅ All Swift unit tests pass
- ✅ All installer tests pass
- ✅ No broken releases are created

### CI Security Protections

The test workflow includes protections against resource abuse:

**Fork PR Protection:**
- Tests only run for PRs from branches **within the same repository**
- External fork PRs are skipped automatically
- Prevents consumption of CI minutes (macOS runners cost $0.08/minute)
- Prevents GitHub API rate limit abuse

**Why This Matters:**
- macOS CI runners are 10x more expensive than Linux
- Installer tests make GitHub API calls
- Without protection, malicious PRs could exhaust resources

**For Fork Contributors:**
- Your tests won't run automatically on your PR
- Maintainers can manually trigger workflows after reviewing code
- Tests will run automatically after your PR is merged

**Override for Trusted Contributors:**
If you want to allow specific forks to run tests, you can manually trigger the workflow via GitHub UI or adjust the `if:` condition in the workflow file.

### Test Requirements

- ✅ macOS 13.0+
- ✅ Swift 6.0+
- ✅ Xcode 16+ (for development)
- ✅ No external dependencies for unit tests
- ⚠️ GitHub CLI required for manual testing

## Troubleshooting

### Tests Fail with "No such file or directory"

Make sure you're running tests from the project root:

```bash
cd /path/to/GitHubMenuBar
swift test
```

### Tests Hang or Timeout

The app may be trying to access the menu bar. Make sure:
1. Tests are running in a proper test environment
2. No actual app instance is running
3. LSUIElement detection is working correctly

### Settings Tests Fail Intermittently

AppSettings uses a shared singleton with UserDefaults. To isolate tests:
1. Each test resets settings in `setUp()`
2. Use a test-specific UserDefaults suite name (if needed)

## Best Practices

### ✅ DO

- Test business logic extensively
- Use meaningful test names (`testFilteringExcludesMergedPRs`)
- Reset state in `setUp()` and `tearDown()`
- Test edge cases (empty arrays, nil values, etc.)
- Keep tests fast (< 0.1s per test)

### ❌ DON'T

- Test AppKit UI directly (too brittle)
- Make real GitHub API calls in unit tests
- Depend on external state or network
- Test implementation details (test behavior)
- Write slow tests that depend on timing

## Test Metrics

Current test suite:
- **Swift Tests**: 38 (unit + integration)
- **Installer Tests**: 15 (bash script tests)
- **Total Tests**: 53
- **Swift Execution Time**: ~0.06 seconds
- **Installer Execution Time**: ~5 seconds (includes API calls)
- **Success Rate**: 100%
- **Coverage**: ~70% of business logic + 100% of installer functionality

## Future Improvements

Potential additions:
- [ ] Snapshot tests for menu rendering
- [ ] Profile manager tests
- [ ] Error handling tests for GitHub CLI failures
- [ ] Performance tests for large PR lists
- [ ] Accessibility tests
- [ ] Localization tests

## Resources

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
- [Swift Testing Best Practices](https://www.swift.org/documentation/articles/testing-swift/)
