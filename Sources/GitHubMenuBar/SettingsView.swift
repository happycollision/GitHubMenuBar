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

    /// Refresh interval selection
    @State private var refreshInterval: RefreshInterval
    @State private var customIntervalText: String = ""

    /// Group by repository setting
    @State private var groupByRepo: Bool

    /// Callback to trigger refresh when settings change
    var onSettingsChanged: (() -> Void)?

    /// Enum for predefined refresh intervals
    enum RefreshInterval: Hashable {
        case minutes(Int)
        case custom

        var displayName: String {
            switch self {
            case .minutes(let m): return "\(m) minute\(m == 1 ? "" : "s")"
            case .custom: return "Custom"
            }
        }

        static let predefined: [RefreshInterval] = [
            .minutes(1), .minutes(5), .minutes(10), .minutes(15), .minutes(30)
        ]
    }

    // MARK: - Initialization

    init(onSettingsChanged: (() -> Void)? = nil) {
        self.onSettingsChanged = onSettingsChanged

        // Initialize state from AppSettings
        // Note: excluded = false means showing, excluded = true means hiding
        _showOpen = State(initialValue: !AppSettings.shared.isExcluded(.open))
        _showDraft = State(initialValue: !AppSettings.shared.isExcluded(.draft))
        _showMerged = State(initialValue: !AppSettings.shared.isExcluded(.merged))
        _showClosed = State(initialValue: !AppSettings.shared.isExcluded(.closed))

        // Initialize refresh interval from AppSettings
        let currentInterval = AppSettings.shared.refreshIntervalMinutes
        if let predefined = RefreshInterval.predefined.first(where: {
            if case .minutes(let m) = $0 { return m == currentInterval }
            return false
        }) {
            _refreshInterval = State(initialValue: predefined)
        } else {
            _refreshInterval = State(initialValue: .custom)
            _customIntervalText = State(initialValue: String(currentInterval))
        }

        // Initialize group by repo from AppSettings
        _groupByRepo = State(initialValue: AppSettings.shared.groupByRepo)
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

            // Refresh interval section
            VStack(alignment: .leading, spacing: 12) {
                Text("Refresh Interval")
                    .font(.headline)

                Text("How often to check for new pull requests:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Refresh every:", selection: $refreshInterval) {
                    ForEach(RefreshInterval.predefined, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                    Text("Custom").tag(RefreshInterval.custom)
                }
                .onChange(of: refreshInterval) { newValue in
                    updateRefreshInterval()
                }

                // Custom interval text field (only shown when Custom is selected)
                if case .custom = refreshInterval {
                    HStack {
                        TextField("Minutes (1-60)", text: $customIntervalText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 100)
                            .onSubmit {
                                updateRefreshInterval()
                            }

                        Text("minutes")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Group by repository section
            VStack(alignment: .leading, spacing: 12) {
                Text("Display Options")
                    .font(.headline)

                Toggle("Group by Repository", isOn: $groupByRepo)
                    .onChange(of: groupByRepo) { newValue in
                        updateGroupByRepo(newValue: newValue)
                    }

                Text("When enabled, PRs are organized by repository with headers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

    /// Updates the refresh interval in AppSettings
    private func updateRefreshInterval() {
        let newInterval: Int
        switch refreshInterval {
        case .minutes(let m):
            newInterval = m
        case .custom:
            // Parse custom interval from text field
            if let parsed = Int(customIntervalText), parsed >= 1, parsed <= 60 {
                newInterval = parsed
            } else {
                // Invalid input - revert to current setting
                customIntervalText = String(AppSettings.shared.refreshIntervalMinutes)
                return
            }
        }

        if newInterval != AppSettings.shared.refreshIntervalMinutes {
            AppSettings.shared.refreshIntervalMinutes = newInterval
            onSettingsChanged?()
        }
    }

    /// Updates the group by repo setting in AppSettings
    private func updateGroupByRepo(newValue: Bool) {
        if newValue != AppSettings.shared.groupByRepo {
            AppSettings.shared.groupByRepo = newValue
            onSettingsChanged?()
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
