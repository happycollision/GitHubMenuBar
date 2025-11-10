# GitHub Menu Bar - Optimized Polling Implementation Plan

## Executive Summary

This document outlines the plan to implement optimized polling for the GitHub Menu Bar app to achieve near-real-time updates (1-2 minute delays) while minimizing GitHub API rate limit impact. The optimizations follow GitHub's recommended API usage patterns for polling-based applications.

**Goal:** Reduce perceived latency between GitHub state changes and menu bar updates from current polling intervals to 1-2 minutes, while ensuring 304 (Not Modified) responses don't consume API rate limits.

**Estimated Effort:** 1-2 weeks

---

## Background & Rationale

### Why Optimized Polling?

Research into push-based notification systems revealed that:

1. **GitHub doesn't offer user-level push APIs** - Webhooks are scoped to repositories/organizations, not individual users
2. **Desktop apps can't easily receive webhooks** - No public URL, would require tunneling services
3. **GitHub explicitly designed their API for polling** - Providing conditional request support, ETag headers, and 304 responses that don't count against rate limits

### Current State

**File:** `Sources/GitHubMenuBar/GitHubService.swift`
- Uses `gh api graphql` to query GitHub
- Makes separate queries for each PR status (draft, open, merged, closed)
- No conditional request headers currently implemented
- Always performs full data fetch regardless of changes

**File:** `Sources/GitHubMenuBar/MenuBarController.swift`
- Timer-based refresh with configurable interval
- Manual refresh button available
- Refresh on settings changes
- No optimization for "no changes" scenarios

### Problem

- Every refresh counts against the 5,000 req/hour rate limit
- No way to know if data changed without fetching it
- Polling frequency vs rate limit tradeoff

### Solution

GitHub provides conditional request support:
- **ETag headers** in responses identify content versions
- **If-None-Match** request header enables conditional requests
- **304 Not Modified** responses when content unchanged
- **Key benefit:** 304 responses DON'T count against rate limits!

---

## Technical Approach

### Phase 1: Conditional Request Support

#### 1.1 Response Header Storage

**Goal:** Persist ETag/Last-Modified headers from GitHub API responses

**Implementation:**
- Add `ResponseCache` class or struct to manage cached headers
- Store in UserDefaults with key format: `"github_etag_<endpoint_identifier>"`
- Track per-query-type (draft PRs, open PRs, etc.) since we make multiple queries

**Data Structure:**
```swift
struct GitHubResponseMetadata: Codable {
    let etag: String?
    let lastModified: String?
    let timestamp: Date
}

class ResponseCache {
    static let shared = ResponseCache()
    private let defaults = UserDefaults.standard

    func store(metadata: GitHubResponseMetadata, for key: String)
    func retrieve(for key: String) -> GitHubResponseMetadata?
    func clear(for key: String)
    func clearAll()
}
```

**Cache Keys:**
- `"pr_status_draft"`
- `"pr_status_open"`
- `"pr_status_merged"`
- `"pr_status_closed"`

#### 1.2 Request Header Injection

**Goal:** Add conditional request headers to GitHub API calls

**Current Implementation:**
```swift
func fetchPullRequests(status: PRStatus) async throws -> [PullRequest] {
    let query = buildGraphQLQuery(for: status)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["gh", "api", "graphql", "-f", "query=\(query)"]
    // ... execute and parse
}
```

**Challenge:** The `gh` CLI doesn't directly support custom headers for GraphQL requests

**Options:**

**Option A: Continue using `gh api graphql` (Simpler)**
- `gh api` supports `-H` flag for custom headers
- Syntax: `gh api graphql -f query="..." -H "If-None-Match: \"etag-value\""`
- Pro: Minimal code changes
- Con: Need to parse both 200 and 304 responses differently

**Option B: Switch to `gh api /notifications` REST endpoint (More aligned)**
- The `/notifications` endpoint is specifically for review requests, mentions, assignments
- Better semantic fit for "what needs my attention"
- Native support for conditional requests with ETags
- Pro: More appropriate endpoint, better structure
- Con: Different data format, requires data model changes

