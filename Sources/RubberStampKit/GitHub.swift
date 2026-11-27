import Foundation

public struct PullRequest: Identifiable, Hashable, Sendable {
    public let id: String          // html URL, unique across repos
    public let repo: String        // owner/name
    public let number: Int
    public let title: String
    public let author: String
    public let url: URL
    public let isDraft: Bool
    public let updatedAt: Date?

    public init(id: String, repo: String, number: Int, title: String, author: String,
                url: URL, isDraft: Bool, updatedAt: Date?) {
        self.id = id
        self.repo = repo
        self.number = number
        self.title = title
        self.author = author
        self.url = url
        self.isDraft = isDraft
        self.updatedAt = updatedAt
    }
}

public enum GHError: LocalizedError, Equatable {
    case notInstalled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "GitHub CLI (gh) not found. Install it with `brew install gh` and run `gh auth login`."
        case .failed(let message):
            return message.isEmpty ? "gh exited with an error" : message
        }
    }
}

/// Talks to GitHub through the `gh` CLI, so the app reuses the existing `gh auth login`
/// session and never stores a token itself.
public enum GitHub {
    public static let ghPath: String? = [
        "/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh",
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Open, non-archived PRs where the current user was requested *personally* as reviewer
    /// (team requests are left out on purpose).
    public static let reviewRequestQuery = "is:pr is:open archived:false user-review-requested:@me"

    public static func reviewRequestArgs() -> [String] {
        ["api", "-X", "GET", "search/issues", "-f", "q=\(reviewRequestQuery)", "-f", "per_page=100"]
    }

    public static func approveArgs(_ pr: PullRequest) -> [String] {
        ["api", "-X", "POST", "repos/\(pr.repo)/pulls/\(pr.number)/reviews", "-f", "event=APPROVE"]
    }

    /// Runs `executable` (default: gh) with `args` and returns stdout; a non-zero exit throws
    /// `GHError.failed` carrying stderr.
    public static func run(_ args: [String], executable: String? = ghPath) async throws -> Data {
        guard let executable else { throw GHError.notInstalled }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["GH_PROMPT_DISABLED"] = "1"
                env["NO_COLOR"] = "1"
                process.environment = env
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    cont.resume(returning: outData)
                } else {
                    let message = String(decoding: errData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: GHError.failed(message))
                }
            }
        }
    }

    public static func reviewRequests() async throws -> [PullRequest] {
        try parseSearch(try await run(reviewRequestArgs()))
    }

    public static func approve(_ pr: PullRequest) async throws {
        _ = try await run(approveArgs(pr))
    }

    public static func currentUser() async throws -> String {
        let data = try await run(["api", "user", "--jq", ".login"])
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses a `search/issues` response, most recently updated first.
    public static func parseSearch(_ data: Data) throws -> [PullRequest] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(SearchResponse.self, from: data)
        return response.items.map { item in
            let parts = item.repository_url.split(separator: "/").suffix(2)
            return PullRequest(
                id: item.html_url.absoluteString,
                repo: parts.joined(separator: "/"),
                number: item.number,
                title: item.title,
                author: item.user.login,
                url: item.html_url,
                isDraft: item.draft ?? false,
                updatedAt: item.updated_at
            )
        }
        .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    private struct SearchResponse: Decodable {
        let items: [Item]
        struct Item: Decodable {
            let number: Int
            let title: String
            let html_url: URL
            let draft: Bool?
            let user: User
            let repository_url: String
            let updated_at: Date?
        }
        struct User: Decodable { let login: String }
    }
}
