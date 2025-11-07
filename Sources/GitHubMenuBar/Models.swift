import Foundation

struct PullRequest: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let number: Int
    let repository: Repository
    let author: Author
    let createdAt: Date

    struct Repository: Codable {
        let nameWithOwner: String
    }

    struct Author: Codable {
        let login: String
    }
}

enum AppError: Error, LocalizedError {
    case ghNotInstalled
    case ghNotAuthenticated
    case commandFailed(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com"
        case .ghNotAuthenticated:
            return "Not authenticated with GitHub. Run 'gh auth login' in Terminal."
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .decodingError(let message):
            return "Failed to parse data: \(message)"
        }
    }
}
