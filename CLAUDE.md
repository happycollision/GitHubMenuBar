# GitHub Menu Bar - Claude Code Instructions

## CHANGELOG.md Maintenance

**IMPORTANT**: CHANGELOG.md should be updated with EVERY meaningful commit.

### How It Works

CHANGELOG.md always has an `[Unreleased]` section at the top where you document changes as you make them. When cutting a release, simply:
1. Rename `[Unreleased]` to the new version number and date
2. Add a fresh `[Unreleased]` section at the top

This follows the standard [Keep a Changelog](https://keepachangelog.com/) format.

### When to Update CHANGELOG.md

Update the `[Unreleased]` section when making:
- **User-facing changes**: New features, bug fixes, behavior changes
- **Internal improvements**: Tooling, CI/CD, refactoring, documentation

Skip trivial changes like: typos in comments, code formatting, minor whitespace adjustments.

### CHANGELOG Sections

**User-Facing Sections:**
- **Added** - New features and functionality
- **Changed** - Modifications to existing features
- **Fixed** - Bug fixes
- **Deprecated** - Features marked for removal
- **Removed** - Removed functionality
- **Security** - Security-related updates

**Internal Section:**
- **Internal** - Tooling, refactoring, CI/CD, documentation, test improvements

**Note:** GitHub releases will only show user-facing sections (not Internal). The Internal section is for developers viewing CHANGELOG.md directly.

### Example Workflow

After implementing a new feature:
```bash
# Make your code changes
git add .

# Update CHANGELOG.md [Unreleased] section with your changes
# Then commit everything together
git commit -m "Add repository filtering by author"
```

The commit message doesn't need special footers - just update CHANGELOG.md as part of your commit.

## GitHub Releases

### Release Process Overview

The release process is automated through GitHub Actions. Follow these steps:

1. **Review CHANGELOG.md**: Ensure the `[Unreleased]` section is complete and accurate
2. **Rename Unreleased Section**: Change `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`
3. **Add New Unreleased Section**: Add a fresh `[Unreleased]` section at the top with empty subsections
4. **Bump Version**: Run `scripts/bump_version.sh` with the new version number
5. **Commit and Tag**: Commit CHANGELOG.md and Info.plist, then create and push the tag
6. **GitHub Actions**: The workflow will automatically build and create the release

### Example Release Process

```bash
# 1. Review and finalize the [Unreleased] section in CHANGELOG.md
# 2. Rename [Unreleased] to [0.3.0] - 2025-11-08 (or whatever version/date)
# 3. Add fresh [Unreleased] section at top

# 4. Bump the version
./scripts/bump_version.sh 0.3.0

# 5. Commit and tag
git add CHANGELOG.md Info.plist
git commit -m "Bump version to 0.3.0"
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin main
git push origin v0.3.0
```

The GitHub Actions workflow will then automatically build and publish the release.

### Release Notes Automation

The GitHub Actions workflow at `.github/workflows/release.yml` automatically:
1. Extracts the author's note from `.github/RELEASE_NOTES_TEMPLATE.md`
2. Pulls the version-specific section from CHANGELOG.md
3. Combines them into the GitHub release description
4. Adds installation instructions

**Important**: The author's note from RELEASE_NOTES_TEMPLATE.md MUST be included in every release, and this is now handled automatically by the workflow.

### Helper Scripts

- `scripts/bump_version.sh` - Updates version in Info.plist and validates CHANGELOG
- `scripts/build_release.sh` - Builds the release package (used by CI)
