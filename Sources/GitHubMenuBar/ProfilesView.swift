import SwiftUI
import AppKit

/// Advanced profile management view (optional 3rd tab in Settings)
/// Provides rename, delete, export, and import operations
struct ProfilesView: View {
    // MARK: - State

    @ObservedObject var profileManager = ProfileManager.shared
    @State private var selectedProfile: String?
    @State private var showingRenameDialog = false
    @State private var showingDeleteConfirmation = false
    @State private var showingImportResult = false
    @State private var newProfileName = ""
    @State private var errorMessage: String?
    @State private var importResult: ImportResult?

    var onSettingsChanged: (() -> Void)?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with import/export buttons
                HStack(spacing: 12) {
                    Button("Import Profile(s)...") {
                        importProfiles()
                    }

                    Button("Export All...") {
                        exportAllProfiles()
                    }
                    .disabled(profileManager.availableProfiles.count <= 1) // Only Default exists

                    Spacer()
                }

                Divider()

                // Available Profiles section
                Text("Available Profiles")
                    .font(.headline)

                // List of profiles
                ForEach(profileManager.availableProfiles, id: \.self) { profileName in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(profileName)
                                .font(.body)

                            if profileName.lowercased() == "default" {
                                Text("(built-in)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if profileName == profileManager.activeProfileName {
                                Text("✓")
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            // Action buttons (only for user profiles)
                            if profileName.lowercased() != "default" {
                                Button("Export") {
                                    exportProfile(name: profileName)
                                }
                                .buttonStyle(.borderless)

                                Button("Rename") {
                                    selectedProfile = profileName
                                    newProfileName = profileName
                                    showingRenameDialog = true
                                }
                                .buttonStyle(.borderless)

                                Button("Delete") {
                                    selectedProfile = profileName
                                    showingDeleteConfirmation = true
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)

                        if profileName != profileManager.availableProfiles.last {
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
        // Rename dialog
        .sheet(isPresented: $showingRenameDialog) {
            VStack(spacing: 16) {
                Text("Rename Profile")
                    .font(.headline)

                TextField("New Profile Name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showingRenameDialog = false
                        newProfileName = ""
                        errorMessage = nil
                        selectedProfile = nil
                    }

                    Button("Rename") {
                        renameProfile()
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 350)
        }
        // Delete confirmation
        .alert("Delete Profile?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedProfile = nil
            }
            Button("Delete", role: .destructive) {
                deleteProfile()
            }
        } message: {
            Text("Are you sure you want to delete '\(selectedProfile ?? "")'? This action cannot be undone.")
        }
        // Import result
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK") {
                importResult = nil
            }
        } message: {
            if let result = importResult {
                Text(formatImportResult(result))
            }
        }
    }

    // MARK: - Actions

    /// Rename the selected profile
    private func renameProfile() {
        guard let oldName = selectedProfile else { return }

        let trimmedName = newProfileName.trimmingCharacters(in: .whitespaces)

        // Validate
        guard !trimmedName.isEmpty else {
            errorMessage = "Profile name cannot be empty"
            return
        }

        guard trimmedName.lowercased() != "default" else {
            errorMessage = "Cannot use 'Default' as a profile name (reserved)"
            return
        }

        guard trimmedName != oldName else {
            // No change - just close
            showingRenameDialog = false
            return
        }

        do {
            try profileManager.renameProfile(oldName: oldName, newName: trimmedName)
            showingRenameDialog = false
            newProfileName = ""
            errorMessage = nil
            selectedProfile = nil
            onSettingsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete the selected profile
    private func deleteProfile() {
        guard let profileName = selectedProfile else { return }

        do {
            try profileManager.deleteProfile(name: profileName)
            selectedProfile = nil
            onSettingsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Export a single profile
    private func exportProfile(name: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "\(name)-\(formattedDate()).json"
        savePanel.title = "Export Profile"
        savePanel.message = "Choose where to save the profile"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            do {
                try profileManager.exportProfile(name: name, to: url)
                print("[ProfilesView] Exported profile '\(name)' to \(url.path)")
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    /// Export all user profiles
    private func exportAllProfiles() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "GitHubMenuBar-Profiles-\(formattedDate()).json"
        savePanel.title = "Export All Profiles"
        savePanel.message = "Choose where to save all profiles"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            do {
                try profileManager.exportAllProfiles(to: url)
                print("[ProfilesView] Exported all profiles to \(url.path)")
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    /// Import profiles from a file
    private func importProfiles() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import Profile(s)"
        openPanel.message = "Choose a profile export file to import"

        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }

            // Simple conflict handler: always rename on conflict
            // In a more sophisticated version, this could show a dialog for each conflict
            let conflictHandler: (String, Profile) -> ConflictResolution = { name, _ in
                return .rename // Auto-rename conflicts
            }

            do {
                let result = try profileManager.importProfiles(from: url, conflictHandler: conflictHandler)
                importResult = result
                showingImportResult = true
                onSettingsChanged?()
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    /// Format the current date for filenames
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Format import result for display
    private func formatImportResult(_ result: ImportResult) -> String {
        var message = ""

        if !result.imported.isEmpty {
            message += "✓ Imported: \(result.imported.count) profile(s)\n"
            message += result.imported.map { "  • \($0)" }.joined(separator: "\n")
            message += "\n\n"
        }

        if !result.skipped.isEmpty {
            message += "⊘ Skipped: \(result.skipped.count) profile(s)\n"
            message += result.skipped.map { "  • \($0)" }.joined(separator: "\n")
            message += "\n\n"
        }

        if !result.errors.isEmpty {
            message += "⚠️ Errors: \(result.errors.count) profile(s)\n"
            message += result.errors.map { "  • \($0.key): \($0.value.localizedDescription)" }.joined(separator: "\n")
        }

        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Preview

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    ProfilesView()
        .frame(width: 450, height: 500)
}
#endif
