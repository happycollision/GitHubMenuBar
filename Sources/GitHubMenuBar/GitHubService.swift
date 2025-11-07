import Foundation

final class GitHubService: Sendable {
    static let shared = GitHubService()

    private init() {}

    func checkGHInstalled() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gh"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw AppError.ghNotInstalled
        }
    }

    func checkAuthentication() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw AppError.ghNotAuthenticated
        }
    }

    func fetchReviewRequests() async throws -> [PullRequest] {
        // First check if gh is installed and authenticated
        try await checkGHInstalled()
        try await checkAuthentication()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "gh", "search", "prs",
            "--review-requested=@me",
            "--json", "id,title,url,number,repository,author,createdAt",
            "--limit", "50"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AppError.commandFailed(errorMessage)
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let prs = try decoder.decode([PullRequest].self, from: data)

            return prs
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.decodingError(error.localizedDescription)
        }
    }
}
