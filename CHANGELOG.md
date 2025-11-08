# Changelog

All notable changes to GitHub Menu Bar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
