import Foundation

/// Container for all profile data stored in JSON
struct ProfilesContainer: Codable {
    let version: Int
    var activeProfile: String?  // Can be "Default" or user profile name, nil = "unsaved"
    var profiles: [String: Profile]  // User-created profiles only, Default NOT included

    init(version: Int = 1, activeProfile: String? = "Default", profiles: [String: Profile] = [:]) {
        self.version = version
        self.activeProfile = activeProfile
        self.profiles = profiles
    }
}

/// A single profile containing a name and settings
struct Profile: Codable {
    var name: String
    let isDefault: Bool  // Only true for hardcoded Default profile
    let createdAt: Date
    var modifiedAt: Date
    var settings: ProfileSettings

    init(name: String, isDefault: Bool = false, createdAt: Date = Date(), modifiedAt: Date = Date(), settings: ProfileSettings) {
        self.name = name
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.settings = settings
    }
}

/// Settings stored in a profile (matches AppSettings properties)
struct ProfileSettings: Codable {
    var excludedStatuses: [String]  // Store as array for JSON
    var excludedReviewDecisions: [String]  // Store as array for JSON
    var refreshIntervalMinutes: Int
    var groupByRepo: Bool
    var repoFilterEnabled: Bool
    var repoFilterMode: String
    var whitelistedRepositories: [String]
    var blacklistedRepositories: [String]
    var authorFilterEnabled: Bool
    var authorFilterMode: String
    var whitelistedAuthors: [String]
    var blacklistedAuthors: [String]

    init(
        excludedStatuses: [String] = ["MERGED", "CLOSED"],
        excludedReviewDecisions: [String] = [],
        refreshIntervalMinutes: Int = 15,
        groupByRepo: Bool = true,
        repoFilterEnabled: Bool = false,
        repoFilterMode: String = "blacklist",
        whitelistedRepositories: [String] = [],
        blacklistedRepositories: [String] = [],
        authorFilterEnabled: Bool = true,
        authorFilterMode: String = "blacklist",
        whitelistedAuthors: [String] = [],
        blacklistedAuthors: [String] = ["dependabot", "dependabot[bot]"]
    ) {
        self.excludedStatuses = excludedStatuses
        self.excludedReviewDecisions = excludedReviewDecisions
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.groupByRepo = groupByRepo
        self.repoFilterEnabled = repoFilterEnabled
        self.repoFilterMode = repoFilterMode
        self.whitelistedRepositories = whitelistedRepositories
        self.blacklistedRepositories = blacklistedRepositories
        self.authorFilterEnabled = authorFilterEnabled
        self.authorFilterMode = authorFilterMode
        self.whitelistedAuthors = whitelistedAuthors
        self.blacklistedAuthors = blacklistedAuthors
    }

    /// Custom equality comparison that ignores array ordering
    /// Arrays are compared as sets since they come from Set<String> conversions
    static func == (lhs: ProfileSettings, rhs: ProfileSettings) -> Bool {
        return lhs.refreshIntervalMinutes == rhs.refreshIntervalMinutes &&
               lhs.groupByRepo == rhs.groupByRepo &&
               lhs.repoFilterEnabled == rhs.repoFilterEnabled &&
               lhs.repoFilterMode == rhs.repoFilterMode &&
               lhs.authorFilterEnabled == rhs.authorFilterEnabled &&
               lhs.authorFilterMode == rhs.authorFilterMode &&
               Set(lhs.excludedStatuses) == Set(rhs.excludedStatuses) &&
               Set(lhs.excludedReviewDecisions) == Set(rhs.excludedReviewDecisions) &&
               Set(lhs.whitelistedRepositories) == Set(rhs.whitelistedRepositories) &&
               Set(lhs.blacklistedRepositories) == Set(rhs.blacklistedRepositories) &&
               Set(lhs.whitelistedAuthors) == Set(rhs.whitelistedAuthors) &&
               Set(lhs.blacklistedAuthors) == Set(rhs.blacklistedAuthors)
    }
}

extension ProfileSettings: Equatable {}

// MARK: - Export/Import Support Types

/// Resolution strategy for profile name conflicts during import
enum ConflictResolution {
    case skip          // Don't import this profile
    case rename        // Auto-append number to profile name
    case overwrite     // Replace existing profile
}

/// Result of a profile import operation
struct ImportResult {
    let imported: [String]      // Successfully imported profile names
    let skipped: [String]       // Profile names that were skipped
    let conflicts: [String]     // Profile names that had conflicts
    let errors: [String: Error] // Profile names with errors
}

/// Wrapper for exporting a single profile
struct ExportableProfile: Codable {
    let profile: Profile
    let exportedAt: Date
    let exportVersion: Int
}

/// Wrapper for exporting multiple profiles
struct ExportableProfiles: Codable {
    let profiles: [String: Profile]
    let exportedAt: Date
    let exportVersion: Int
}

// MARK: - Profile Errors

/// Errors that can occur during profile operations
enum ProfileError: Error, LocalizedError {
    case profileNotFound
    case cannotExportDefault
    case cannotImportAsDefault
    case cannotModifyDefault
    case cannotDeleteDefault
    case cannotRenameDefault
    case invalidProfileName
    case invalidImportFormat
    case profileAlreadyExists
    case fileNotFound
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Profile not found"
        case .cannotExportDefault:
            return "Cannot export the Default profile (it's hardcoded)"
        case .cannotImportAsDefault:
            return "Cannot import a profile named 'Default' (reserved name)"
        case .cannotModifyDefault:
            return "Cannot modify the Default profile (it's read-only)"
        case .cannotDeleteDefault:
            return "Cannot delete the Default profile"
        case .cannotRenameDefault:
            return "Cannot rename the Default profile"
        case .invalidProfileName:
            return "Invalid profile name (must not be empty or 'Default')"
        case .invalidImportFormat:
            return "Invalid import file format"
        case .profileAlreadyExists:
            return "A profile with this name already exists"
        case .fileNotFound:
            return "File not found"
        case .invalidJSON:
            return "Invalid JSON in file"
        }
    }
}
