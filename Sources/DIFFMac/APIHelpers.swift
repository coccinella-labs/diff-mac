import Foundation

enum APIErrorMessage {
    static func extract(from data: Data, fallback: String = "No response body") -> String {
        guard !data.isEmpty else { return fallback }
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? String,
            !message.isEmpty
        {
            if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
                let details = errors
                    .compactMap { $0["message"] as? String ?? $0["code"] as? String }
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")
                return details.isEmpty ? message : "\(message): \(details)"
            }
            return message
        }
        return String(data: data, encoding: .utf8) ?? fallback
    }
}

enum SupabaseRequestBuilder {
    static func restURL(projectURL: String, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: projectURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SupabasePreferencesError.invalidURL
        }
        components.path = "/rest/v1" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw SupabasePreferencesError.invalidURL
        }
        return url
    }

    static func fetchPreferencesURL(projectURL: String, userID: String) throws -> URL {
        try restURL(projectURL: projectURL, path: "/user_preferences", query: [
            URLQueryItem(name: "select", value: "user_id,default_repo_owner,default_repo_name,recent_repos,saved_pulls,ai_drafts"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "limit", value: "1")
        ])
    }

    static func upsertPreferencesURL(projectURL: String) throws -> URL {
        try restURL(projectURL: projectURL, path: "/user_preferences", query: [
            URLQueryItem(name: "on_conflict", value: "user_id")
        ])
    }
}
