# Release Process

This document describes how to create a new release of GitHubMenuBar.

## Overview

Releases are automated via GitHub Actions. When you push a version tag, GitHub Actions will:
1. Build the app using the build script
2. Create a GitHub release with auto-generated changelog
3. Upload the ZIP file as a release asset

## Prerequisites

- Commit all changes and ensure the `main` branch is clean
- Update version number in `Info.plist`
- Ensure the app builds locally: `./scripts/build_release.sh`

## Release Steps

### 1. Update Version Number

Edit `Info.plist` and update the version:

```xml
<key>CFBundleShortVersionString</key>
<string>0.1.0</string>
```

You can also use the version bump script:

```bash
./scripts/bump_version.sh 0.1.0
```

### 2. Commit Version Change

```bash
git add Info.plist
git commit -m "Bump version to 0.1.0"
git push origin main
```

### 3. Create and Push Tag

```bash
# Create an annotated tag
git tag -a v0.1.0 -m "Release v0.1.0"

# Push the tag to GitHub
git push origin v0.1.0
```

**That's it!** GitHub Actions will automatically:
- Build the app
- Create a GitHub release
- Upload `GitHubMenuBar.zip` as a release asset
- Generate release notes from commits since the last tag

## Testing a Release Locally

Before creating an official release, you can test the build process:

```bash
# Build locally
./scripts/build_release.sh

# Test the built app
open dist/GitHubMenuBar.app

# Test the ZIP
unzip -q dist/GitHubMenuBar.zip -d /tmp/test
open /tmp/test/GitHubMenuBar.app
```

## Versioning Scheme

We use [Semantic Versioning](https://semver.org/):
- **Major** (1.x.x): Breaking changes or major new features
- **Minor** (x.1.x): New features, backward compatible
- **Patch** (x.x.1): Bug fixes, backward compatible

**Note**: Starting at 0.0.0 indicates the project is in initial development. Version 1.0.0 will be released when the API is considered stable.

## Troubleshooting

### Build Fails in GitHub Actions

1. Check the Actions log: https://github.com/dondenton/GitHubMenuBar/actions
2. Common issues:
   - Swift version mismatch (update `.github/workflows/release.yml`)
   - Build script not executable (ensure `chmod +x scripts/build_release.sh`)

### Release Not Created

- Ensure you pushed the tag: `git push origin v0.1.0`
- Check that the tag starts with `v` (required by workflow)
- Verify GitHub Actions is enabled for the repository

### ZIP File Not Attached

- Check GitHub Actions permissions: Repository Settings → Actions → General → Workflow permissions
- Ensure "Read and write permissions" is enabled

## Rolling Back a Release

If you need to remove a bad release:

```bash
# Delete the GitHub release (via web UI or gh CLI)
gh release delete v0.1.0

# Delete the tag locally and remotely
git tag -d v0.1.0
git push --delete origin v0.1.0
```

Then fix the issue and create a new release with a patch version (e.g., v0.1.1).

## Pre-releases

To create a pre-release (beta, alpha, etc.):

```bash
# Tag with pre-release suffix
git tag -a v0.1.0-beta.1 -m "Pre-release v0.1.0-beta.1"
git push origin v0.1.0-beta.1
```

Edit the GitHub release and mark it as "Pre-release" in the web UI.

## Release Checklist

Before creating a release:

- [ ] All tests pass locally
- [ ] Version updated in `Info.plist`
- [ ] Build script runs successfully
- [ ] App works when run from `dist/` directory
- [ ] Changelog/release notes drafted
- [ ] All changes committed and pushed to `main`
- [ ] Tag created and pushed
- [ ] GitHub release created automatically