**Option C: Direct REST API calls using URLSession (Most flexible)**
- Use URLSession with `gh auth token` for authentication
- Full control over headers and response handling
- Pro: Complete control, can handle 304 responses cleanly
- Con: More code, need to implement authentication, error handling

**Recommended:** **Option A initially**, with Option B as a future enhancement after validating the pattern works.

**Modified Implementation:**
```swift
func fetchPullRequests(status: PRStatus) async throws -> [PullRequest] {
    let query = buildGraphQLQuery(for: status)
    let cacheKey = "pr_status_\(status.rawValue.lowercased())"

    // Retrieve cached metadata
    let cachedMetadata = ResponseCache.shared.retrieve(for: cacheKey)

    // Build command with conditional headers
    var arguments = ["gh", "api", "graphql", "-f", "query=\(query)"]
    if let etag = cachedMetadata?.etag {
        arguments.append(contentsOf: ["-H", "If-None-Match: \"\(etag)\""])
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments

    // Execute and handle response
    // ... (see 1.3 for response handling)
}
```

#### 1.3 Response Handling

**Goal:** Detect 304 responses and reuse cached data

**Challenge:** `gh api` returns HTTP status in stderr on non-200 responses

**Implementation:**
```swift
// Capture both stdout and stderr
let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

try process.run()
process.waitUntilExit()

let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

// Check for 304 in stderr
let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
if stderrString.contains("HTTP 304") || stderrString.contains("Not Modified") {
    // Return cached data
    return cachedData[cacheKey] ?? []
}

// Parse new data from stdout
let response = try JSONDecoder().decode(GitHubResponse.self, from: stdoutData)

// Extract and store ETag from response headers (if available via gh api)
// Note: gh api may not expose response headers easily - need to test
```

**Alternative Approach Using `gh api --include` Flag:**
```bash
gh api graphql --include -f query="..."
```
The `--include` flag includes HTTP headers in output, similar to curl's `-i` flag.

**Parsing Headers from `--include` Output:**
```swift
// Response format with --include:
// HTTP/2.0 200 OK
// etag: "abc123"
// x-ratelimit-remaining: 4999
//
// {"data": {...}}

let output = String(data: stdoutData, encoding: .utf8) ?? ""
let components = output.components(separatedBy: "\r\n\r\n")

if components.count >= 2 {
    let headerLines = components[0].components(separatedBy: "\r\n")
    let statusLine = headerLines[0]

    // Check for 304
    if statusLine.contains("304") {
        return cachedData[cacheKey] ?? []
    }

    // Extract ETag
    if let etagLine = headerLines.first(where: { $0.lowercased().starts(with: "etag:") }) {
        let etag = etagLine
            .components(separatedBy: ":")[1]
            .trimmingCharacters(in: .whitespaces)

        // Store for next request
        let metadata = GitHubResponseMetadata(
            etag: etag,
            lastModified: nil,
            timestamp: Date()
        )
        ResponseCache.shared.store(metadata: metadata, for: cacheKey)
    }

    // Parse JSON from body
    let jsonBody = components[1]
    // ... parse as usual
}
```

#### 1.4 Cache Management

**Goal:** Implement cache storage and retrieval

**Implementation in AppSettings.swift or new ResponseCache.swift:**

```swift
class ResponseCache {
    static let shared = ResponseCache()
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func key(for identifier: String) -> String {
        "github_response_metadata_\(identifier)"
    }

    func store(metadata: GitHubResponseMetadata, for identifier: String) {
        guard let data = try? encoder.encode(metadata) else { return }
        defaults.set(data, forKey: key(for: identifier))
    }

    func retrieve(for identifier: String) -> GitHubResponseMetadata? {
        guard let data = defaults.data(forKey: key(for: identifier)),
              let metadata = try? decoder.decode(GitHubResponseMetadata.self, from: data) else {
            return nil
        }

        // Expire cache after 24 hours to prevent stale ETags
        if Date().timeIntervalSince(metadata.timestamp) > 24 * 60 * 60 {
            clear(for: identifier)
            return nil
        }

        return metadata
    }

    func clear(for identifier: String) {
        defaults.removeObject(forKey: key(for: identifier))
    }

    func clearAll() {
        let keys = ["pr_status_draft", "pr_status_open", "pr_status_merged", "pr_status_closed"]
        keys.forEach { clear(for: $0) }
    }
}
```

