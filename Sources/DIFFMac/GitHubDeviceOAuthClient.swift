import Foundation

enum DeviceOAuthError: LocalizedError {
    case missingClientID
    case invalidResponse
    case authorizationPending
    case slowDown
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Add a GitHub OAuth client ID first."
        case .invalidResponse:
            "GitHub returned an invalid OAuth response."
        case .authorizationPending:
            "Authorization is still pending."
        case .slowDown:
            "GitHub asked the app to slow down polling."
        case .denied(let message):
            message
        }
    }
}

struct DeviceCodeResponse: Codable, Hashable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

final class GitHubDeviceOAuthClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestDeviceCode(clientID: String) async throws -> DeviceCodeResponse {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeviceOAuthError.missingClientID
        }

        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "scope": "repo read:user user:email"
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeviceOAuthError.invalidResponse
        }
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    func pollForToken(clientID: String, deviceCode: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeviceOAuthError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceOAuthError.invalidResponse
        }
        if let token = json["access_token"] as? String, !token.isEmpty {
            return token
        }
        let error = json["error"] as? String
        switch error {
        case "authorization_pending":
            throw DeviceOAuthError.authorizationPending
        case "slow_down":
            throw DeviceOAuthError.slowDown
        default:
            throw DeviceOAuthError.denied((json["error_description"] as? String) ?? "GitHub OAuth failed.")
        }
    }

    private func formBody(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let body = values
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}
