import AppKit
import SwiftUI

/// Custom window subclass that ensures proper first responder handling for SwiftUI content
private class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Controller for the settings window.
///
/// This class manages:
/// - NSWindow that displays the settings dialog
/// - Singleton pattern to ensure only one settings window exists
/// - Window lifecycle (showing, hiding, bringing to front)
/// - Hosting SwiftUI SettingsView in an NSWindow
@MainActor
class SettingsWindowController {
    // MARK: - Singleton

    static let shared = SettingsWindowController()

    // MARK: - Properties

    /// The settings window
    private var window: NSWindow?

    /// The window delegate (stored strongly to prevent deallocation)
    private var windowDelegate: WindowDelegate?

    /// Callback to trigger refresh when settings change
    var onSettingsChanged: (() -> Void)?

    // MARK: - Initialization

    private init() {
        // Private to enforce singleton
    }

    // MARK: - Window Management

    /// Shows the settings window, creating it if needed.
    ///
    /// If the window already exists, brings it to the front and focuses it.
    /// If it doesn't exist, creates a new window with the SettingsView.
    func showSettings() {
        // Temporarily change activation policy to .regular to enable keyboard input
        // LSUIElement apps (.accessory policy) don't properly handle keyboard events in windows
        NSApp.setActivationPolicy(.regular)

        if let existingWindow = window {
            // Window exists, bring it to front
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Create new window
            let settingsView = SettingsView(onSettingsChanged: onSettingsChanged)
            let hostingController = NSHostingController(rootView: settingsView)

            // Use custom KeyWindow class for proper first responder handling
            let window = KeyWindow(
                contentRect: NSRect(x: 0, y: 0, width: 490, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "GitHub PR Reviews - Settings"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false

            // Set minimum size to prevent window from being too small
            window.minSize = NSSize(width: 490, height: 500)

            // Use normal window level for proper keyboard focus
            window.level = .normal

            // Set delegate to handle window close
            let delegate = WindowDelegate(controller: self)
            window.delegate = delegate
            self.windowDelegate = delegate

            self.window = window

            // Make window key and activate app
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Force the window to accept first responder
            DispatchQueue.main.async {
                window.makeFirstResponder(hostingController.view)
            }
        }
    }

    /// Closes the settings window if it's open.
    func closeSettings() {
        window?.close()
        // Don't nil out the window here, let the delegate handle it
    }

    // MARK: - Window Delegate

    /// Internal delegate to handle window lifecycle events
    private class WindowDelegate: NSObject, NSWindowDelegate {
        weak var controller: SettingsWindowController?

        init(controller: SettingsWindowController) {
            self.controller = controller
        }

        func windowWillClose(_ notification: Notification) {
            // Clear the window and delegate references when user closes it
            controller?.window = nil
            controller?.windowDelegate = nil

            // Restore accessory activation policy to hide from Dock
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
