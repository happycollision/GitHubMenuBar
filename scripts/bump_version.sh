#!/bin/bash

# Version Bump Script for GitHubMenuBar
# Updates the version number in Info.plist

set -e

# Check if version argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.1.0"
    exit 1
fi

NEW_VERSION="$1"
INFO_PLIST="Info.plist"

# Validate version format (basic check)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "❌ Error: Invalid version format"
    echo "   Expected: MAJOR.MINOR.PATCH (e.g., 1.2.3)"
    echo "   Or: MAJOR.MINOR.PATCH-PRERELEASE (e.g., 1.2.3-beta.1)"
    exit 1
fi

# Check if Info.plist exists
if [ ! -f "$INFO_PLIST" ]; then
    echo "❌ Error: Info.plist not found in current directory"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(defaults read "$(pwd)/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")

echo "📝 Updating version in Info.plist"
echo "   Current: $CURRENT_VERSION"
echo "   New: $NEW_VERSION"

# Update CFBundleShortVersionString
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"

# Update CFBundleVersion (build number) to match
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST"

echo "✅ Version updated successfully!"
echo ""

# Validate that CHANGELOG.md has an entry for this version
echo "🔍 Checking CHANGELOG.md for version $NEW_VERSION..."
if ! grep -q "^## \[$NEW_VERSION\]" CHANGELOG.md; then
    echo "⚠️  Warning: CHANGELOG.md does not have an entry for version $NEW_VERSION"
    echo ""
    echo "Please rename the [Unreleased] section to [$NEW_VERSION] - $(date +%Y-%m-%d)"
    echo "Then add a fresh [Unreleased] section at the top."
    echo ""
    echo "After updating CHANGELOG.md, re-run this script."
    exit 1
fi

# Check if the changelog entry is just a placeholder
# Extract content between this version and the next version header (or end of file)
CHANGELOG_CONTENT=$(awk -v version="$NEW_VERSION" '
    /^## \['"$NEW_VERSION"'\]/ { found=1; next }
    found && /^## \[/ { exit }
    found && NF > 0 { print; has_content=1 }
    END { if (!has_content) exit 1 }
' CHANGELOG.md)
if [ $? -ne 0 ] || [ -z "$CHANGELOG_CONTENT" ]; then
    echo "⚠️  Warning: CHANGELOG.md entry for $NEW_VERSION appears to be empty"
    echo ""
    echo "Please add release notes to CHANGELOG.md before creating the release."
    exit 1
fi

echo "✅ CHANGELOG.md entry found for version $NEW_VERSION"
echo ""
echo "Next steps:"
echo "1. Review the changes: git diff Info.plist"
echo "2. Commit the version change:"
echo "   git add Info.plist CHANGELOG.md"
echo "   git commit -m \"Bump version to $NEW_VERSION\""
echo "3. Create and push a tag:"
echo "   git tag -a v$NEW_VERSION -m \"Release v$NEW_VERSION\""
echo "   git push origin main"
echo "   git push origin v$NEW_VERSION"
echo ""
echo "The GitHub Actions workflow will automatically build and create the release."
