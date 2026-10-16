import Foundation

enum AppMetadata {
    static let name = "DIFF Mac"
    static let executableName = "DIFFMac"
    static let bundleIdentifier = "com.bniladridas.diff-mac"
    static let version = "0.1.0"
    static let build = "1"
    static let minimumSystemVersion = "15.0"

    static var releaseArchiveName: String {
        "\(executableName)-\(version)"
    }
}

struct DiagnosticsSnapshot: Hashable {
    let appVersion: String
    let repo: String
    let viewer: String
    let mode: String
    let savedPullsCount: Int
    let recentReposCount: Int
    let aiDraftsCount: Int
    let hasGitHubToken: Bool
    let hasGeminiKey: Bool
    let hasSupabaseConfig: Bool
    let livePollingEnabled: Bool

    var redactedText: String {
        """
        App: DIFF Mac \(appVersion)
        Repository: \(repo)
        Viewer: \(viewer)
        Mode: \(mode)
        Saved pulls: \(savedPullsCount)
        Recent repos: \(recentReposCount)
        AI drafts: \(aiDraftsCount)
        GitHub token configured: \(hasGitHubToken)
        Gemini key configured: \(hasGeminiKey)
        Supabase configured: \(hasSupabaseConfig)
        Live polling: \(livePollingEnabled)
        """
    }
}
