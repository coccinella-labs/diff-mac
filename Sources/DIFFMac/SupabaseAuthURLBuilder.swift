import Foundation

enum SupabaseAuthURLBuilder {
    static func authorizeURL(projectURL: String, provider: String = "github", redirectTo: String = "diffmac://supabase-auth") throws -> URL {
        let trimmedProjectURL = projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectURL.isEmpty,
              var components = URLComponents(string: trimmedProjectURL)
        else {
            throw SupabasePreferencesError.invalidURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/auth/v1/authorize" : "/\(basePath)/auth/v1/authorize"
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectTo)
        ]

        guard let url = components.url else {
            throw SupabasePreferencesError.invalidURL
        }
        return url
    }
}
