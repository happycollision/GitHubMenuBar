# Architecture Documentation

## Overview

GitHubMenuBar is a native macOS menu bar application that monitors GitHub pull requests where the user has been requested as a reviewer. The app provides quick access to pending reviews directly from the system menu bar.

## Key Design Decisions

### 1. GitHub CLI Integration

**Decision**: Use `gh` CLI via shell commands instead of direct GitHub API calls.

**Rationale**:
- No token management required (users already authenticated via `gh auth login`)
- Simpler implementation without API client dependencies
- Users are likely already familiar with gh CLI
- Handles rate limiting and authentication automatically

**Implementation**: See `GitHubService.swift`

### 2. `gh search prs` vs `gh pr list`

**Decision**: Use `gh search prs --review-requested=@me` instead of `gh pr list`.

**Rationale**:
- `gh search prs` works from any directory (global search)
- `gh pr list` requires being in a git repository
- Menu bar apps can run from anywhere, not tied to a specific project

**Trade-offs**:
- Search API has different field names (e.g., `repository` instead of `headRepository`)
- Limited to 50 results by default (configurable via `--limit`)

### 3. SwiftUI App + AppKit Menu Bar

**Decision**: Use SwiftUI's App lifecycle but AppKit for menu bar functionality.

**Rationale**:
- SwiftUI doesn't have native menu bar support yet
- NSStatusBar is the mature, reliable way to create menu bar apps
- SwiftUI App lifecycle provides modern app structure
- Easy to add SwiftUI views later if needed

**Implementation**: See `GitHubMenuBar.swift` and `MenuBarController.swift`

### 4. Concurrency with @MainActor

**Decision**: Mark `MenuBarController` as `@MainActor` and use Swift concurrency.

**Rationale**:
- AppKit is not thread-safe; all UI updates must be on main thread
- @MainActor ensures this at compile time
- Async/await for clean, modern async code
- Sendable conformance for thread-safe service layer

### 5. Profiles System Architecture

**Decision**: Use hardcoded Default profile + JSON storage for user profiles with hybrid switching.

**Rationale**:
- **Hardcoded Default Profile**:
  - Ensures consistent baseline experience across installations
  - No migration needed for existing users
  - Read-only prevents accidental modification
  - Always available even if JSON is corrupted
- **JSON Storage for User Profiles**:
  - Human-readable format, easy to share/backup
  - Single file (profiles.json) for all user profiles
  - Atomic writes prevent corruption
  - Default excluded from JSON (stays hardcoded)
- **Hybrid Switching with In-Memory Changes**:
  - Preserves unsaved changes when switching profiles
  - No confirmation dialogs for seamless workflow
  - Changes stored in memory dictionary (pendingChanges)
  - Allows "exploring" other profiles without losing work
- **Silent Mode for applySnapshot**:
  - Prevents spurious change notifications during profile loading
  - Required for accurate unsaved changes detection
  - Used during switches to avoid triggering change handlers

**Implementation**: See `ProfileManager.swift`, `Profile.swift`

**Trade-offs**:
- More complex than simple settings file
- Requires careful state management for change tracking
- Benefits: Better UX, team collaboration, backup/restore

## Project Structure

```
GitHubMenuBar/
├── Sources/GitHubMenuBar/
│   ├── GitHubMenuBar.swift           # App entry point and AppDelegate
│   ├── Models.swift                  # Data models (PullRequest, AppSettings, AppError)
│   ├── Profile.swift                 # Profile data models and export/import types
│   ├── ProfileManager.swift          # Profile management singleton
│   ├── GitHubService.swift           # GitHub CLI integration layer
│   ├── MenuBarController.swift       # Menu bar UI and logic
│   ├── SettingsView.swift            # Settings window with tabs
│   ├── SettingsWindowController.swift # NSWindowController for settings
│   ├── ProfileManagementBar.swift    # Profile management UI component
│   └── ProfilesView.swift            # Advanced profile management tab
├── Package.swift                     # Swift Package Manager configuration
├── Info.plist                        # macOS app configuration (LSUIElement)
├── README.md                         # User-facing documentation
├── CHANGELOG.md                      # Version history and release notes
└── ARCHITECTURE.md                   # This file - technical documentation
```