#### 1.5 Data Caching

**Goal:** Cache actual PR data to return on 304 responses

**Implementation:**

Add to `ResponseCache` class:
```swift
struct CachedPullRequests: Codable {
    let pullRequests: [PullRequest]
    let timestamp: Date
}

func storePullRequests(_ prs: [PullRequest], for identifier: String) {
    let cached = CachedPullRequests(pullRequests: prs, timestamp: Date())
    guard let data = try? encoder.encode(cached) else { return }
    defaults.set(data, forKey: "cached_prs_\(identifier)")
}

func retrievePullRequests(for identifier: String) -> [PullRequest]? {
    guard let data = defaults.data(forKey: "cached_prs_\(identifier)"),
          let cached = try? decoder.decode(CachedPullRequests.self, from: data) else {
        return nil
    }
    return cached.pullRequests
}
```

**Update GitHubService.swift:**
```swift
// After parsing successful response
ResponseCache.shared.storePullRequests(pullRequests, for: cacheKey)
ResponseCache.shared.store(metadata: metadata, for: cacheKey)

// On 304 response
if let cachedPRs = ResponseCache.shared.retrievePullRequests(for: cacheKey) {
    return cachedPRs
}
```

---

### Phase 2: Smart Polling Intervals

#### 2.1 Parse X-Poll-Interval Header

**Goal:** Respect GitHub's recommended polling frequency

**Implementation:**

When parsing headers from `gh api --include` output:
```swift
// Extract X-Poll-Interval header
if let pollIntervalLine = headerLines.first(where: {
    $0.lowercased().starts(with: "x-poll-interval:")
}) {
    let intervalString = pollIntervalLine
        .components(separatedBy: ":")[1]
        .trimmingCharacters(in: .whitespaces)

    if let interval = TimeInterval(intervalString) {
        // Store recommended interval
        AppSettings.shared.recommendedPollInterval = interval
    }
}
```

**Add to AppSettings.swift:**
```swift
@Published var recommendedPollInterval: TimeInterval = 60 // Default 60s
@Published var useRecommendedInterval: Bool = true

var effectiveRefreshInterval: TimeInterval {
    if useRecommendedInterval {
        return recommendedPollInterval
    }
    return refreshInterval // User-configured interval
}
```

#### 2.2 Adaptive Polling Based on Time of Day

**Goal:** Poll more frequently during work hours, less during off-hours

**Implementation:**

Add to AppSettings.swift:
```swift
struct AdaptivePollingSchedule {
    var workHoursStart: Int = 9     // 9 AM
    var workHoursEnd: Int = 18      // 6 PM
    var workHoursInterval: TimeInterval = 60    // 1 minute
    var offHoursInterval: TimeInterval = 300    // 5 minutes
    var weekendInterval: TimeInterval = 600     // 10 minutes

    func currentInterval() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        // Weekend (Saturday = 7, Sunday = 1)
        if weekday == 1 || weekday == 7 {
            return weekendInterval
        }

        // Work hours
        if hour >= workHoursStart && hour < workHoursEnd {
            return workHoursInterval
        }

        // Off hours
        return offHoursInterval
    }
}

@Published var adaptivePolling: AdaptivePollingSchedule = AdaptivePollingSchedule()
@Published var enableAdaptivePolling: Bool = true

var effectiveRefreshInterval: TimeInterval {
    if enableAdaptivePolling {
        return adaptivePolling.currentInterval()
    }
    if useRecommendedInterval {
        return recommendedPollInterval
    }
    return refreshInterval
}
```

