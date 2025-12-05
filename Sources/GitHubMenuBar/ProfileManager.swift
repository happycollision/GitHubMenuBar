import Foundation

/// Manages profile persistence, switching, and export/import operations
///
/// This singleton class handles all profile operations including:
/// - Loading and saving profiles to JSON
/// - Managing the hardcoded Default profile
/// - Tracking unsaved changes
/// - Profile switching with in-memory change preservation
/// - Export/import functionality
@MainActor
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    // MARK: - Published Properties (for SwiftUI reactivity)

    @Published private(set) var activeProfileName: String = "Default"
    @Published private(set) var hasUnsavedChanges: Bool = false
    @Published private(set) var availableProfiles: [String] = ["Default"]

    // MARK: - Private Properties

    private var container: ProfilesContainer
    private let fileManager = FileManager.default
    private var profilesFileURL: URL
    private var pendingChanges: [String: ProfileSettings] = [:]

    // MARK: - Initialization

    private init() {
        // Determine profiles.json location
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("GitHubMenuBar", isDirectory: true)
        self.profilesFileURL = appDirectory.appendingPathComponent("profiles.json")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        // Initialize with empty container (will load in loadProfiles)
        self.container = ProfilesContainer()

        // Load profiles from disk
        loadProfiles()
    }

    // MARK: - Hardcoded Default Profile

    /// Creates and returns the hardcoded Default profile
    /// This profile is never stored in JSON and is always available
    /// Note: groupByRepo, reverseClickBehavior, and refreshIntervalMinutes are global settings,
    /// not stored in profiles.
    static func createDefaultProfile() -> Profile {
        Profile(
            name: "Default",
            isDefault: true,
            createdAt: Date.distantPast,
            modifiedAt: Date.distantPast,
            settings: ProfileSettings(
                excludedStatuses: ["MERGED", "CLOSED"],
                excludedReviewDecisions: [],
                repoFilterEnabled: false,
                repoFilterMode: "blacklist",
                whitelistedRepositories: [],
                blacklistedRepositories: [],
                authorFilterEnabled: true,
                authorFilterMode: "blacklist",
                whitelistedAuthors: [],
                blacklistedAuthors: ["dependabot", "dependabot[bot]"]
            )
        )
    }

    // MARK: - Profile Loading and Saving

    /// Load profiles from JSON file
    /// Creates an empty container if file doesn't exist or is corrupted
    func loadProfiles() {
        guard fileManager.fileExists(atPath: profilesFileURL.path) else {
            print("[ProfileManager] No profiles.json found, creating empty container")
            container = ProfilesContainer(version: 1, activeProfile: "Default", profiles: [:])
            saveProfiles()
            updatePublishedState()
            return
        }

        do {
            let data = try Data(contentsOf: profilesFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            container = try decoder.decode(ProfilesContainer.self, from: data)

            // Verify active profile exists
            if let active = container.activeProfile {
                if active.lowercased() != "default" && container.profiles[active] == nil {
                    print("[ProfileManager] Active profile '\(active)' not found, falling back to Default")
                    container.activeProfile = "Default"
                    saveProfiles()
                }
            } else {
                container.activeProfile = "Default"
            }

            activeProfileName = container.activeProfile ?? "Default"
            updatePublishedState()
            print("[ProfileManager] Loaded \(container.profiles.count) profile(s)")
        } catch {
            print("[ProfileManager] Failed to load profiles.json: \(error). Creating empty container.")
            container = ProfilesContainer(version: 1, activeProfile: "Default", profiles: [:])
            saveProfiles()
            updatePublishedState()
        }
    }

    /// Save profiles to JSON file (atomic write, never includes Default)
    func saveProfiles() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(container)
            try data.write(to: profilesFileURL, options: .atomic)
            print("[ProfileManager] Saved \(container.profiles.count) profile(s) to disk")
        } catch {
            print("[ProfileManager] Failed to save profiles: \(error)")
        }
    }

    // MARK: - Profile Queries

    /// Get a profile by name (checks Default first, then user profiles)
    func getProfile(name: String) -> Profile? {
        if name.lowercased() == "default" {
            return Self.createDefaultProfile()
        }
        return container.profiles[name]
    }

    /// Get all profile names (Default always first, then user profiles)
    func getAllProfileNames() -> [String] {
        var names = ["Default"]
        names.append(contentsOf: container.profiles.keys.sorted())
        return names
    }

    /// Get the currently active profile name
    func getActiveProfileName() -> String? {
        return activeProfileName
    }

    // MARK: - Profile Mutations

    /// Set the active profile name and save to disk
    func setActiveProfile(name: String) {
        container.activeProfile = name
        activeProfileName = name
        saveProfiles()
        updatePublishedState()
    }

    /// Save or update a profile (prevents modification of Default)
    func saveProfile(name: String, settings: ProfileSettings) throws {
        guard validateProfileName(name) else {
            throw ProfileError.invalidProfileName
        }

        guard name.lowercased() != "default" else {
            throw ProfileError.cannotModifyDefault
        }

        let now = Date()
        if var existingProfile = container.profiles[name] {
            // Update existing profile
            existingProfile.settings = settings
            existingProfile.modifiedAt = now
            container.profiles[name] = existingProfile
        } else {
            // Create new profile
            let profile = Profile(
                name: name,
                isDefault: false,
                createdAt: now,
                modifiedAt: now,
                settings: settings
            )
            container.profiles[name] = profile
        }

        saveProfiles()
        updatePublishedState()
        print("[ProfileManager] Saved profile '\(name)'")
    }

    /// Delete a profile (prevents deletion of Default)
    func deleteProfile(name: String) throws {
        guard name.lowercased() != "default" else {
            throw ProfileError.cannotDeleteDefault
        }

        guard container.profiles[name] != nil else {
            throw ProfileError.profileNotFound
        }

        container.profiles.removeValue(forKey: name)

        // Clear pending changes for this profile
        pendingChanges.removeValue(forKey: name)

        // If this was the active profile, switch to Default
        if activeProfileName == name {
            activeProfileName = "Default"
            container.activeProfile = "Default"
        }

        saveProfiles()
        updatePublishedState()
        print("[ProfileManager] Deleted profile '\(name)'")
    }

    /// Rename a profile (prevents renaming Default or to Default)
    func renameProfile(oldName: String, newName: String) throws {
        guard oldName.lowercased() != "default" else {
            throw ProfileError.cannotRenameDefault
        }

        guard newName.lowercased() != "default" else {
            throw ProfileError.cannotRenameDefault
        }

        guard validateProfileName(newName) else {
            throw ProfileError.invalidProfileName
        }

        guard var profile = container.profiles[oldName] else {
            throw ProfileError.profileNotFound
        }

        guard container.profiles[newName] == nil else {
            throw ProfileError.profileAlreadyExists
        }

        // Update profile name and move to new key
        profile.name = newName
        profile.modifiedAt = Date()
        container.profiles.removeValue(forKey: oldName)
        container.profiles[newName] = profile

        // Update pending changes if present
        if let pending = pendingChanges[oldName] {
            pendingChanges.removeValue(forKey: oldName)
            pendingChanges[newName] = pending
        }

        // Update active profile if this was active
        if activeProfileName == oldName {
            activeProfileName = newName
            container.activeProfile = newName
        }

        saveProfiles()
        updatePublishedState()
        print("[ProfileManager] Renamed profile '\(oldName)' to '\(newName)'")
    }

    // MARK: - Profile Switching and Change Management

    /// Switch to a different profile (works for Default and user profiles)
    /// Implements hybrid switching: saves pending changes, loads new profile, restores pending if exists
    func switchToProfile(name: String, currentSettings: ProfileSettings) {
        // Store current changes if profile has been modified
        if activeProfileName != name {
            let currentProfile = getProfile(name: activeProfileName)
            if let currentProfile = currentProfile, currentSettings != currentProfile.settings {
                pendingChanges[activeProfileName] = currentSettings
                print("[ProfileManager] Stored pending changes for '\(activeProfileName)'")
            }
        }

        // Load new profile settings
        guard let newProfile = getProfile(name: name) else {
            print("[ProfileManager] Profile '\(name)' not found")
            return
        }

        // Check if new profile has pending changes
        let settingsToApply = pendingChanges[name] ?? newProfile.settings

        // Update active profile
        activeProfileName = name
        container.activeProfile = name
        saveProfiles()

        // Apply settings to AppSettings (silent mode to avoid triggering during comparison)
        AppSettings.shared.applySnapshot(settingsToApply, silent: true)

        updatePublishedState()

        // Post notification to update UI
        NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)

        print("[ProfileManager] Switched to profile '\(name)'")
    }

    /// Create a new profile from current settings
    func createProfileFromCurrentSettings(name: String, settings: ProfileSettings) throws {
        try saveProfile(name: name, settings: settings)

        // Switch to the newly created profile
        activeProfileName = name
        container.activeProfile = name

        // Clear any pending changes for this profile
        pendingChanges.removeValue(forKey: name)

        saveProfiles()
        updatePublishedState()
    }

    /// Check if current settings differ from active profile
    func hasUnsavedChanges(currentSettings: ProfileSettings) -> Bool {
        guard let activeProfile = getProfile(name: activeProfileName) else {
            return false
        }

        // Always compare against the saved profile settings
        // (pendingChanges is only for preserving state when switching profiles)
        return currentSettings != activeProfile.settings
    }

    /// Revert to the saved state of the active profile
    func revertToSaved() {
        guard let activeProfile = getProfile(name: activeProfileName) else {
            return
        }

        // Clear pending changes
        pendingChanges.removeValue(forKey: activeProfileName)

        // Reload profile settings (silent to avoid triggering change detection)
        AppSettings.shared.applySnapshot(activeProfile.settings, silent: true)

        updatePublishedState()

        // Now post notification to update UI
        NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)

        print("[ProfileManager] Reverted to saved state of '\(activeProfileName)'")
    }

    /// Update the active profile with current settings
    func updateActiveProfile(settings: ProfileSettings) throws {
        guard activeProfileName.lowercased() != "default" else {
            throw ProfileError.cannotModifyDefault
        }

        try saveProfile(name: activeProfileName, settings: settings)

        // Clear pending changes since we just saved
        pendingChanges.removeValue(forKey: activeProfileName)

        updatePublishedState()
    }

    // MARK: - Export/Import

    /// Export a single profile to a file
    func exportProfile(name: String, to url: URL) throws {
        guard let profile = getProfile(name: name) else {
            throw ProfileError.profileNotFound
        }

        guard name.lowercased() != "default" else {
            throw ProfileError.cannotExportDefault
        }

        let exportable = ExportableProfile(
            profile: profile,
            exportedAt: Date(),
            exportVersion: 1
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exportable)
        try data.write(to: url, options: .atomic)

        print("[ProfileManager] Exported profile '\(name)' to \(url.path)")
    }

    /// Export all user profiles to a file (Default not included)
    func exportAllProfiles(to url: URL) throws {
        let exportable = ExportableProfiles(
            profiles: container.profiles,
            exportedAt: Date(),
            exportVersion: 1
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exportable)
        try data.write(to: url, options: .atomic)

        print("[ProfileManager] Exported \(container.profiles.count) profile(s) to \(url.path)")
    }

    /// Import profiles from a file with conflict handling
    func importProfiles(
        from url: URL,
        conflictHandler: (String, Profile) -> ConflictResolution
    ) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Detect format: try single profile first, then full set
        var profilesToImport: [String: Profile] = [:]

        if let single = try? decoder.decode(ExportableProfile.self, from: data) {
            profilesToImport[single.profile.name] = single.profile
        } else if let multiple = try? decoder.decode(ExportableProfiles.self, from: data) {
            profilesToImport = multiple.profiles
        } else {
            throw ProfileError.invalidImportFormat
        }

        var imported: [String] = []
        var skipped: [String] = []
        var conflicts: [String] = []
        var errors: [String: Error] = [:]

        for (name, profile) in profilesToImport {
            // Validate profile
            guard validateProfileName(name) else {
                errors[name] = ProfileError.invalidProfileName
                continue
            }

            guard name.lowercased() != "default" else {
                errors[name] = ProfileError.cannotImportAsDefault
                continue
            }

            // Use profile settings as-is (validation for global settings is handled elsewhere)
            let validatedSettings = profile.settings

            // Check for conflict
            if container.profiles[name] != nil {
                conflicts.append(name)
                let resolution = conflictHandler(name, profile)

                switch resolution {
                case .skip:
                    skipped.append(name)
                    continue

                case .rename:
                    let newName = generateUniqueName(baseName: name)
                    var renamedProfile = profile
                    renamedProfile.name = newName
                    renamedProfile.settings = validatedSettings
                    container.profiles[newName] = renamedProfile
                    imported.append(newName)

                case .overwrite:
                    var updatedProfile = profile
                    updatedProfile.settings = validatedSettings
                    container.profiles[name] = updatedProfile
                    imported.append(name)
                }
            } else {
                // No conflict, import directly
                var updatedProfile = profile
                updatedProfile.settings = validatedSettings
                container.profiles[name] = updatedProfile
                imported.append(name)
            }
        }

        // Save if any profiles were imported
        if !imported.isEmpty {
            saveProfiles()
            updatePublishedState()
        }

        print("[ProfileManager] Import complete: \(imported.count) imported, \(skipped.count) skipped, \(errors.count) errors")

        return ImportResult(
            imported: imported,
            skipped: skipped,
            conflicts: conflicts,
            errors: errors
        )
    }

    // MARK: - Helper Methods

    /// Validate a profile name
    private func validateProfileName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.lowercased() != "default"
    }

    /// Generate a unique profile name by appending a number
    private func generateUniqueName(baseName: String) -> String {
        var counter = 2
        var candidateName = "\(baseName) \(counter)"

        while container.profiles[candidateName] != nil || candidateName.lowercased() == "default" {
            counter += 1
            candidateName = "\(baseName) \(counter)"
        }

        return candidateName
    }

    /// Update published properties for SwiftUI reactivity
    private func updatePublishedState() {
        availableProfiles = getAllProfileNames()
        hasUnsavedChanges = hasUnsavedChanges(currentSettings: AppSettings.shared.createSnapshot())
    }
}
