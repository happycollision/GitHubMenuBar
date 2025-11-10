> A note from "the author". This note you are reading is the only code I manually contributed to this repo. I've never looked at a single file, only diffs presented to me from Claude Code. So you need to ask yourself if you trust me and also if you trust Claude Code before you download, install, and run this thing. Mostly if you trust Claude Code, honestly. I am really just the the VP of Product for this thing: technically knowledgeable, but not necessarily about this language or this codebase in particular. (I've literally never hand-coded a lick of Swift in my life so far.)
> 
> But this toolbar app sure does scratch an itch that I personally have.

# GitHub Menu Bar

A lightweight macOS menu bar application that monitors GitHub pull requests where you've been requested as a reviewer.

## Features

- **Menu Bar Integration**: Displays as an icon in your macOS menu bar with a badge count of pending reviews
- **Real-time Updates**: Automatically refreshes every 5 minutes to fetch new review requests
- **Quick Access**: Click any PR to open it directly in your default browser
- **Manual Refresh**: Force refresh at any time from the menu
- **Status Filtering**: Filter PRs by status (Open, Draft, Merged, Closed) - defaults to showing only Open and Draft PRs
- **GitHub CLI Integration**: Uses the `gh` CLI for authentication, so no additional setup needed if you're already authenticated

## Installation

### Quick Install (Recommended)

**YOLO mode (full auto install):**

```bash
curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash -s -- --yolo
```

This will:
- Download and extract the latest release
- Remove quarantine attributes (allows unsigned app to launch normally)
- Move to `/Applications` folder (requires admin privileges)
- Check for GitHub CLI and prompt if not installed

Equivalent to using `--remove-quarantine --move-to-applications` flags.

**Note:** Moving to `/Applications` works automatically for admin users on macOS. If you're not an admin user, use the conservative installation method instead.

**Conservative installation (you handle the final steps):**

```bash
curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash
```

This will download and extract only. You'll need to:
1. Manually copy the app to `/Applications`
2. Right-click and select "Open" on first launch (unsigned app)

