import SwiftUI
import AppKit

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
        // Initialize the menu bar controller, which sets up the status item
        // and begins fetching PR data
        menuBarController = MenuBarController()
    }
}
