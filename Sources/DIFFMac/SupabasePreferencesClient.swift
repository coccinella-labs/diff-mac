import Foundation

enum SupabasePreferencesError: LocalizedError {
    case missingConfig
    case invalidURL
    case missingUserID
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            "Add Supabase URL, anon key, and access token first."
        case .invalidURL:
            "Supabase URL is invalid."
        case .missingUserID:
            "Could not read a user id from the Supabase access token."
        case .invalidResponse:
            "Supabase returned an invalid response."
        case .http(let status, let message):
            "Supabase returned HTTP \(status): \(message)"
        }
    }

    var statusCode: Int? {
        switch self {
        case .http(let status, _):
            status
        default:
            nil
        }
    }
}

struct SupabasePreferences: Codable, Sendable {
    let userID: String
    let defaultRepoOwner: String?
    let defaultRepoName: String?
    let recentRepos: [SupabaseRecentRepo]?
    let savedPulls: [SupabaseSavedPull]?
    let aiDrafts: [SupabaseAIDraft]?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case defaultRepoOwner = "default_repo_owner"
        case defaultRepoName = "default_repo_name"
        case recentRepos = "recent_repos"
        case savedPulls = "saved_pulls"
        case aiDrafts = "ai_drafts"
    }
}

struct SupabaseAIDraft: Codable, Sendable {
    let id: String
    let owner: String
    let repo: String
    let pullNumber: Int
    let pullTitle: String
    let branch: String
    let path: String
    let commentID: Int
    let commentBody: String
    let originalContent: String
    let draftContent: String
    let summary: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case owner
        case repo
        case pullNumber = "pull_number"
        case pullTitle = "pull_title"
        case branch
        case path
        case commentID = "comment_id"
        case commentBody = "comment_body"
        case originalContent = "original_content"
        case draftContent = "draft_content"
        case summary
        case updatedAt = "updated_at"
    }
}

struct SupabaseRecentRepo: Codable, Sendable {
    let owner: String
    let repo: String
    let lastViewedAt: String

    enum CodingKeys: String, CodingKey {
        case owner
        case repo
        case lastViewedAt = "last_viewed_at"
    }
}

struct SupabaseSavedPull: Codable, Sendable {
    let owner: String
    let repo: String
    let pullNumber: Int
    let title: String
    let htmlURL: String
    let state: String
    let draft: Bool
    let savedAt: String

    enum CodingKeys: String, CodingKey {
        case owner
        case repo
        case pullNumber = "pull_number"
        case title
        case htmlURL = "html_url"
        case state
        case draft
        case savedAt = "saved_at"
    }
}

final class SupabasePreferencesClient: @unchecked Sendable {
    var projectURL = ""
    var anonKey = ""
    var accessToken = ""
    private let session: URLSession

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func userIDFromAccessToken() throws -> String {
        guard let sub = JWTClaims.subject(from: accessToken), !sub.isEmpty else {
            throw SupabasePreferencesError.missingUserID
        }
        return sub
    }

    func fetchPreferences() async throws -> SupabasePreferences? {
        let userID = try userIDFromAccessToken()
        try validateConfig()
        let url = try SupabaseRequestBuilder.fetchPreferencesURL(projectURL: projectURL, userID: userID)
        let data = try await send(url: url, method: "GET")
        let rows = try decoder.decode([SupabasePreferences].self, from: data)
        return rows.first
    }

    func upsertPreferences(_ preferences: SupabasePreferences) async throws {
        try validateConfig()
        let url = try SupabaseRequestBuilder.upsertPreferencesURL(projectURL: projectURL)
        let body = try encoder.encode([preferences])
        _ = try await send(
            url: url,
            method: "POST",
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    private func validateConfig() throws {
        guard !projectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SupabasePreferencesError.missingConfig
        }
    }

    private func send(url: URL, method: String, body: Data? = nil, prefer: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabasePreferencesError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabasePreferencesError.http(http.statusCode, APIErrorMessage.extract(from: data, fallback: ""))
        }
        return data
    }
}
