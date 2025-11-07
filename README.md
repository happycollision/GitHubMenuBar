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

### Download Pre-built Release (Recommended)

1. **Download the latest release**:
   - Go to the [Releases page](https://github.com/dondenton/GitHubMenuBar/releases)
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

1. **Use pre-built releases** (easiest): Download from the [Releases page](https://github.com/dondenton/GitHubMenuBar/releases)
2. **Build from source**: Clone the repository and follow the build instructions above

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
└── Info.plist                 # macOS app configuration
```

## License

This project is provided as-is for use within your organization.

## Requirements

- macOS 13.0+
- Swift 6.2+
- GitHub CLI (`gh`)