**Update MenuBarController.swift:**
```swift
private func scheduleNextRefresh() {
    refreshTimer?.invalidate()

    let interval = AppSettings.shared.effectiveRefreshInterval
    refreshTimer = Timer.scheduledTimer(
        withTimeInterval: interval,
        repeats: false
    ) { [weak self] _ in
        Task { @MainActor in
            await self?.refreshData()
        }
    }
}

func refreshData() async {
    await gitHubService.refresh()

    // Reschedule with potentially updated interval
    scheduleNextRefresh()
}
```

#### 2.3 Exponential Backoff on Errors

**Goal:** Reduce API pressure when errors occur

**Implementation:**

Add to GitHubService.swift:
```swift
private var consecutiveErrors: Int = 0
private let maxBackoffInterval: TimeInterval = 600 // 10 minutes
private let baseBackoffInterval: TimeInterval = 60 // 1 minute

private func calculateBackoffInterval() -> TimeInterval {
    let multiplier = pow(2.0, Double(min(consecutiveErrors, 5)))
    return min(baseBackoffInterval * multiplier, maxBackoffInterval)
}

func refresh() async {
    do {
        // Fetch PRs
        let draft = try await fetchPullRequests(status: .draft)
        // ... other statuses

        // Success - reset error count
        consecutiveErrors = 0

    } catch {
        consecutiveErrors += 1
        let backoffInterval = calculateBackoffInterval()

        print("GitHub API error (attempt \(consecutiveErrors)): \(error)")
        print("Backing off for \(Int(backoffInterval))s")

        // Notify AppSettings to use backoff interval
        await MainActor.run {
            AppSettings.shared.currentBackoffInterval = backoffInterval
        }

        throw error
    }
}
```

**Update AppSettings.swift:**
```swift
@Published var currentBackoffInterval: TimeInterval? = nil

var effectiveRefreshInterval: TimeInterval {
    // Backoff takes highest priority
    if let backoff = currentBackoffInterval {
        return backoff
    }

    if enableAdaptivePolling {
        return adaptivePolling.currentInterval()
    }
    if useRecommendedInterval {
        return recommendedPollInterval
    }
    return refreshInterval
}
```

---

### Phase 3: Background Optimizations

#### 3.1 Detect Mac Sleep/Wake Events

**Goal:** Pause polling when Mac is sleeping, resume on wake

**Implementation:**

Add to MenuBarController.swift:
```swift
import IOKit.pwr_mgt

class MenuBarController {
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func setupPowerNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSleep()
        }

        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    private func handleSleep() {
        print("Mac going to sleep - pausing refresh timer")
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func handleWake() {
        print("Mac woke up - refreshing immediately")
        Task { @MainActor in
            await refreshData()
        }
    }

    deinit {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
```

**Call in init:**
```swift
init() {
    // ... existing init
    setupPowerNotifications()
}
```

#### 3.2 Network Availability Check

**Goal:** Don't poll when network is unavailable

**Implementation:**

Add to GitHubService.swift:
```swift
import Network

class GitHubService {
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    func startMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = (path.status == .satisfied)

            if path.status == .satisfied {
                print("Network available")
            } else {
                print("Network unavailable")
            }
        }

        networkMonitor.start(queue: DispatchQueue.global(qos: .background))
    }

    func refresh() async throws {
        guard isNetworkAvailable else {
            print("Skipping refresh - network unavailable")
            return
        }

        // ... existing refresh logic
    }
}
```

**Update MenuBarController to handle network unavailability:**
```swift
func refreshData() async {
    do {
        try await gitHubService.refresh()
    } catch {
        // Handle error, but continue scheduling next refresh
        print("Refresh failed: \(error)")
    }

    // Always reschedule, even on error (backoff handled by AppSettings)
    scheduleNextRefresh()
}
```

---

