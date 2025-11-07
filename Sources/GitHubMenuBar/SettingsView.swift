import SwiftUI

/// SwiftUI view for the settings dialog.
///
/// Displays checkboxes for filtering PRs by status (Open, Draft, Merged, Closed).
/// Changes are automatically persisted to UserDefaults via AppSettings singleton.
struct SettingsView: View {
    // MARK: - State

    /// Local state for each status filter (toggling updates AppSettings)
    @State private var showOpen: Bool
    @State private var showDraft: Bool
    @State private var showMerged: Bool
    @State private var showClosed: Bool

    /// Callback to trigger refresh when settings change
    var onSettingsChanged: (() -> Void)?

    // MARK: - Initialization

    init(onSettingsChanged: (() -> Void)? = nil) {
        self.onSettingsChanged = onSettingsChanged

        // Initialize state from AppSettings
        // Note: excluded = false means showing, excluded = true means hiding
        _showOpen = State(initialValue: !AppSettings.shared.isExcluded(.open))
        _showDraft = State(initialValue: !AppSettings.shared.isExcluded(.draft))
        _showMerged = State(initialValue: !AppSettings.shared.isExcluded(.merged))
        _showClosed = State(initialValue: !AppSettings.shared.isExcluded(.closed))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Filter Pull Requests")
                .font(.headline)

            Text("Choose which PR statuses to display in the menu:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            // Status checkboxes
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show Open PRs", isOn: $showOpen)
                    .onChange(of: showOpen) { newValue in
                        updateSetting(status: .open, shouldShow: newValue)
                    }

                Toggle("Show Draft PRs", isOn: $showDraft)
                    .onChange(of: showDraft) { newValue in
                        updateSetting(status: .draft, shouldShow: newValue)
                    }

                Toggle("Show Merged PRs", isOn: $showMerged)
                    .onChange(of: showMerged) { newValue in
                        updateSetting(status: .merged, shouldShow: newValue)
                    }

                Toggle("Show Closed PRs", isOn: $showClosed)
                    .onChange(of: showClosed) { newValue in
                        updateSetting(status: .closed, shouldShow: newValue)
                    }
            }

            Divider()

            // Info text
            Text("Changes take effect immediately and will be remembered.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 350)
    }

    // MARK: - Helper Methods

    /// Updates AppSettings and triggers refresh
    private func updateSetting(status: PRStatus, shouldShow: Bool) {
        // shouldShow = true means NOT excluded
        // shouldShow = false means excluded
        let shouldExclude = !shouldShow

        if shouldExclude != AppSettings.shared.isExcluded(status) {
            AppSettings.shared.toggleExclusion(for: status)
            onSettingsChanged?()
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
