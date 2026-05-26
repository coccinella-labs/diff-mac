import Foundation

enum PullStateFilter: String, CaseIterable, Identifiable {
    case open
    case closed
    case all

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case pulls
    case branches
    case code

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case diff
    case discussion
    case checks
    case timeline

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct RepoRef: Codable, Hashable {
    var owner: String
    var name: String

    var displayName: String { "\(owner)/\(name)" }
}

struct PullRequest: Codable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let user: GitHubUser
    let body: String?
    let htmlURL: URL?
    let state: String
    let draft: Bool?
    let merged: Bool?
    let mergeable: Bool?
    let mergeableState: String?
    let createdAt: Date?
    let updatedAt: Date?
    let base: PullRef?
    let head: PullRef?
    let labels: [PullLabel]?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case user
        case body
        case htmlURL = "html_url"
        case state
        case draft
        case merged
        case mergeable
        case mergeableState = "mergeable_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case base
        case head
        case labels
    }
}

struct GitHubUser: Codable, Hashable {
    let login: String
    let avatarURL: URL?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }
}

struct PullRef: Codable, Hashable {
    let ref: String
    let sha: String?
    let repo: PullRepo?
}

struct PullRepo: Codable, Hashable {
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}

struct PullLabel: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let color: String?
}

struct CreatePullPayload: Hashable {
    var title: String
    var body: String
    var head: String
    var base: String
}

struct SavedPull: Codable, Identifiable, Hashable {
    var id: String { "\(owner)/\(repo)#\(number)" }
    let owner: String
    let repo: String
    let number: Int
    let title: String
    let state: String
    let htmlURL: URL?
    let savedAt: Date
}

struct RecentRepo: Codable, Identifiable, Hashable {
    var id: String { "\(owner)/\(repo)" }
    let owner: String
    let repo: String
    let viewedAt: Date
}

struct AIDraft: Codable, Identifiable, Hashable {
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
    let updatedAt: Date
}

struct ChangedFile: Codable, Identifiable, Hashable {
    var id: String { filename }
    let sha: String?
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let changes: Int
    let patch: String?
}

struct IssueComment: Codable, Identifiable, Hashable {
    let id: Int
    let user: GitHubUser
    let body: String
    let createdAt: Date?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case createdAt = "created_at"
        case htmlURL = "html_url"
    }
}

struct ReviewComment: Codable, Identifiable, Hashable {
    let id: Int
    let user: GitHubUser
    let body: String
    let path: String?
    let line: Int?
    let originalLine: Int?
    let startLine: Int?
    let side: String?
    let diffHunk: String?
    let createdAt: Date?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case path
        case line
        case originalLine = "original_line"
        case startLine = "start_line"
        case side
        case diffHunk = "diff_hunk"
        case createdAt = "created_at"
        case htmlURL = "html_url"
    }
}

struct PullReview: Codable, Identifiable, Hashable {
    let id: Int
    let user: GitHubUser
    let body: String?
    let state: String
    let submittedAt: Date?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case state
        case submittedAt = "submitted_at"
        case htmlURL = "html_url"
    }
}

struct PullCommit: Codable, Identifiable, Hashable {
    var id: String { sha }
    let sha: String
    let htmlURL: URL?
    let commit: CommitPayload
    let author: GitHubUser?

    enum CodingKeys: String, CodingKey {
        case sha
        case htmlURL = "html_url"
        case commit
        case author
    }
}

struct CommitPayload: Codable, Hashable {
    let message: String
    let author: CommitAuthor?
}

struct CommitAuthor: Codable, Hashable {
    let name: String?
    let email: String?
    let date: Date?
}

struct TimelineEvent: Codable, Identifiable, Hashable {
    var id: String { "\(event)-\(createdAt?.timeIntervalSince1970 ?? 0)-\(actor?.login ?? user?.login ?? "")-\(commitID ?? "")" }
    let event: String
    let createdAt: Date?
    let actor: GitHubUser?
    let user: GitHubUser?
    let body: String?
    let state: String?
    let commitID: String?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case event
        case createdAt = "created_at"
        case actor
        case user
        case body
        case state
        case commitID = "commit_id"
        case htmlURL = "html_url"
    }
}

struct CheckRunsResponse: Codable {
    let totalCount: Int?
    let checkRuns: [CheckRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case checkRuns = "check_runs"
    }
}

struct CheckRun: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let status: String?
    let conclusion: String?
    let htmlURL: URL?
    let startedAt: Date?
    let completedAt: Date?
    let output: CheckOutput?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case conclusion
        case htmlURL = "html_url"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case output
    }
}

struct CheckOutput: Codable, Hashable {
    let title: String?
    let summary: String?
    let text: String?
}

struct CheckAnnotationsResponse: Codable {
    let annotations: [CheckAnnotation]
}

struct CheckAnnotation: Codable, Identifiable, Hashable {
    var id: String { "\(path):\(startLine ?? 0):\(endLine ?? 0):\(message)" }
    let path: String
    let startLine: Int?
    let endLine: Int?
    let annotationLevel: String
    let title: String?
    let message: String
    let rawDetails: String?

    enum CodingKeys: String, CodingKey {
        case path
        case startLine = "start_line"
        case endLine = "end_line"
        case annotationLevel = "annotation_level"
        case title
        case message
        case rawDetails = "raw_details"
    }
}

struct Branch: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let commit: BranchCommit
    let protected: Bool
}

struct BranchCommit: Codable, Hashable {
    let sha: String
}

struct CompareResponse: Codable {
    let files: [ChangedFile]?
    let commits: [PullCommit]?
}

struct RepoInfo: Codable {
    let defaultBranch: String?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
        case htmlURL = "html_url"
    }
}

struct RepoTreeResponse: Codable {
    let tree: [RepoTreeItem]
    let truncated: Bool?
}

struct RepoTreeItem: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    let mode: String?
    let type: String
    let sha: String
    let size: Int?
}

struct RepoContent: Codable, Hashable {
    let path: String
    let sha: String?
    let content: String?
    let encoding: String?
}

struct PullSnapshot {
    var pull: PullRequest
    var files: [ChangedFile] = []
    var comments: [IssueComment] = []
    var reviewComments: [ReviewComment] = []
    var reviews: [PullReview] = []
    var commits: [PullCommit] = []
    var checks: [CheckRun] = []
    var timeline: [TimelineEvent] = []
}

struct BranchSnapshot {
    var branch: Branch
    var base: String
    var files: [ChangedFile] = []
    var commits: [PullCommit] = []
}
