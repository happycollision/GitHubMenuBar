# Changelog

All notable changes to GitHub Menu Bar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Copy button for error messages in menu with visual feedback (checkmark animation)
- Command-click to copy PR URL to clipboard with visual feedback (green flash)
- Setting to reverse click behavior (click to copy, command-click to open)
- Gave the app an icon!

### Changed
- Error messages now display in normal readable color instead of grayed-out text

### Fixed

### Internal
- Comprehensive test suite with 38 automated tests
  - Unit tests for models, enums, and data structures
  - Unit tests for AppSettings with profile snapshot support
  - Integration tests for filtering, sorting, and grouping logic
  - Fast execution (< 0.1 seconds for full test suite)
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