**Security note:** The installer is [open source and versioned in this repo](install.sh) - review it before running. The `--remove-quarantine` flag runs `xattr -cr` to tell macOS to trust this specific app (doesn't affect system-wide security). The `--move-to-applications` flag moves the app to `/Applications`.

**More Options:**

```bash
# List all available versions (no installation)
curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash -s -- --list-versions

# Install specific version (YOLO mode)
curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash -s -- --version v0.3.0 --yolo

# Full installation with explicit flags (same as --yolo)
curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash -s -- --remove-quarantine --move-to-applications

# Show all options
curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash -s -- --help
```

### Manual Installation

1. **Download the latest release**:
   - Go to the [Releases page](https://github.com/happycollision/GitHubMenuBar/releases)
   - Download `GitHubMenuBar.zip`

2. **Extract and install**:
   - Extract the ZIP file
   - Move `GitHubMenuBar.app` to your `/Applications` folder

3. **First launch** (unsigned app):
   - Right-click the app and select **Open**
   - Click **Open** in the security dialog
   - Alternatively, run: `xattr -cr /Applications/GitHubMenuBar.app`

4. **Install and authenticate GitHub CLI**:
   ```bash
   brew install gh
   gh auth login
   ```

## Prerequisites

To run this app, you need:

1. **macOS 13.0 (Ventura) or later**
2. **GitHub CLI (`gh`)**: Install and authenticate

### Installing and Authenticating GitHub CLI

```bash
# Install gh (if not already installed)
brew install gh

# Authenticate with GitHub
gh auth login
```

Follow the prompts to authenticate with your GitHub account.

## Building from Source

If you prefer to build from source instead of using a pre-built release:

### Prerequisites for Building

1. **macOS 13.0 (Ventura) or later**
2. **Xcode** (for building the app)
3. **Swift 6.2+**

### Option 1: Command Line Build

```bash
# Clone or navigate to the project directory
cd GitHubMenuBar

# Build the project
swift build -c release

# The executable will be at:
# .build/release/GitHubMenuBar
```

### Option 2: Build with Xcode (Recommended for Menu Bar App)

1. Open the project in Xcode:
   ```bash
   open Package.swift
   ```

2. In Xcode, select the `GitHubMenuBar` scheme

3. Build and run the project (⌘R)

   **Note**: When running from Xcode, you'll see the menu bar icon appear in your system menu bar

### Creating a Standalone App Bundle

To create a proper `.app` bundle that you can copy to your Applications folder:

1. Open the project in Xcode: `open Package.swift`

2. Go to **Product** → **Archive**

3. Once the archive is complete, click **Distribute App** → **Copy App**

4. Save the app bundle to a location of your choice

5. Copy `GitHubMenuBar.app` to your `/Applications` folder

6. **Important**: To make the app a menu bar-only app (no dock icon), you need to modify the Info.plist:
   - Right-click on `GitHubMenuBar.app` and select **Show Package Contents**
   - Navigate to `Contents/`
   - Open `Info.plist` in a text editor
   - Add the following key:
     ```xml
     <key>LSUIElement</key>
     <true/>
     ```
   - Save the file

   Alternatively, use the `Info.plist` file included in the repository as a reference.

## Running the App

1. Launch the app (double-click or run from Xcode)

2. Look for the list icon in your menu bar (top-right area)

3. Click the icon to see your pending PR reviews

4. Click any PR to open it in your browser

5. Use the "Refresh" option to manually update the list

6. Use "Filter by Status" to customize which PR statuses are shown (see below)

7. Use "Quit" to close the app

## Filtering by Status

The app allows you to filter which PRs are displayed based on their status:

1. Click the menu bar icon to open the menu

2. Navigate to **Filter by Status** at the bottom of the menu

3. Check or uncheck the status types you want to see:
   - **Open**: Non-draft open PRs
   - **Draft**: Draft PRs (subset of open PRs)
   - **Merged**: PRs that have been merged
   - **Closed**: PRs that were closed without merging

4. Changes are saved automatically and persist across app restarts

5. The PR list will refresh immediately to show only the selected statuses

**Default behavior**: By default, the app shows only **Open** and **Draft** PRs (excludes Merged and Closed). This keeps the menu focused on actionable review requests.

## How It Works

The app works by:

1. Checking if `gh` CLI is installed and authenticated
2. Running `gh pr list --search "review-requested:@me"` to fetch PRs
3. Parsing the JSON output to display in the menu
4. Refreshing the data every 5 minutes automatically
5. Opening PR URLs in your default browser when clicked

## Troubleshooting

### "GitHub CLI (gh) is not installed"

Install the GitHub CLI:
```bash
brew install gh
```

### "Not authenticated with GitHub"

Authenticate with GitHub:
```bash
gh auth login
```

### The app doesn't appear in the menu bar

- Make sure you've built and run the app
- Check if `LSUIElement` is set to `true` in the Info.plist
- Try restarting the app

### No PRs showing up

- Verify you have pending review requests: `gh pr list --search "review-requested:@me"`
- Check your GitHub notifications to confirm you have review requests
- Try the "Refresh" option in the menu

## Sharing with Others

Simply direct them to this repository! They can:

1. **Use the installer** (easiest):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/happycollision/GitHubMenuBar/main/install.sh | bash -s -- --yolo
   ```
2. **Use pre-built releases**: Download from the [Releases page](https://github.com/happycollision/GitHubMenuBar/releases)
3. **Build from source**: Clone the repository and follow the build instructions above

All users will need to have the GitHub CLI installed and authenticated.

## Development

The project structure:

```
GitHubMenuBar/
├── Package.swift              # Swift Package Manager configuration
├── Sources/
│   └── GitHubMenuBar/
│       ├── GitHubMenuBar.swift       # Main app entry point
│       ├── Models.swift              # Data models for PRs
│       ├── GitHubService.swift       # GitHub CLI integration
│       └── MenuBarController.swift   # Menu bar UI logic
├── Tests/
│   └── GitHubMenuBarTests/
│       ├── ModelsTests.swift         # Unit tests for models
│       ├── AppSettingsTests.swift    # Unit tests for settings
│       └── IntegrationTests.swift    # Integration tests
├── icons/
│   ├── GithubMenuBar.icon/    # Source Liquid Glass icon (requires Xcode)
│   └── AppIcon.png            # Exported PNG for CI builds
├── scripts/
│   └── build_release.sh       # Build and package script
├── Info.plist                 # macOS app configuration
└── TESTING.md                 # Testing guide and documentation
```

### App Icon Workflow

The app uses Apple's new Liquid Glass icon format (`.icon`), but since this project is built with Swift Package Manager (not Xcode), we can't use the `.icon` format directly in CI/CD pipelines.

**Current Workflow:**
1. **Source**: `icons/GithubMenuBar.icon/` - The original Liquid Glass icon created with [Icon Composer](https://developer.apple.com/icon-composer/)
2. **Build-ready**: `icons/AppIcon.png` - A 1024x1024 PNG export of the icon
3. **CI/CD**: The build script (`scripts/build_release.sh`) automatically generates an `.icns` file from the PNG using native macOS tools (`sips` and `iconutil`)

**To update the app icon:**
1. Edit the icon in Icon Composer (opens `icons/GithubMenuBar.icon/`)
2. Export a new 1024x1024 PNG as `icons/AppIcon.png`
3. Commit both files to the repository
4. The build script will automatically generate the `.icns` file

**Future Improvement:**
Once Apple provides CLI tools to compile `.icon` bundles directly (or when the project moves to Xcode), we can use the Liquid Glass icon format with all its dynamic effects. Until then, the PNG-based workflow ensures CI/CD compatibility while maintaining the source `.icon` file for future use.

### Testing

The project includes comprehensive unit and integration tests:

```bash
# Run all tests (38 tests)
swift test

# Run specific test suite
swift test --filter ModelsTests
swift test --filter AppSettingsTests
swift test --filter IntegrationTests
```

**Test Coverage:**
- ✅ 38 automated tests covering business logic
- ✅ PR filtering, sorting, and grouping
- ✅ Settings management and persistence
- ✅ Model serialization and data transformations
- ✅ Fast execution (< 0.1 seconds)

For detailed testing documentation, see [TESTING.md](TESTING.md).

## License

This project is provided as-is for use within your organization.

## Requirements

- macOS 13.0+
- Swift 6.2+
- GitHub CLI (`gh`)