## Component Breakdown

### GitHubMenuBar.swift
- **Responsibility**: Application lifecycle
- **Key classes**:
  - `GitHubMenuBar`: SwiftUI App struct (main entry point)
  - `AppDelegate`: Initializes MenuBarController

### Models.swift
- **Responsibility**: Data structures and settings
- **Key types**:
  - `PRStatus`: Enum representing filterable PR statuses (Open, Draft, Merged, Closed)
  - `ReviewDecision`: Enum for review approval states (Approved, ChangesRequested, ReviewRequired, NoReview)
  - `AppSettings`: Singleton managing user preferences via UserDefaults
    - Stores 12 filter settings (status, review decisions, refresh interval, grouping, repo/author filters)
    - Provides included/excluded status sets for filtering
    - Posts notifications when settings change via `didChangeNotification`
    - Thread-safe with @MainActor
    - **Profile Integration**:
      - `createSnapshot()`: Exports current settings to ProfileSettings
      - `applySnapshot(_:silent:)`: Imports settings from ProfileSettings with optional silent mode
  - `PullRequest`: Codable model matching gh CLI JSON output
    - Core fields: id, title, url, number, repository, author, createdAt
    - Metadata fields: assignees, commentsCount, isDraft, state, reviewDecision
    - Helper method: `formattedAge()` - formats PR age as human-readable string
  - `AppError`: App-specific error types with user-friendly messages

### Profile.swift
- **Responsibility**: Profile data models and export/import types
- **Key types**:
  - `ProfilesContainer`: Top-level JSON structure with version, activeProfile, and profiles dictionary
  - `Profile`: Individual profile with name, isDefault flag, timestamps, and settings
  - `ProfileSettings`: Codable struct containing all 12 filter settings
    - Custom equality comparison ignoring array ordering (compares as sets)
  - `ExportableProfiles`: Wrapper for exporting multiple profiles with metadata
  - `ImportResult`: Result type tracking imported/skipped/error profiles
  - `ConflictResolution`: Enum for import conflict strategies (skip/rename/overwrite)
  - `ProfileError`: Errors for profile operations with user-friendly descriptions

### ProfileManager.swift
- **Responsibility**: Centralized profile management and persistence
- **Key features**:
  - Singleton pattern with @MainActor isolation
  - ObservableObject with @Published properties for SwiftUI reactivity
  - Manages hardcoded Default profile (never stored in JSON)
  - Loads/saves user profiles from ~/Library/Application Support/GitHubMenuBar/profiles.json
  - Atomic writes to prevent corruption
  - Hybrid profile switching with in-memory change preservation
  - Export/import functionality with automatic conflict resolution
- **Published State**:
  - `activeProfileName`: Currently active profile name
  - `hasUnsavedChanges`: Whether current settings differ from saved profile
  - `availableProfiles`: All profile names (Default + user profiles)
- **Core Methods**:
  - `loadProfiles()`: Load from JSON, create empty if missing
  - `saveProfiles()`: Write to JSON with atomic writes
  - `getProfile(name:)`: Retrieve profile (checks Default first, then user profiles)
  - `saveProfile(name:settings:)`: Create/update user profile (prevents Default modification)
  - `deleteProfile(name:)`: Remove profile (prevents Default deletion)
  - `renameProfile(oldName:newName:)`: Rename profile (prevents Default rename)
  - `switchToProfile(name:currentSettings:)`: Switch with change preservation
  - `createProfileFromCurrentSettings(name:settings:)`: Save current state as new profile
  - `hasUnsavedChanges(currentSettings:)`: Compare against active profile
  - `revertToSaved()`: Discard changes and reload profile
  - `updateActiveProfile(settings:)`: Save changes to active profile
  - `exportAllProfiles(to:)`: Export all user profiles to JSON file
  - `importProfiles(from:conflictHandler:)`: Import with conflict resolution

