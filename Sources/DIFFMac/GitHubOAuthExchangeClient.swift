import Foundation

enum GitHubOAuthExchangeError: LocalizedError {
    case missingEndpoint
    case invalidEndpoint
    case stateMismatch
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            "Add a GitHub OAuth exchange endpoint first."
        case .invalidEndpoint:
            "GitHub OAuth exchange endpoint is invalid."
        case .stateMismatch:
            "GitHub OAuth callback state did not match the pending sign-in."
        case .invalidResponse:
            "GitHub OAuth exchange returned an invalid response."
        case .http(let status, let message):
            "GitHub OAuth exchange returned HTTP \(status): \(message)"
        }
    }
}

struct GitHubOAuthTokenResponse: Codable, Hashable {
    let accessToken: String
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

final class GitHubOAuthExchangeClient: @unchecked Sendable {
    var endpoint = ""
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exchange(code: String, state: String? = nil) async throws -> String {
        let url = try Self.validatedEndpointURL(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = ["code": code]
        if let state, !state.isEmpty {
            payload["state"] = state
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthExchangeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubOAuthExchangeError.http(http.statusCode, APIErrorMessage.extract(from: data, fallback: ""))
        }
        let decoded = try decoder.decode(GitHubOAuthTokenResponse.self, from: data)
        guard !decoded.accessToken.isEmpty else {
            throw GitHubOAuthExchangeError.invalidResponse
        }
        return decoded.accessToken
    }

    static func validatedEndpointURL(_ endpoint: String) throws -> URL {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            throw GitHubOAuthExchangeError.missingEndpoint
        }
        guard let url = URL(string: trimmedEndpoint), url.scheme == "https", url.host?.isEmpty == false else {
            throw GitHubOAuthExchangeError.invalidEndpoint
        }
        return url
    }
}
