import Foundation

struct SupabaseAuthSession: Codable, Hashable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

final class SupabaseAuthClient: @unchecked Sendable {
    var projectURL = ""
    var anonKey = ""
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        guard !projectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SupabasePreferencesError.missingConfig
        }

        let url = try SupabaseAuthRequestBuilder.refreshTokenURL(projectURL: projectURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "refresh_token": refreshToken
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabasePreferencesError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabasePreferencesError.http(http.statusCode, APIErrorMessage.extract(from: data, fallback: ""))
        }
        return try decoder.decode(SupabaseAuthSession.self, from: data)
    }
}

enum SupabaseAuthRequestBuilder {
    static func refreshTokenURL(projectURL: String) throws -> URL {
        guard var components = URLComponents(string: projectURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SupabasePreferencesError.invalidURL
        }
        components.path = "/auth/v1/token"
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        guard let url = components.url else {
            throw SupabasePreferencesError.invalidURL
        }
        return url
    }
}