### SettingsView.swift
- **Responsibility**: Main settings window with tabbed interface
- **Key features**:
  - SwiftUI view with TabView for organized settings
  - Three tabs: General (status/review filters), Advanced (repo/author filters), Profiles (management)
  - ProfileManagementBar component above tabs for quick profile operations
  - Observes AppSettings.didChangeNotification to reload on profile switches
  - Two-way binding with AppSettings for all filter controls
  - `onSettingsChanged` callback to trigger PR list refresh
- **State Management**:
  - Local @State for all UI controls (toggles, pickers, text fields)
  - `reloadSettingsFromAppSettings()`: Syncs UI state from AppSettings after profile switch
  - Updates AppSettings immediately when user changes any control

### SettingsWindowController.swift
- **Responsibility**: NSWindowController wrapper for SwiftUI settings
- **Key features**:
  - Singleton pattern for single settings window instance
  - Creates NSWindow with SwiftUI hosting view
  - Manages window lifecycle (show, close, focus)
  - Prevents multiple windows from opening

### ProfileManagementBar.swift
- **Responsibility**: Profile management controls in settings window
- **Key features**:
  - SwiftUI component displaying above settings tabs
  - Profile dropdown with unsaved changes indicator (asterisk)
  - Three action buttons: Update Profile, Save New, Revert
  - Observes ProfileManager for reactivity
  - Local state for unsaved changes tracking
  - Dialog sheets for creating new profiles with validation
- **Button States**:
  - Update Profile: Disabled when no changes or on Default profile
  - Save New: Disabled when no changes, opens name input dialog
  - Revert: Disabled when no changes
- **Actions**:
  - Profile switching triggers ProfileManager.switchToProfile()
  - Update saves to active profile via updateActiveProfile()
  - Save New creates new profile and switches to it
  - Revert calls ProfileManager.revertToSaved()
  - All actions invoke onSettingsChanged callback to refresh PRs

### ProfilesView.swift
- **Responsibility**: Advanced profile management in Profiles tab
- **Key features**:
  - SwiftUI view listing all available profiles
  - Visual indicators for Default profile and active profile
  - Per-profile action buttons (Export, Rename, Delete)
  - Import/Export buttons at top for bulk operations
  - Dialog sheets for rename operations with validation
  - Alert dialogs for delete confirmation and import results
- **Export/Import**:
  - Export All button: Opens NSSavePanel, calls exportAllProfiles()
  - Import button: Opens NSOpenPanel, calls importProfiles() with auto-rename conflict handler
  - Export button per profile: Opens NSSavePanel, calls exportProfile()
  - Import result displayed in alert with imported/skipped/error counts
- **Validation**:
  - Prevents empty profile names
  - Prevents "Default" name (case-insensitive)
  - Shows error messages for validation failures

### GitHubService.swift
- **Responsibility**: GitHub data fetching with status filtering
- **Key features**:
  - Singleton pattern (`GitHubService.shared`)
  - Sendable conformance for thread safety
  - Shell command execution via Process
  - Dynamic query building based on user's filter preferences
  - Error handling for gh CLI issues
- **Methods**:
  - `checkGHInstalled()`: Verifies gh is installed
  - `checkAuthentication()`: Verifies gh is authenticated
  - `buildSearchQuery()`: Constructs gh search query with status filters
  - `fetchReviewRequests()`: Fetches PRs via `gh search prs` with filters
- **JSON fields fetched**: id, title, url, number, repository, author, createdAt, assignees, commentsCount, isDraft, state
- **Query construction logic**:
  - Base query: `review-requested:@me`
  - Adds status filters based on AppSettings.includedStatuses
  - Handles OPEN/DRAFT logic (draft is subset of open)
  - Uses negative filters for excluded statuses (e.g., `-is:merged`)

### MenuBarController.swift
- **Responsibility**: Menu bar UI and user interactions
- **Key features**:
  - @MainActor for thread-safe UI updates
  - NSStatusItem management (icon + badge)
  - NSMenu construction and updates with multi-line PR items
  - Auto-refresh every 5 minutes
  - Click handlers for PR links
