import Foundation

enum GitHubRequestBuilder {
    static let baseURL = URL(string: "https://api.github.com")!

    static func url(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: "https://api.github.com\(path)") else {
            throw GitHubClientError.invalidURL(path)
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw GitHubClientError.invalidURL(path)
        }
        return url
    }

    static func pullsURL(repo: RepoRef, state: PullStateFilter, page: Int, perPage: Int) throws -> URL {
        try url(path: "/repos/\(repo.owner)/\(repo.name)/pulls", query: [
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ])
    }

    static func contentURL(repo: RepoRef, path: String, ref: String) throws -> URL {
        try url(path: "/repos/\(repo.owner)/\(repo.name)/contents/\(path.urlPathEncodedPreservingSlashes)", query: [
            URLQueryItem(name: "ref", value: ref)
        ])
    }

    static func updateContentPayload(sha: String?, branch: String, content: String, message: String) throws -> Data {
        var payload: [String: String] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString(),
            "branch": branch
        ]
        if let sha, !sha.isEmpty {
            payload["sha"] = sha
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func createPullPayload(_ payload: CreatePullPayload) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "title": payload.title,
            "body": payload.body,
            "head": payload.head,
            "base": payload.base
        ], options: [.sortedKeys])
    }
}

extension String {
    var urlPathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }

    var urlPathEncodedPreservingSlashes: String {
        split(separator: "/").map { String($0).urlPathEncoded }.joined(separator: "/")
    }
}