### Phase 4: Testing & Validation

#### 4.1 Unit Tests

**Create:** `Tests/GitHubMenuBarTests/ResponseCacheTests.swift`

```swift
import XCTest
@testable import GitHubMenuBar

class ResponseCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ResponseCache.shared.clearAll()
    }

    func testStoreAndRetrieveMetadata() {
        let metadata = GitHubResponseMetadata(
            etag: "test-etag",
            lastModified: "Mon, 10 Nov 2025 12:00:00 GMT",
            timestamp: Date()
        )

        ResponseCache.shared.store(metadata: metadata, for: "test_key")
        let retrieved = ResponseCache.shared.retrieve(for: "test_key")

        XCTAssertEqual(retrieved?.etag, "test-etag")
    }

    func testMetadataExpiration() {
        var metadata = GitHubResponseMetadata(
            etag: "old-etag",
            lastModified: nil,
            timestamp: Date(timeIntervalSinceNow: -25 * 60 * 60) // 25 hours ago
        )

        ResponseCache.shared.store(metadata: metadata, for: "test_key")
        let retrieved = ResponseCache.shared.retrieve(for: "test_key")

        XCTAssertNil(retrieved, "Expired metadata should return nil")
    }

    func testStoreAndRetrievePullRequests() {
        let prs = [
            PullRequest(/* ... test data ... */)
        ]

        ResponseCache.shared.storePullRequests(prs, for: "test_key")
        let retrieved = ResponseCache.shared.retrievePullRequests(for: "test_key")

        XCTAssertEqual(retrieved?.count, 1)
    }
}
```

**Create:** `Tests/GitHubMenuBarTests/AdaptivePollingTests.swift`

```swift
class AdaptivePollingTests: XCTestCase {
    func testWorkHoursInterval() {
        let schedule = AdaptivePollingSchedule()

        // Test during work hours (mock current time to 10 AM weekday)
        // ... test implementation with date mocking
    }

    func testWeekendInterval() {
        // Test weekend intervals are longer
    }

    func testOffHoursInterval() {
        // Test off-hours (evening/night) intervals
    }
}
```

#### 4.2 Integration Tests

**Manual Test Plan:**

1. **Conditional Request Flow**
   - [ ] Start app, verify initial fetch with no If-None-Match header
   - [ ] Wait for refresh, verify If-None-Match header is sent
   - [ ] Monitor `gh` output for 304 responses
   - [ ] Verify menu bar updates correctly on 304 (shows cached data)
   - [ ] Make a change on GitHub (create/update PR)
   - [ ] Verify next refresh gets 200 response with new data

2. **Rate Limit Impact**
   - [ ] Monitor rate limit before test: `gh api rate_limit`
   - [ ] Run app with 1-minute polling for 10 minutes
   - [ ] Check rate limit after: should show ~1-2 requests consumed (not 10)
   - [ ] Verify most requests returned 304

3. **Error Handling & Backoff**
   - [ ] Simulate API error (network disconnection)
   - [ ] Verify exponential backoff increases intervals
   - [ ] Restore network, verify recovery and reset of error count
   - [ ] Check logs for backoff messages

4. **Sleep/Wake Behavior**
   - [ ] Start app and monitor refresh timer
   - [ ] Put Mac to sleep
   - [ ] Verify timer is invalidated (check logs)
   - [ ] Wake Mac
   - [ ] Verify immediate refresh occurs
   - [ ] Verify timer resumes with correct interval

5. **Network Monitoring**
   - [ ] Start app with network connected
   - [ ] Disable WiFi/Ethernet
   - [ ] Verify refresh is skipped (check logs)
   - [ ] Re-enable network
   - [ ] Verify refresh resumes automatically

6. **Adaptive Polling**
   - [ ] Test during work hours (9 AM - 6 PM weekday)
   - [ ] Verify 1-minute interval used
   - [ ] Test during off-hours (evening)
   - [ ] Verify 5-minute interval used
   - [ ] Test on weekend
   - [ ] Verify 10-minute interval used

