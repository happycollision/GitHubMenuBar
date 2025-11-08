import SwiftUI
import AppKit

/// Custom NSApplication subclass that handles keyboard shortcuts for LSUIElement apps.
///
/// Menu bar apps with LSUIElement=true don't activate normally, which breaks standard
/// keyboard shortcuts in text fields. This subclass intercepts keyboard events and
/// routes them to the appropriate text editing actions.
class MenuBarApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Handle Command key combinations
            if event.modifierFlags.contains(.command) {
                guard let key = event.charactersIgnoringModifiers else {
                    return super.sendEvent(event)
                }

                // Handle Command+Shift combinations
                if event.modifierFlags.contains(.shift) {
                    if key.uppercased() == "Z" {
                        if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return }
                    }
                } else {
                    // Handle single Command key combinations
                    switch key.lowercased() {
                    case "x":
                        if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return }
                    case "c":
                        if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return }
                    case "v":
                        if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return }
                    case "z":
                        if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return }
                    case "a":
                        if NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: self) { return }
                    default:
                        break
                    }
                }
            }
        }
        super.sendEvent(event)
    }
}

/// Main application entry point for the GitHub Menu Bar app.
///
/// This app uses SwiftUI's App lifecycle but integrates with AppKit for menu bar functionality.
/// The app is configured as a menu bar-only app (LSUIElement=true in Info.plist), so it has
/// no dock icon and only appears in the system menu bar.
@main
struct GitHubMenuBar: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene is required by SwiftUI App lifecycle, but we use EmptyView
        // since all UI is handled through the NSStatusBar in MenuBarController
        Settings {
            EmptyView()
        }
    }
}

/// Application delegate that initializes the menu bar controller.
///
/// The menu bar functionality is handled by MenuBarController, which manages the
/// NSStatusItem and all user interactions.
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize ProfileManager and load active profile settings
        Task { @MainActor in
            let profileManager = ProfileManager.shared
            profileManager.loadProfiles()

            // Load active profile into AppSettings
            if let activeProfile = profileManager.getProfile(name: profileManager.activeProfileName) {
                AppSettings.shared.applySnapshot(activeProfile.settings)
                print("[AppDelegate] Loaded active profile: \(profileManager.activeProfileName)")
            }

            // Initialize the menu bar controller, which sets up the status item
            // and begins fetching PR data
            menuBarController = MenuBarController()

            // Setup Edit menu for keyboard shortcuts (required for LSUIElement apps)
            setupEditMenu()
        }
    }

    /// Creates an Edit menu to enable keyboard shortcuts in menu bar apps.
    ///
    /// Menu bar apps (LSUIElement=true) don't show the standard menu bar, which breaks
    /// keyboard shortcuts like Cmd+V for paste. This method programmatically creates
    /// an Edit menu with standard actions to restore keyboard shortcut functionality.
    @MainActor
    private func setupEditMenu() {
        let mainMenu = NSMenu()

        // Edit menu
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = NSMenu(title: "Edit")

        // Add standard Edit menu items with keyboard shortcuts
        // Use Selector syntax for standard responder chain actions
        editMenuItem.submenu?.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenuItem.submenu?.addItem(NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenuItem.submenu?.addItem(NSMenuItem.separator())
        editMenuItem.submenu?.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenuItem.submenu?.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenuItem.submenu?.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenuItem.submenu?.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenuItem.submenu?.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }
}