- **Menu item formatting**:
  - Two-line display per PR (title line + metadata line)
  - Title line shows PR info with [DRAFT] indicator if applicable
  - Metadata line uses attributed string: smaller font, secondary color
  - Metadata order: age, author, assignees, comments (age first for scannability)
  - Dynamic text based on counts (singular/plural handling)
  - Bullet separators (•) for visual clarity
- **State**:
  - `pullRequests`: Current PR list
  - `isLoading`: Loading state
  - `lastError`: Error message if fetch failed
  - `refreshTimer`: Timer for auto-refresh

## Data Flow

### App Launch with Profiles

```
AppDelegate.applicationDidFinishLaunching()
  ↓
ProfileManager.shared.loadProfiles()
  ↓
Load profiles.json OR create empty container
  ↓
Get active profile (Default or user profile)
  ↓
AppSettings.shared.applySnapshot(activeProfile.settings)
  ↓
MenuBarController.init()
  ↓
setupMenuBar() → Creates NSStatusItem with icon
  ↓
setupRefreshTimer() → Starts timer based on profile's refresh interval
  ↓
refresh() → Fetches data with profile's filter settings
  ↓
GitHubService.fetchReviewRequests()
  ↓
Shell: gh search prs --review-requested=@me --json ...
  ↓
Parse JSON → [PullRequest]
  ↓
updateMenu() → Rebuild NSMenu with PRs
  ↓
updateBadge() → Update count badge on icon
```

### Profile Switching Flow

```
User selects different profile from dropdown
  ↓
ProfileManagementBar.switchProfile(to: newName)
  ↓
ProfileManager.switchToProfile(name: newName, currentSettings: snapshot)
  ↓
IF current profile has unsaved changes
  → Store in pendingChanges[oldProfileName]
  ↓
Load new profile settings
  ↓
IF new profile has pending changes
  → Restore from pendingChanges[newProfileName]
  ELSE
  → Use saved profile settings
  ↓
AppSettings.shared.applySnapshot(settings, silent: true)
  ↓
Post AppSettings.didChangeNotification
  ↓
SettingsView.reloadSettingsFromAppSettings() → Updates UI
  ↓
MenuBarController.refresh() → Fetches PRs with new filters
```

### Save Profile Flow

```
User clicks "Update Profile" button
  ↓
ProfileManagementBar calls ProfileManager.updateActiveProfile()
  ↓
Validate: not Default profile
  ↓
Update profile.modifiedAt timestamp
  ↓
Write to profiles.json (atomic)
  ↓
Clear pendingChanges[profileName]
  ↓
Update @Published properties (hasUnsavedChanges → false)
```

## Menu Structure

```
GitHub PR Reviews (disabled title)
────────────────────────────────
[Loading...] OR [Error: ...] OR [No pending reviews] OR:
  repo/name #123: PR Title 1 [DRAFT]
     opened 2 days ago • by username • 2 assignees • 5 comments
  repo/name #456: PR Title 2
     opened 1 hour ago • by username • 3 comments
  ...
────────────────────────────────
Refresh (⌘R)
────────────────────────────────
Filter by Status ▶
  Show PRs with status: (disabled)
  ────────────────────
  ✓ Open
  ✓ Draft
    Merged
    Closed
────────────────────────────────
Quit (⌘Q)
```

Each PR displays:
- **Line 1**: Repository name, PR number, title, and [DRAFT] indicator (if applicable)
- **Line 2**: Metadata with bullet separators (•), formatted smaller and dimmed
  - Time since opened (always shown, comes first for scannability)
  - Author (always shown)
  - Assignee count (if any assigned)
  - Comment count (if any comments)

## Configuration

### Info.plist
- `LSUIElement = true`: Makes app menu bar-only (no dock icon)
- `CFBundleIdentifier`: com.github.menubar
- `LSMinimumSystemVersion`: 13.0 (macOS Ventura+)

### Package.swift
- Platform: macOS 13.0+
- Swift tools version: 6.2
- No external dependencies

## Known Limitations

