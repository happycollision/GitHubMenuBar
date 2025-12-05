import Foundation
import ServiceManagement

/// Manages the app's login item (launch at login) state using SMAppService.
///
/// This class provides a simple interface to query and set the app's login item
/// status without requiring UserDefaults storage - it queries the system directly.
@MainActor
class LoginItemManager {
    /// Shared singleton instance
    static let shared = LoginItemManager()

    private init() {}

    /// Whether the app is currently registered to launch at login.
    ///
    /// This queries the system directly rather than storing state locally,
    /// ensuring accuracy even if the user changes settings via System Settings.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enables or disables launch at login.
    ///
    /// - Parameter enabled: Whether to enable launch at login
    /// - Throws: An error if the registration/unregistration fails
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Human-readable status message for debugging/logging
    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return "Not registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires user approval in System Settings"
        case .notFound:
            return "App not found (may be running from Xcode)"
        @unknown default:
            return "Unknown status"
        }
    }
}
