import SwiftUI

/// Profile management bar component displayed above the settings tabs
/// Provides profile switching, saving, and reverting functionality
struct ProfileManagementBar: View {
    // MARK: - State

    @ObservedObject var profileManager = ProfileManager.shared
    @State private var showingSaveDialog = false
    @State private var showingDeleteConfirmation = false
    @State private var newProfileName = ""
    @State private var errorMessage: String?
    @State private var localHasUnsavedChanges = false

    /// Callback to trigger refresh when settings change
    var onSettingsChanged: (() -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile dropdown with unsaved changes indicator
            HStack(spacing: 8) {
                Text("Active Profile:")
                    .font(.headline)

                Picker("", selection: Binding(
                    get: { profileManager.activeProfileName },
                    set: { newProfileName in
                        switchProfile(to: newProfileName)
                    }
                )) {
                    ForEach(profileManager.availableProfiles, id: \.self) { profileName in
                        Text(profileName).tag(profileName)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)

                // Asterisk indicator for unsaved changes
                if localHasUnsavedChanges {
                    Text("*")
                        .font(.headline)
                        .foregroundColor(.orange)
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 12) {
                // Update Profile button
                Button("Update Profile") {
                    updateCurrentProfile()
                }
                .disabled(!canUpdateProfile)
                .help(updateProfileTooltip)

                // Save New button
                Button("Save New") {
                    showingSaveDialog = true
                }
                .disabled(!localHasUnsavedChanges)
                .help("Create a new profile from current settings")

                // Revert button
                Button("Revert") {
                    revertChanges()
                }
                .disabled(!localHasUnsavedChanges)
                .help("Discard changes and reload active profile")

                Spacer()
            }

            Divider()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .onAppear {
            updateUnsavedChangesState()
            setupSettingsObserver()
        }
        .onChange(of: profileManager.hasUnsavedChanges) { _ in
            updateUnsavedChangesState()
        }
        // Save New Profile dialog
        .sheet(isPresented: $showingSaveDialog) {
            VStack(spacing: 16) {
                Text("Create New Profile")
                    .font(.headline)

                TextField("Profile Name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showingSaveDialog = false
                        newProfileName = ""
                        errorMessage = nil
                    }

                    Button("Save") {
                        saveNewProfile()
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 350)
        }
    }

    // MARK: - Computed Properties

    /// Whether the Update Profile button should be enabled
    private var canUpdateProfile: Bool {
        return localHasUnsavedChanges && profileManager.activeProfileName.lowercased() != "default"
    }

    /// Tooltip for Update Profile button
    private var updateProfileTooltip: String {
        if profileManager.activeProfileName.lowercased() == "default" {
            return "Cannot modify the Default profile"
        } else if !localHasUnsavedChanges {
            return "No changes to save"
        } else {
            return "Save changes to \(profileManager.activeProfileName)"
        }
    }

    // MARK: - Actions

    /// Setup observer for settings changes
    private func setupSettingsObserver() {
        NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.updateUnsavedChangesState()
            }
        }
    }

    /// Update the unsaved changes state by checking with ProfileManager
    private func updateUnsavedChangesState() {
        let currentSnapshot = AppSettings.shared.createSnapshot()
        localHasUnsavedChanges = profileManager.hasUnsavedChanges(currentSettings: currentSnapshot)
    }

    /// Switch to a different profile
    private func switchProfile(to newProfileName: String) {
        guard newProfileName != profileManager.activeProfileName else { return }

        let currentSnapshot = AppSettings.shared.createSnapshot()
        profileManager.switchToProfile(name: newProfileName, currentSettings: currentSnapshot)

        // Trigger refresh
        onSettingsChanged?()

        // Update local state
        updateUnsavedChangesState()
    }

    /// Update the current profile with current settings
    private func updateCurrentProfile() {
        guard profileManager.activeProfileName.lowercased() != "default" else {
            errorMessage = "Cannot modify the Default profile"
            return
        }

        do {
            let currentSnapshot = AppSettings.shared.createSnapshot()
            try profileManager.updateActiveProfile(settings: currentSnapshot)
            errorMessage = nil
            updateUnsavedChangesState()
            onSettingsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Save current settings as a new profile
    private func saveNewProfile() {
        let trimmedName = newProfileName.trimmingCharacters(in: .whitespaces)

        // Validate name
        guard !trimmedName.isEmpty else {
            errorMessage = "Profile name cannot be empty"
            return
        }

        guard trimmedName.lowercased() != "default" else {
            errorMessage = "Cannot use 'Default' as a profile name (reserved)"
            return
        }

        // Check for duplicates
        if profileManager.availableProfiles.contains(where: { $0.lowercased() == trimmedName.lowercased() }) {
            errorMessage = "A profile with this name already exists"
            return
        }

        do {
            let currentSnapshot = AppSettings.shared.createSnapshot()
            try profileManager.createProfileFromCurrentSettings(name: trimmedName, settings: currentSnapshot)

            // Success - close dialog and reset
            showingSaveDialog = false
            newProfileName = ""
            errorMessage = nil
            updateUnsavedChangesState()
            onSettingsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Revert changes to the saved state of the active profile
    private func revertChanges() {
        profileManager.revertToSaved()
        updateUnsavedChangesState()
        onSettingsChanged?()
    }
}

// MARK: - Preview

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    ProfileManagementBar()
        .frame(width: 450)
}
#endif