1. **50 PR Limit**: Currently limited to 50 PRs (can be adjusted in GitHubService.swift)
2. **Limited Filtering**: Can filter by status, but not by age, repo, author, etc.
   - Note: The `gh` CLI supports additional filters (e.g., `repo:owner/name`, `author:username`, `created:>date`)
   - This is a UI limitation, not a gh CLI limitation - could be implemented in future versions
3. **No Sorting**: PRs appear in GitHub's default search order
   - Note: Could implement custom sorting in the UI layer
4. **No Notifications**: Doesn't show desktop notifications for new reviews
5. **Limited Review Details**: Cannot show number of requested reviewers or approval status (gh search prs limitation)
   - To get this data would require individual `gh pr view` calls per PR (slower)
6. **No Status Checks**: Doesn't show CI/CD status or merge conflicts
   - Note: Would require additional gh CLI calls per PR

## Future Enhancement Ideas

1. ✅ ~~**Configurable refresh interval**: Allow users to set refresh time~~ (Implemented in profiles)
2. ✅ ~~**Additional filters**: By repo, age, author, etc.~~ (Status, review decision, repo, and author filters implemented)
3. ✅ ~~**Saved filter presets**: Allow users to save and switch between filter combinations~~ (Implemented as profiles system)
4. **Individual profile export**: Export single profiles in addition to bulk export
5. **Interactive conflict resolution**: UI for choosing skip/rename/overwrite per conflict during import
6. **Desktop notifications**: Alert when new review requests appear
7. **Detailed review info**: Use hybrid approach with `gh pr view` for full review details
   - Show number of requested reviewers
   - Show approval/changes requested count
   - Show CI/CD status
   - Available on-demand (e.g., Option+click or submenu)
8. **Sort options**: Sort by age, repo, priority, etc.
9. **Multiple GitHub accounts**: Support for switching accounts
10. **Custom gh command**: Allow users to customize the search query

## Testing the App

### Manual Testing
```bash
# Build and run
swift build
.build/debug/GitHubMenuBar

# Or open in Xcode
open Package.swift
```

### Testing gh CLI integration
```bash
# Verify gh is installed
which gh

# Verify authentication
gh auth status

# Test the actual command we use
gh search prs --review-requested=@me --json "id,title,url,number,repository,author,createdAt" --limit 5
```

### Common Issues

1. **"gh not installed"**: User needs to run `brew install gh`
2. **"Not authenticated"**: User needs to run `gh auth login`
3. **No PRs showing**: Verify with manual gh command (see above)
4. **Icon shows 50**: Hitting the limit, adjust in GitHubService.swift

## Swift Concurrency Notes

### Why @MainActor?
- AppKit requires all UI updates on main thread
- @MainActor enforces this at compile time
- Prevents common threading bugs

### Why Sendable?
- GitHubService is shared across async contexts
- Sendable conformance proves it's thread-safe
- No mutable state = inherently thread-safe

### Why nonisolated deinit?
- deinit cannot be isolated to an actor
- MainActor.assumeIsolated safely accesses main actor properties
- Required for timer cleanup

## Contributing Guidelines

### Adding a New Feature

1. **Update Models** (if needed): Add new fields to PullRequest or new error types
2. **Update Service** (if needed): Add new GitHub CLI commands
3. **Update Controller**: Add UI for the feature
4. **Update README**: Document the feature for users
5. **Update ARCHITECTURE**: Document technical decisions

### Code Style

- Use Swift documentation comments (`///`) for public APIs
- Group code with `// MARK: -` comments
- Keep files focused on single responsibility
- Prefer clear names over brevity
- Use guard for early returns

### Concurrency Rules

- All UI code must be @MainActor
- Use Task {} for bridging sync to async
- Use weak self in closures to prevent retain cycles
- Never force unwrap in production code

## Dependencies

**None!** The app has zero external dependencies:
- Uses only Swift standard library
- Uses only Apple frameworks (Foundation, AppKit, SwiftUI)
- Uses gh CLI (user installs separately)

This keeps the app simple, lightweight, and easy to build.
