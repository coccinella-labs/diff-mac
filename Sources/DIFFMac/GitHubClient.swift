import Foundation

enum GitHubClientError: LocalizedError {
    case invalidURL(String)
    case missingToken
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            "Invalid URL: \(value)"
        case .missingToken:
            "Add a GitHub token before using this write action."
        case .http(let status, let message):
            "GitHub returned HTTP \(status): \(message)"
        case .emptyResponse:
            "GitHub returned an empty response."
        }
    }
}

final class GitHubClient: @unchecked Sendable {
    var token: String = ""
    private let session: URLSession

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let jsonEncoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchViewer() async throws -> GitHubUser {
        try await request("/user")
    }

    func fetchPulls(repo: RepoRef, state: PullStateFilter, page: Int = 1, perPage: Int = 50) async throws -> [PullRequest] {
        try await request(url: GitHubRequestBuilder.pullsURL(repo: repo, state: state, page: page, perPage: perPage))
    }

    func fetchPull(repo: RepoRef, number: Int) async throws -> PullRequest {
        try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)")
    }

    func fetchPullFiles(repo: RepoRef, number: Int) async throws -> [ChangedFile] {
        try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/files", query: [
            URLQueryItem(name: "per_page", value: "100")
        ])
    }

    func fetchIssueComments(repo: RepoRef, number: Int) async throws -> [IssueComment] {
        try await request("/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments", query: [
            URLQueryItem(name: "per_page", value: "100")
        ])
    }

    func fetchReviewComments(repo: RepoRef, number: Int) async throws -> [ReviewComment] {
        try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/comments", query: [
            URLQueryItem(name: "per_page", value: "100")
        ])
    }

    func fetchReviews(repo: RepoRef, number: Int) async throws -> [PullReview] {
        try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/reviews", query: [
            URLQueryItem(name: "per_page", value: "100")
        ])
    }

    func fetchCommits(repo: RepoRef, number: Int) async throws -> [PullCommit] {
        try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/commits", query: [
            URLQueryItem(name: "per_page", value: "100")
        ])
    }

    func fetchTimeline(repo: RepoRef, number: Int) async throws -> [TimelineEvent] {
        try await request(
            "/repos/\(repo.owner)/\(repo.name)/issues/\(number)/timeline",
            query: [URLQueryItem(name: "per_page", value: "100")],
            accept: "application/vnd.github.mockingbird-preview+json"
        )
    }

    func fetchChecks(repo: RepoRef, ref: String) async throws -> [CheckRun] {
        let response: CheckRunsResponse = try await request("/repos/\(repo.owner)/\(repo.name)/commits/\(ref)/check-runs", accept: "application/vnd.github+json")
        return response.checkRuns
    }

    func fetchCheckAnnotations(repo: RepoRef, checkRunID: Int) async throws -> [CheckAnnotation] {
        let response: CheckAnnotationsResponse = try await request(
            "/repos/\(repo.owner)/\(repo.name)/check-runs/\(checkRunID)/annotations",
            query: [URLQueryItem(name: "per_page", value: "100")]
        )
        return response.annotations
    }

    func fetchBranches(repo: RepoRef, page: Int = 1, perPage: Int = 100) async throws -> [Branch] {
        try await request("/repos/\(repo.owner)/\(repo.name)/branches", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ])
    }

    func fetchRepoInfo(repo: RepoRef) async throws -> RepoInfo {
        try await request("/repos/\(repo.owner)/\(repo.name)")
    }

    func compare(repo: RepoRef, base: String, head: String) async throws -> CompareResponse {
        try await request("/repos/\(repo.owner)/\(repo.name)/compare/\(base.urlPathEncoded)...\(head.urlPathEncoded)")
    }

    func fetchTree(repo: RepoRef, ref: String) async throws -> RepoTreeResponse {
        try await request("/repos/\(repo.owner)/\(repo.name)/git/trees/\(ref.urlPathEncoded)", query: [
            URLQueryItem(name: "recursive", value: "1")
        ])
    }

    func fetchContent(repo: RepoRef, path: String, ref: String) async throws -> RepoContent {
        try await request("/repos/\(repo.owner)/\(repo.name)/contents/\(path.urlPathEncodedPreservingSlashes)", query: [
            URLQueryItem(name: "ref", value: ref)
        ])
    }

    func updateContent(repo: RepoRef, path: String, sha: String?, branch: String, content: String, message: String) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }

        let body = try GitHubRequestBuilder.updateContentPayload(sha: sha, branch: branch, content: content, message: message)
        let _: EmptyPayload = try await request(
            "/repos/\(repo.owner)/\(repo.name)/contents/\(path.urlPathEncodedPreservingSlashes)",
            method: "PUT",
            body: body
        )
    }

    func createBranch(repo: RepoRef, name: String, sourceSHA: String) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "ref": "refs/heads/\(name)",
            "sha": sourceSHA
        ])
        let _: EmptyPayload = try await request("/repos/\(repo.owner)/\(repo.name)/git/refs", method: "POST", body: data)
    }

    func createPull(repo: RepoRef, payload: CreatePullPayload) async throws -> PullRequest {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try GitHubRequestBuilder.createPullPayload(payload)
        return try await request("/repos/\(repo.owner)/\(repo.name)/pulls", method: "POST", body: data)
    }

    func postIssueComment(repo: RepoRef, number: Int, body: String) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try JSONSerialization.data(withJSONObject: ["body": body])
        let _: IssueComment = try await request("/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments", method: "POST", body: data)
    }

    func submitReview(repo: RepoRef, number: Int, body: String, event: String) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "body": body,
            "event": event
        ])
        let _: PullReview = try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/reviews", method: "POST", body: data)
    }

    func postReviewComment(repo: RepoRef, number: Int, body: String, commitID: String, path: String, line: Int, side: String) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "body": body,
            "commit_id": commitID,
            "path": path,
            "line": line,
            "side": side
        ])
        let _: ReviewComment = try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/comments", method: "POST", body: data)
    }

    func updatePull(repo: RepoRef, number: Int, title: String, body: String) async throws -> PullRequest {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try JSONSerialization.data(withJSONObject: ["title": title, "body": body])
        return try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)", method: "PATCH", body: data)
    }

    func replaceLabels(repo: RepoRef, number: Int, labels: [String]) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try JSONSerialization.data(withJSONObject: ["labels": labels])
        let _: [PullLabel] = try await request("/repos/\(repo.owner)/\(repo.name)/issues/\(number)/labels", method: "PUT", body: data)
    }

    func updateBranch(repo: RepoRef, number: Int) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let _: EmptyPayload = try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/update-branch", method: "PUT", body: Data("{}".utf8))
    }

    func mergePull(repo: RepoRef, number: Int, method: String) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let data = try JSONSerialization.data(withJSONObject: ["merge_method": method])
        let _: EmptyPayload = try await request("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/merge", method: "PUT", body: data)
    }

    func deleteBranch(repo: RepoRef, name: String) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubClientError.missingToken
        }
        let _: EmptyPayload = try await request("/repos/\(repo.owner)/\(repo.name)/git/refs/heads/\(name.urlPathEncodedPreservingSlashes)", method: "DELETE")
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        accept: String = "application/vnd.github+json"
    ) async throws -> T {
        let url = try GitHubRequestBuilder.url(path: path, query: query)
        return try await request(url: url, method: method, body: body, accept: accept)
    }

    private func request<T: Decodable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        accept: String = "application/vnd.github+json"
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("DIFFMac", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.emptyResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = APIErrorMessage.extract(from: data)
            throw GitHubClientError.http(http.statusCode, message)
        }

        if T.self == EmptyPayload.self {
            return EmptyPayload() as! T
        }

        return try jsonDecoder.decode(T.self, from: data)
    }
}

struct EmptyPayload: Codable {}
