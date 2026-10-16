import Foundation

enum GitHubOAuthURLBuilder {
    static func authorizeURL(
        clientID: String,
        redirectURI: String = "diffmac://github-oauth",
        scope: String = "repo read:user user:email",
        state: String
    ) throws -> URL {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            throw DeviceOAuthError.missingClientID
        }

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }
}