#### 4.3 Performance Monitoring

**Add logging to track effectiveness:**

```swift
struct RefreshMetrics {
    var totalRequests: Int = 0
    var cached304Responses: Int = 0
    var dataChanges: Int = 0
    var errors: Int = 0

    var cacheHitRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(cached304Responses) / Double(totalRequests)
    }
}

class GitHubService {
    var metrics = RefreshMetrics()

    func refresh() async throws {
        metrics.totalRequests += 1

        // ... in 304 handling:
        if is304Response {
            metrics.cached304Responses += 1
        } else {
            metrics.dataChanges += 1
        }

        // Log periodically
        if metrics.totalRequests % 10 == 0 {
            print("Refresh metrics: \(metrics.cacheHitRate * 100)% cache hit rate")
        }
    }
}
```

---

## Phase 5: Documentation

### 5.1 Update ARCHITECTURE.md

Add new section: **"Polling Optimization Strategy"**

Content should include:
- Explanation of conditional requests and ETags
- ResponseCache architecture
- Smart polling intervals and adaptive scheduling
- Background optimizations (sleep/wake, network monitoring)
- Rate limit impact analysis

### 5.2 Update CHANGELOG.md

Under `[Unreleased]` section:

**Added:**
- Conditional request support with ETag caching for efficient polling
- Smart polling intervals that respect GitHub's X-Poll-Interval recommendations
- Adaptive polling based on time of day (faster during work hours, slower at night/weekends)
- Exponential backoff on API errors to reduce load during issues
- Mac sleep/wake detection - pauses polling when sleeping, refreshes immediately on wake
- Network availability monitoring - skips polling when offline

**Internal:**
- ResponseCache class for managing GitHub API response metadata
- RefreshMetrics for monitoring cache hit rates and polling effectiveness
- Power and network notification observers in MenuBarController

### 5.3 Update README.md (if needed)

If adaptive polling is configurable, document settings:

```markdown
## Polling Configuration

GitHub Menu Bar uses optimized polling to minimize API rate limit usage:

- **Conditional Requests**: Only downloads data when it has changed
- **Smart Intervals**: Automatically adjusts polling frequency based on GitHub's recommendations
- **Adaptive Polling**: Polls more frequently during work hours (9 AM - 6 PM), less during nights and weekends
- **Power Aware**: Pauses when your Mac sleeps, refreshes immediately on wake

### Customizing Polling

Configure polling behavior in Preferences:
- Enable/disable adaptive polling
- Set custom work hours
- Adjust polling intervals for work hours, off-hours, and weekends
```

---

## Implementation Timeline

### Week 1: Core Implementation

**Days 1-2: Conditional Requests (Phase 1)**
- Implement ResponseCache class
- Add ETag storage/retrieval
- Modify GitHubService to include If-None-Match headers
- Handle 304 responses
- Cache PR data

**Days 3-4: Smart Polling (Phase 2)**
- Parse X-Poll-Interval header
- Implement adaptive polling schedule
- Add exponential backoff
- Update MenuBarController timer logic

**Day 5: Background Optimizations (Phase 3)**
- Add sleep/wake notifications
- Implement network monitoring
- Test power-aware behavior

### Week 2: Testing & Documentation

**Days 1-2: Unit Tests (Phase 4.1)**
- Write ResponseCache tests
- Write adaptive polling tests
- Write backoff tests

**Days 3-4: Integration Testing (Phase 4.2)**
- Manual test plan execution
- Bug fixes from testing
- Performance monitoring

**Day 5: Documentation (Phase 5)**
- Update ARCHITECTURE.md
- Update CHANGELOG.md
- Update README.md if needed
- Code review and cleanup

---

## Files to Modify

### New Files
- `Sources/GitHubMenuBar/ResponseCache.swift` - ETag and data caching
- `Tests/GitHubMenuBarTests/ResponseCacheTests.swift` - Cache tests
- `Tests/GitHubMenuBarTests/AdaptivePollingTests.swift` - Polling tests

