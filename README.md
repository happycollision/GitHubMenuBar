# GitHub Menu Bar

A lightweight macOS menu bar application that monitors GitHub pull requests where you've been requested as a reviewer.

## Features

- **Menu Bar Integration**: Displays as an icon in your macOS menu bar with a badge count of pending reviews
- **Real-time Updates**: Automatically refreshes every 5 minutes to fetch new review requests
- **Quick Access**: Click any PR to open it directly in your default browser
- **Manual Refresh**: Force refresh at any time from the menu
- **GitHub CLI Integration**: Uses the `gh` CLI for authentication, so no additional setup needed if you're already authenticated

## Prerequisites

Before building and running this app, you need to have:

1. **macOS 13.0 (Ventura) or later**
2. **Xcode** (for building the app)
3. **GitHub CLI (`gh`)**: Install and authenticate

### Installing and Authenticating GitHub CLI

```bash
# Install gh (if not already installed)
brew install gh

# Authenticate with GitHub
gh auth login
```

Follow the prompts to authenticate with your GitHub account.

## Building from Source

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

6. Use "Quit" to close the app

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

## Sharing with Coworkers

To share this app with your coworkers:

1. **Share the source code**: They can clone this repository and build it themselves following the instructions above

2. **Share a built app**: You can build the app and share the `.app` bundle (see "Creating a Standalone App Bundle" above). However, note that they may need to:
   - Right-click the app and select "Open" the first time (macOS Gatekeeper)
   - Have the GitHub CLI installed and authenticated

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
