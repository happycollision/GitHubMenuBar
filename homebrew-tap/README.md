# Homebrew Tap for GitHubMenuBar

This directory contains the Homebrew Cask formula for GitHubMenuBar.

## Setup Instructions

### 1. Create a Separate GitHub Repository

Homebrew taps must be in their own repository. Create a new repo named `homebrew-tap`:

```bash
# On GitHub, create a new repository: dondenton/homebrew-tap
# Then locally:
cd ~/GitProjects  # or wherever you keep repos
mkdir homebrew-tap
cd homebrew-tap
git init
mkdir -p Casks
```

### 2. Copy the Cask Formula

Copy the Cask formula from this directory:

```bash
cp /path/to/GitHubMenuBar/homebrew-tap/Casks/github-menubar.rb Casks/
```

### 3. Update SHA256 After First Release

After creating your first GitHub release (v0.1.0):

```bash
# Download the release ZIP
curl -L -o GitHubMenuBar.zip https://github.com/dondenton/GitHubMenuBar/releases/download/v0.1.0/GitHubMenuBar.zip

# Calculate SHA256
shasum -a 256 GitHubMenuBar.zip

# Update the sha256 value in Casks/github-menubar.rb
```

### 4. Commit and Push

```bash
git add Casks/github-menubar.rb
git commit -m "Add GitHubMenuBar cask"
git remote add origin https://github.com/dondenton/homebrew-tap.git
git push -u origin main
```

### 5. Test Installation

```bash
# Add your tap
brew tap dondenton/tap

# Install the cask
brew install --cask github-menubar

# Or users can do both in one command:
brew install --cask dondenton/tap/github-menubar
```

## Updating for New Releases

When you release a new version:

1. Update the `version` in `Casks/github-menubar.rb`
2. Download the new release ZIP and calculate its SHA256
3. Update the `sha256` in the formula
4. Commit and push to the homebrew-tap repository

```bash
# Example for v0.2.0
VERSION="0.2.0"
curl -L -o GitHubMenuBar.zip "https://github.com/dondenton/GitHubMenuBar/releases/download/v${VERSION}/GitHubMenuBar.zip"
shasum -a 256 GitHubMenuBar.zip
# Copy the hash, update the formula, then:
git commit -am "Update to v${VERSION}"
git push
```

## Testing Locally

Before pushing, test the formula locally:

```bash
brew install --cask --debug Casks/github-menubar.rb
```

## Resources

- [Homebrew Cask Documentation](https://docs.brew.sh/Cask-Cookbook)
- [Creating a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