### Modified Files
- `Sources/GitHubMenuBar/GitHubService.swift` - Conditional requests, backoff, network monitoring
- `Sources/GitHubMenuBar/MenuBarController.swift` - Sleep/wake handling, dynamic intervals
- `Sources/GitHubMenuBar/AppSettings.swift` - Adaptive polling configuration
- `Sources/GitHubMenuBar/Models.swift` - GitHubResponseMetadata struct
- `ARCHITECTURE.md` - Document polling optimizations
- `CHANGELOG.md` - Document changes
- `README.md` - Update if user-facing settings added

---

## Success Metrics

After implementation, we should see:

1. **Rate Limit Efficiency**
   - Cache hit rate > 80% (304 responses)
   - Rate limit consumption reduced by 70-90%

2. **Responsiveness**
   - Average polling interval: 1-2 minutes during work hours
   - Immediate refresh on wake from sleep
   - Graceful degradation during network issues

3. **Reliability**
   - No crashes or hangs during network issues
   - Proper recovery from API errors
   - Stable performance over extended usage

---

## Risks & Mitigation

### Risk 1: `gh api` header parsing complexity

**Issue:** Extracting ETags from `gh api --include` output may be fragile

**Mitigation:**
- Implement robust header parsing with error handling
- Fallback to no conditional requests if parsing fails
- Consider Option C (direct URLSession) if `gh` proves problematic

### Risk 2: Rate limit not actually saved

**Issue:** 304 responses may still count against rate limits despite GitHub docs

**Mitigation:**
- Test early with rate limit monitoring: `gh api rate_limit`
- Measure actual rate limit consumption over time
- Document findings and adjust strategy if needed

### Risk 3: Cache invalidation bugs

**Issue:** Stale data shown to users if cache not properly invalidated

**Mitigation:**
- 24-hour cache expiration as safety net
- Clear cache on manual refresh button
- Add "Clear Cache" debug option in settings
- Comprehensive testing of cache scenarios

### Risk 4: Timer drift with dynamic intervals

**Issue:** Rescheduling timer after each refresh may cause drift

**Mitigation:**
- Use `Timer.scheduledTimer` with `repeats: false` and manual rescheduling
- Log actual refresh times during testing
- Monitor for accumulating drift over long sessions

---

## Future Enhancements

After initial implementation and validation:

1. **Switch to `/notifications` REST API**
   - More semantic fit for review requests
   - Potentially better data structure
   - Native support for conditional requests

2. **User-configurable polling settings UI**
   - Preferences window for adaptive polling
   - Custom work hours
   - Enable/disable features

3. **Advanced cache strategies**
   - Per-PR caching for more granular updates
   - Delta updates (only fetch changed PRs)
   - Predictive prefetching based on usage patterns

4. **Rate limit dashboard**
   - Show remaining API quota in menu
   - Warn when approaching limit
   - Suggest optimal polling interval based on quota

---

## References

- [GitHub REST API - Conditional Requests](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#conditional-requests)
- [GitHub REST API - Rate Limiting](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)
- [GitHub CLI - api command](https://cli.github.com/manual/gh_api)
- [Keep a Changelog](https://keepachangelog.com/)
- RFC 7232 - HTTP/1.1 Conditional Requests

---

## Questions for Review

Before implementation begins, please review and provide feedback on:

1. **Approach:** Is Option A (continue with `gh api` + header parsing) acceptable, or should we go directly to Option C (URLSession)?

2. **Adaptive Polling:** Are the default intervals reasonable?
   - Work hours: 1 minute
   - Off-hours: 5 minutes
   - Weekends: 10 minutes

3. **User Settings:** Should adaptive polling be user-configurable in this phase, or wait for future enhancement?

4. **Scope:** Any features you'd like to add or remove from this plan?

5. **Timeline:** Does 1-2 weeks seem reasonable for this scope?
