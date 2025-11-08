import SwiftUI
import AppKit

/// AppKit NSTextField wrapper for proper keyboard focus handling in menu bar apps
struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

/// AppKit NSTextView wrapper for multiline text editing with proper keyboard focus
struct AppKitTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = ClickableTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor

        // Configure text container to wrap
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        return scrollView
    }

    /// Custom NSTextView that accepts first responder on mouse down
    private class ClickableTextView: NSTextView {
        override func mouseDown(with event: NSEvent) {
            // Make ourselves first responder when clicked
            self.window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override var acceptsFirstResponder: Bool {
            return true
        }
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Only update if different to avoid cursor jumping
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Restore cursor position if possible
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

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

    /// Repository filter settings
    @State private var repoFilterEnabled: Bool
    @State private var repoFilterMode: FilterMode
    @State private var repoListText: String = ""
    @State private var repoSaveError: String? = nil

    /// Author filter settings
    @State private var authorFilterEnabled: Bool
    @State private var authorFilterMode: FilterMode
    @State private var authorListText: String = ""
    @State private var authorSaveError: String? = nil

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

        // Initialize filter settings from AppSettings
        _repoFilterEnabled = State(initialValue: AppSettings.shared.repoFilterEnabled)
        _repoFilterMode = State(initialValue: AppSettings.shared.repoFilterMode)
        _authorFilterEnabled = State(initialValue: AppSettings.shared.authorFilterEnabled)
        _authorFilterMode = State(initialValue: AppSettings.shared.authorFilterMode)

        // Populate text fields with current lists (newline-delimited)
        let currentRepos = AppSettings.shared.repoFilterMode == .blacklist
            ? Array(AppSettings.shared.blacklistedRepositories).sorted()
            : Array(AppSettings.shared.whitelistedRepositories).sorted()
        _repoListText = State(initialValue: currentRepos.joined(separator: "\n"))

        let currentAuthors = AppSettings.shared.authorFilterMode == .blacklist
            ? Array(AppSettings.shared.blacklistedAuthors).sorted()
            : Array(AppSettings.shared.whitelistedAuthors).sorted()
        _authorListText = State(initialValue: currentAuthors.joined(separator: "\n"))
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
                        AppKitTextField(
                            text: $customIntervalText,
                            placeholder: "Minutes (1-60)",
                            onSubmit: updateRefreshInterval
                        )
                        .frame(width: 100)

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

            // Repository filtering section
            VStack(alignment: .leading, spacing: 12) {
                Text("Repository Filtering")
                    .font(.headline)

                Toggle("Enable Repository Filtering", isOn: $repoFilterEnabled)
                    .onChange(of: repoFilterEnabled) { newValue in
                        AppSettings.shared.repoFilterEnabled = newValue
                        onSettingsChanged?()
                    }

                if repoFilterEnabled {
                    Picker("Mode:", selection: $repoFilterMode) {
                        Text("Blacklist (Exclude)").tag(FilterMode.blacklist)
                        Text("Whitelist (Include Only)").tag(FilterMode.whitelist)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: repoFilterMode) { newValue in
                        AppSettings.shared.repoFilterMode = newValue
                        // Reload text field with the new mode's list
                        let repos = newValue == .blacklist
                            ? Array(AppSettings.shared.blacklistedRepositories).sorted()
                            : Array(AppSettings.shared.whitelistedRepositories).sorted()
                        repoListText = repos.joined(separator: "\n")
                        repoSaveError = nil
                        onSettingsChanged?()
                    }

                    // Show text area based on mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text(repoFilterMode == .blacklist
                            ? "Excluded Repositories (one per line):"
                            : "Included Repositories (one per line, only these will show):")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Format: owner/repo")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $repoListText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .border(Color.gray.opacity(0.3), width: 1)

                        if let error = repoSaveError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button("Save") {
                            saveRepositories()
                        }
                    }
                }

                Text("Filter PRs by repository at the command level.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Author filtering section
            VStack(alignment: .leading, spacing: 12) {
                Text("Author Filtering")
                    .font(.headline)

                Toggle("Enable Author Filtering", isOn: $authorFilterEnabled)
                    .onChange(of: authorFilterEnabled) { newValue in
                        AppSettings.shared.authorFilterEnabled = newValue
                        onSettingsChanged?()
                    }

                if authorFilterEnabled {
                    Picker("Mode:", selection: $authorFilterMode) {
                        Text("Blacklist (Exclude)").tag(FilterMode.blacklist)
                        Text("Whitelist (Include Only)").tag(FilterMode.whitelist)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: authorFilterMode) { newValue in
                        AppSettings.shared.authorFilterMode = newValue
                        // Reload text field with the new mode's list
                        let authors = newValue == .blacklist
                            ? Array(AppSettings.shared.blacklistedAuthors).sorted()
                            : Array(AppSettings.shared.whitelistedAuthors).sorted()
                        authorListText = authors.joined(separator: "\n")
                        authorSaveError = nil
                        onSettingsChanged?()
                    }

                    // Show text area based on mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text(authorFilterMode == .blacklist
                            ? "Excluded Authors (one per line):"
                            : "Included Authors (one per line, only PRs by these authors will show):")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Format: username (without @)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $authorListText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .border(Color.gray.opacity(0.3), width: 1)

                        if let error = authorSaveError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button("Save") {
                            saveAuthors()
                        }
                    }
                }

                Text("Filter PRs by author at the command level.")
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
        .frame(width: 450)
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

    // MARK: - Save Methods

    /// Parses and saves the repository list from the text field
    private func saveRepositories() {
        // Parse lines from text field, handling various line separators
        let lines = repoListText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Validate all repositories
        var validRepos: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }

            // Validate format: owner/repo
            if !trimmed.contains("/") || trimmed.split(separator: "/").count != 2 {
                repoSaveError = "Invalid format '\(trimmed)': must be owner/repo"
                return
            }

            let parts = trimmed.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count != 2 || parts[0].isEmpty || parts[1].isEmpty {
                repoSaveError = "Invalid format '\(trimmed)': both owner and repo name required"
                return
            }

            // Store the properly formatted repo
            validRepos.append("\(parts[0])/\(parts[1])")
        }

        // All valid - update AppSettings
        repoSaveError = nil
        if repoFilterMode == .blacklist {
            AppSettings.shared.blacklistedRepositories = Set(validRepos)
        } else {
            AppSettings.shared.whitelistedRepositories = Set(validRepos)
        }
        onSettingsChanged?()
    }

    /// Parses and saves the author list from the text field
    private func saveAuthors() {
        // Parse lines from text field, handling various line separators
        let lines = authorListText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Validate all authors
        var validAuthors: [String] = []
        let usernameRegex = "^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }

            // Remove @ if present and trim again
            let cleaned = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed

            // Skip if empty after cleaning
            if cleaned.isEmpty {
                continue
            }

            // Validate username format
            if !predicate.evaluate(with: cleaned) {
                authorSaveError = "Invalid username '\(line)': use alphanumeric and hyphens only"
                return
            }

            validAuthors.append(cleaned)
        }

        // All valid - update AppSettings
        authorSaveError = nil
        if authorFilterMode == .blacklist {
            AppSettings.shared.blacklistedAuthors = Set(validAuthors)
        } else {
            AppSettings.shared.whitelistedAuthors = Set(validAuthors)
        }
        onSettingsChanged?()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
