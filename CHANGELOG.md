# Changelog

All notable changes to GitHub Menu Bar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed
- Fix "gh not found" error when app is launched from Finder or login items on macOS
  - macOS GUI apps don't inherit user's shell PATH by default (only get `/usr/bin:/bin:/usr/sbin:/sbin`)
  - App now loads user's shell environment at startup to find `gh` in Homebrew locations
  - Works on both Intel (`/usr/local/bin`) and Apple Silicon (`/opt/homebrew/bin`) Macs
  - Environment is cached at startup for performance (avoids repeated shell spawns)

### Internal
- Replace print statements with Swift's unified logging system (os.Logger)
  - Uses proper log levels (.debug, .info, .error) instead of always-on print statements
  - Debug logs are automatically stripped from release builds for better performance
  - Logs can be filtered by subsystem and category in Console.app
  - Follows Apple's recommended best practices for macOS logging
- Fix Swift Package Manager build warning about unhandled Assets.xcassets file
  - Explicitly declare Assets.xcassets as a processed resource in Package.swift

## [0.4.0] - 2025-11-10

### Added
- Copy button for error messages in menu with visual feedback (checkmark animation)
- Command-click to copy PR URL to clipboard with visual feedback (green flash)
- Setting to reverse click behavior (click to copy, command-click to open)
- Gave the app an icon!
- **curl|bash installer script** (`install.sh`)
  - YOLO mode for full auto-install (`--yolo`)
  - Conservative mode (download and extract only, you handle the rest)
  - Version selection support (`--version v0.3.0` or `--version latest`)
  - Flexible version format (accepts `0.3.0` or `v0.3.0`)
  - `--list-versions` flag to view all available releases
  - `--remove-quarantine` flag to bypass macOS unsigned app security
  - `--move-to-applications` flag to automatically move to /Applications
  - System requirements checking (macOS version, GitHub CLI)
  - Colored output with clear status indicators
  - Smart error handling with helpful suggestions

### Changed
- Menu bar icon updated to crossed-out anchor design (Unicode anchor with rotated SF Symbol nosign overlay)
- Error messages now display in normal readable color instead of grayed-out text

### Internal
- Comprehensive test suite with 38 automated tests
  - Unit tests for models, enums, and data structures
  - Unit tests for AppSettings with profile snapshot support
  - Integration tests for filtering, sorting, and grouping logic
  - Fast execution (< 0.1 seconds for full test suite)
- Installer test suite with 15 automated tests
  - Tests argument parsing, version handling, help text
  - Validates `--list-versions` functionality
  - Tests version normalization and error handling
  - Safe for CI (no actual installations performed)
  - Execution time: ~5 seconds (includes GitHub API calls)
- GitHub Actions CI workflow with security protections
  - Runs 53 total tests (38 Swift + 15 installer)
  - Fork PR protection prevents resource abuse
  - Protects against CI cost ($0.08/min for macOS runners)
  - Prevents GitHub API rate limit exhaustion
- Build script integration runs all tests before building
- Test infrastructure with swift-snapshot-testing dependency
- Test environment detection for menu bar app compatibility
- TESTING.md documentation for test suite usage and best practices
- App icon workflow documentation for Liquid Glass icons
- Organized icon assets in dedicated `icons/` directory
  - Source Liquid Glass icon (`icons/GithubMenuBar.icon/`)
  - Build-ready PNG export (`icons/AppIcon.png`)
  - Automated .icns generation using native macOS tools (sips, iconutil)

## [0.3.0] - 2025-11-08

### Added
- Profiles system for managing filter configurations
  - Create, rename, delete, and switch between unlimited custom profiles
  - Read-only Default profile with sensible defaults always available
  - Profile Management Bar in settings with instant switching
  - Export/import all profiles for sharing and backup with automatic conflict resolution
  - Hybrid profile switching preserves unsaved changes in memory
  - Profiles stored in ~/Library/Application Support/GitHubMenuBar/profiles.json

### Internal
- Automated release process with CHANGELOG.md integration for consistent, accurate release notes

## [0.2.0] - 2025-11-08

### Added
- Repository and author whitelist/blacklist filtering
- PR approval status display and filtering
- Pill badges for PR status and approval filters in settings
- 50+ badge indicator when more PRs exist beyond display limit
- Vertical spacing between PR list items for improved readability

### Changed
- Reorganized settings window with tabbed interface for better organization
- Moved PR status and approval pills to second line with improved UX
- Limited PR display to 50 results for better performance
- Fixed merged/closed PR filtering to use API queries instead of app-level filtering

### Fixed
- Menu text colors now properly support dark mode
- Race condition when changing filter settings

## [0.1.0] - 2025-01-XX

### Added
- Initial release
- Display GitHub pull requests in macOS menu bar
- PR status filtering (Open, Draft, Merged, Closed)
- Click to open PRs in browser
- Auto-refresh capability
- Settings panel for filter configuration
