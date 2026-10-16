import Foundation

enum OAuthCallbackParser {
    static func value(named name: String, in url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value,
           !value.isEmpty {
            return value
        }

        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
              !fragment.isEmpty
        else {
            return nil
        }

        let fragmentQuery = fragment.hasPrefix("?") ? String(fragment.dropFirst()) : fragment
        return URLComponents(string: "?\(fragmentQuery)")?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func githubCode(from url: URL) -> String? {
        value(named: "code", in: url)
    }

    static func githubState(from url: URL) -> String? {
        value(named: "state", in: url)
    }

    static func supabaseAccessToken(from url: URL) -> String? {
        value(named: "access_token", in: url)
    }

    static func supabaseRefreshToken(from url: URL) -> String? {
        value(named: "refresh_token", in: url)
    }
}
