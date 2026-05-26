import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var repo = RepoRef(owner: "harpertoken", name: "harper")
    @Published var token = ""
    @Published var viewer: GitHubUser?
    @Published var mode: WorkspaceMode = .pulls {
        didSet { persistWorkspacePreferences() }
    }
    @Published var pullFilter: PullStateFilter = .open {
        didSet { persistWorkspacePreferences() }
    }
    @Published var activeTab: WorkspaceTab = .diff {
        didSet { persistWorkspacePreferences() }
    }
    @Published var searchText = ""

    @Published var pulls: [PullRequest] = []
    @Published var selectedPull: PullRequest?
    @Published var pullSnapshot: PullSnapshot?

    @Published var branches: [Branch] = []
    @Published var defaultBranch = "main"
    @Published var selectedBranch: Branch?
    @Published var branchSnapshot: BranchSnapshot?

    @Published var repoFiles: [RepoTreeItem] = []
    @Published var selectedRepoFile: RepoTreeItem?
    @Published var repoFileContent = ""
    @Published var originalRepoFileContent = ""
    @Published var repoFileSHA: String?
    @Published var conflictBaseContent = ""
    @Published var conflictBaseRef = ""
    @Published var repoFileIsLikelyBinary = false
    @Published var repoFileIsLarge = false
    @Published var repoRef = "HEAD"
    @Published var commitMessage = ""
    @Published var newFilePath = ""
    @Published var newFileContent = ""
    @Published var newFileCommitMessage = ""
    @Published var createFileMode = false

    @Published var commentDraft = ""
    @Published var reviewDraft = ""
    @Published var inlineCommentDraft = ""
    @Published var inlineCommentPath = ""
    @Published var inlineCommentLine = ""
    @Published var inlineCommentSide = "RIGHT"
    @Published var metadataTitle = ""
    @Published var metadataBody = ""
    @Published var labelsDraft = ""

    @Published var newBranchName = ""
    @Published var pullTitle = ""
    @Published var pullBody = ""
    @Published var pullHead = ""
    @Published var pullBase = ""
    @Published var geminiAPIKey = ""
    @Published var githubOAuthClientID = ""
    @Published var githubOAuthExchangeEndpoint = ""
    @Published var githubOAuthState = ""
    @Published var deviceUserCode = ""
    @Published var deviceVerificationURL: URL?
    @Published var deviceOAuthMessage = ""
    @Published var isPollingDeviceOAuth = false
    @Published var oauthCallbackMessage = ""
    @Published var savedPulls: [SavedPull] = []
    @Published var recentRepos: [RecentRepo] = []
    @Published var aiDrafts: [AIDraft] = []
    @Published var supabaseURL = ""
    @Published var supabaseAnonKey = ""
    @Published var supabaseAccessToken = ""
    @Published var supabaseRefreshToken = ""
    @Published var supabaseSyncMessage = ""
    @Published var livePollingEnabled = true
    @Published var livePollingIntervalSeconds = 60

    @Published var isLoading = false
    @Published var detailLoading = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var checkAnnotations: [Int: [CheckAnnotation]] = [:]
    @Published var loadingCheckAnnotations: Set<Int> = []

    let client = GitHubClient()
    let gemini = GeminiClient()
    let deviceOAuth = GitHubDeviceOAuthClient()
    let githubOAuthExchange = GitHubOAuthExchangeClient()
    let supabaseAuth = SupabaseAuthClient()
    let supabasePreferences = SupabasePreferencesClient()
    private let defaults = UserDefaults.standard
    private let keychainService = "com.bniladridas.diff-mac"
    private let githubTokenAccount = "github-token"
    private let geminiKeyAccount = "gemini-api-key"
    private let supabaseAccessTokenAccount = "supabase-access-token"
    private let supabaseRefreshTokenAccount = "supabase-refresh-token"
    private var pullsPage = 1
    private var branchesPage = 1
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    @Published var hasMorePulls = true
    @Published var hasMoreBranches = true

    init() {
        loadSettings()
        loadLocalCollections()
        client.token = token
    }

    var filteredPulls: [PullRequest] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return pulls
        }
        let needle = searchText.lowercased()
        return pulls.filter {
            $0.title.lowercased().contains(needle) ||
            $0.user.login.lowercased().contains(needle) ||
            String($0.number).contains(needle)
        }
    }

    var filteredBranches: [Branch] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return branches
        }
        let needle = searchText.lowercased()
        return branches.filter { $0.name.lowercased().contains(needle) || $0.commit.sha.lowercased().contains(needle) }
    }

    var filteredRepoFiles: [RepoTreeItem] {
        let files = repoFiles.filter { $0.type == "blob" }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return files
        }
        let needle = searchText.lowercased()
        return files.filter { $0.path.lowercased().contains(needle) }
    }

    var isRepoFileDirty: Bool {
        repoFileContent != originalRepoFileContent
    }

    var conflictBlocks: [ConflictBlock] {
        ConflictMarkerParser.blocks(in: repoFileContent)
    }

    var hasUnresolvedConflicts: Bool {
        !conflictBlocks.isEmpty
    }

    func showWorkspaceMode(_ nextMode: WorkspaceMode) async {
        guard mode != nextMode else {
            await refreshCurrentMode()
            return
        }
        mode = nextMode
        searchText = ""
        await refreshCurrentMode()
    }

    var diagnosticsSnapshot: DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appVersion: "\(AppMetadata.version) (\(AppMetadata.build))",
            repo: repo.displayName,
            viewer: viewer?.login ?? "anonymous",
            mode: mode.title,
            savedPullsCount: savedPulls.count,
            recentReposCount: recentRepos.count,
            aiDraftsCount: aiDrafts.count,
            hasGitHubToken: !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasGeminiKey: !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasSupabaseConfig: !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty && !supabaseAccessToken.isEmpty,
            livePollingEnabled: livePollingEnabled
        )
    }

    func saveSettings() {
        defaults.set(repo.owner, forKey: "repo.owner")
        defaults.set(repo.name, forKey: "repo.name")
        defaults.set(repoRef, forKey: "repo.ref")
        persistWorkspacePreferences()
        defaults.set(githubOAuthClientID, forKey: "github.oauth.clientID")
        defaults.set(githubOAuthExchangeEndpoint, forKey: "github.oauth.exchangeEndpoint")
        defaults.set(githubOAuthState, forKey: "github.oauth.state")
        defaults.set(supabaseURL, forKey: "supabase.url")
        defaults.set(supabaseAnonKey, forKey: "supabase.anonKey")
        if token.isEmpty {
            KeychainStore.delete(service: keychainService, account: githubTokenAccount)
        } else {
            KeychainStore.save(token, service: keychainService, account: githubTokenAccount)
        }
        if geminiAPIKey.isEmpty {
            KeychainStore.delete(service: keychainService, account: geminiKeyAccount)
        } else {
            KeychainStore.save(geminiAPIKey, service: keychainService, account: geminiKeyAccount)
        }
        if supabaseAccessToken.isEmpty {
            KeychainStore.delete(service: keychainService, account: supabaseAccessTokenAccount)
        } else {
            KeychainStore.save(supabaseAccessToken, service: keychainService, account: supabaseAccessTokenAccount)
        }
        if supabaseRefreshToken.isEmpty {
            KeychainStore.delete(service: keychainService, account: supabaseRefreshTokenAccount)
        } else {
            KeychainStore.save(supabaseRefreshToken, service: keychainService, account: supabaseRefreshTokenAccount)
        }
        client.token = token
        gemini.apiKey = geminiAPIKey
        configureSupabaseClient()
    }

    func loadSettings() {
        let owner = defaults.string(forKey: "repo.owner") ?? repo.owner
        let name = defaults.string(forKey: "repo.name") ?? repo.name
        repo = RepoRef(owner: owner, name: name)
        token = KeychainStore.read(service: keychainService, account: githubTokenAccount)
        if token.isEmpty, let legacyToken = defaults.string(forKey: "github.token"), !legacyToken.isEmpty {
            token = legacyToken
            KeychainStore.save(legacyToken, service: keychainService, account: githubTokenAccount)
            defaults.removeObject(forKey: "github.token")
        }
        geminiAPIKey = KeychainStore.read(service: keychainService, account: geminiKeyAccount)
        supabaseAccessToken = KeychainStore.read(service: keychainService, account: supabaseAccessTokenAccount)
        supabaseRefreshToken = KeychainStore.read(service: keychainService, account: supabaseRefreshTokenAccount)
        repoRef = defaults.string(forKey: "repo.ref") ?? "HEAD"
        githubOAuthClientID = defaults.string(forKey: "github.oauth.clientID") ?? ""
        githubOAuthExchangeEndpoint = defaults.string(forKey: "github.oauth.exchangeEndpoint") ?? ""
        githubOAuthState = defaults.string(forKey: "github.oauth.state") ?? ""
        supabaseURL = defaults.string(forKey: "supabase.url") ?? ""
        supabaseAnonKey = defaults.string(forKey: "supabase.anonKey") ?? ""
        if let savedMode = WorkspaceMode(rawValue: defaults.string(forKey: "workspace.mode") ?? "") {
            mode = savedMode
        }
        if let savedPullFilter = PullStateFilter(rawValue: defaults.string(forKey: "workspace.pullFilter") ?? "") {
            pullFilter = savedPullFilter
        }
        if let savedActiveTab = WorkspaceTab(rawValue: defaults.string(forKey: "workspace.activeTab") ?? "") {
            activeTab = savedActiveTab
        }
        gemini.apiKey = geminiAPIKey
        configureSupabaseClient()
    }

    private func persistWorkspacePreferences() {
        defaults.set(mode.rawValue, forKey: "workspace.mode")
        defaults.set(pullFilter.rawValue, forKey: "workspace.pullFilter")
        defaults.set(activeTab.rawValue, forKey: "workspace.activeTab")
    }

    func loadLocalCollections() {
        if let data = defaults.data(forKey: "savedPulls"),
           let decoded = try? jsonDecoder.decode([SavedPull].self, from: data) {
            savedPulls = decoded
        }
        if let data = defaults.data(forKey: "recentRepos"),
           let decoded = try? jsonDecoder.decode([RecentRepo].self, from: data) {
            recentRepos = decoded
        }
        if let data = defaults.data(forKey: "aiDrafts"),
           let decoded = try? jsonDecoder.decode([AIDraft].self, from: data) {
            aiDrafts = decoded
        }
    }

    func persistLocalCollections() {
        if let data = try? jsonEncoder.encode(savedPulls) {
            defaults.set(data, forKey: "savedPulls")
        }
        if let data = try? jsonEncoder.encode(recentRepos) {
            defaults.set(data, forKey: "recentRepos")
        }
        if let data = try? jsonEncoder.encode(aiDrafts) {
            defaults.set(data, forKey: "aiDrafts")
        }
    }

    func configureSupabaseClient() {
        githubOAuthExchange.endpoint = githubOAuthExchangeEndpoint
        supabaseAuth.projectURL = supabaseURL
        supabaseAuth.anonKey = supabaseAnonKey
        supabasePreferences.projectURL = supabaseURL
        supabasePreferences.anonKey = supabaseAnonKey
        supabasePreferences.accessToken = supabaseAccessToken
    }

    func refreshCurrentMode() async {
        switch mode {
        case .pulls:
            await loadPulls()
        case .branches:
            await loadBranches()
        case .code:
            await loadRepoTree()
        }
    }

    func loadAccount() async {
        client.token = token
        do {
            viewer = try await client.fetchViewer()
            statusMessage = "Signed in as \(viewer?.login ?? "GitHub")"
            errorMessage = nil
        } catch {
            viewer = nil
            errorMessage = error.localizedDescription
        }
    }

    func loadPulls() async {
        pullsPage = 1
        hasMorePulls = true
        isLoading = true
        defer { isLoading = false }
        client.token = token
        do {
            rememberCurrentRepo()
            let result = try await client.fetchPulls(repo: repo, state: pullFilter, page: pullsPage)
            pulls = result.sorted { $0.number > $1.number }
            hasMorePulls = result.count >= 50
            if selectedPull == nil, let first = pulls.first {
                await selectPull(first)
            }
            statusMessage = "Loaded \(pulls.count) pull requests"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMorePulls() async {
        guard hasMorePulls, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let nextPage = pullsPage + 1
            let result = try await client.fetchPulls(repo: repo, state: pullFilter, page: nextPage)
            pullsPage = nextPage
            hasMorePulls = result.count >= 50
            pulls = (pulls + result).sorted { $0.number > $1.number }
            statusMessage = "Loaded \(pulls.count) pull requests"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPull(_ pull: PullRequest) async {
        selectedPull = pull
        metadataTitle = pull.title
        metadataBody = pull.body ?? ""
        labelsDraft = (pull.labels ?? []).map(\.name).joined(separator: ", ")
        inlineCommentPath = ""
        inlineCommentLine = ""
        activeTab = .diff
        await loadPullSnapshot(number: pull.number)
    }

    func loadPullSnapshot(number: Int) async {
        detailLoading = true
        defer { detailLoading = false }
        client.token = token

        do {
            async let pullValue = client.fetchPull(repo: repo, number: number)
            async let filesValue = client.fetchPullFiles(repo: repo, number: number)
            async let commentsValue = client.fetchIssueComments(repo: repo, number: number)
            async let reviewCommentsValue = client.fetchReviewComments(repo: repo, number: number)
            async let reviewsValue = client.fetchReviews(repo: repo, number: number)
            async let commitsValue = client.fetchCommits(repo: repo, number: number)
            async let timelineValue = client.fetchTimeline(repo: repo, number: number)

            let pull = try await pullValue
            let commits = try await commitsValue
            let checks: [CheckRun]
            if let sha = pull.head?.sha {
                checks = (try? await client.fetchChecks(repo: repo, ref: sha)) ?? []
            } else {
                checks = []
            }

            pullSnapshot = PullSnapshot(
                pull: pull,
                files: try await filesValue,
                comments: try await commentsValue,
                reviewComments: try await reviewCommentsValue,
                reviews: try await reviewsValue,
                commits: commits,
                checks: checks,
                timeline: try await timelineValue
            )
            selectedPull = pull
            metadataTitle = pull.title
            metadataBody = pull.body ?? ""
            labelsDraft = (pull.labels ?? []).map(\.name).joined(separator: ", ")
            statusMessage = "Loaded #\(pull.number)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadBranches() async {
        branchesPage = 1
        hasMoreBranches = true
        isLoading = true
        defer { isLoading = false }
        client.token = token
        do {
            rememberCurrentRepo()
            async let repoInfoValue = client.fetchRepoInfo(repo: repo)
            async let branchesValue = client.fetchBranches(repo: repo)
            let info = try await repoInfoValue
            defaultBranch = info.defaultBranch ?? defaultBranch
            pullBase = defaultBranch
            branches = try await branchesValue
            hasMoreBranches = branches.count >= 100
            if selectedBranch == nil, let first = branches.first {
                await selectBranch(first)
            }
            statusMessage = "Loaded \(branches.count) branches"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreBranches() async {
        guard hasMoreBranches, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let nextPage = branchesPage + 1
            let result = try await client.fetchBranches(repo: repo, page: nextPage)
            branchesPage = nextPage
            hasMoreBranches = result.count >= 100
            branches += result
            statusMessage = "Loaded \(branches.count) branches"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectBranch(_ branch: Branch) async {
        selectedBranch = branch
        await loadBranchSnapshot(branch: branch)
    }

    func loadBranchSnapshot(branch: Branch) async {
        detailLoading = true
        defer { detailLoading = false }
        do {
            let comparison = try await client.compare(repo: repo, base: defaultBranch, head: branch.name)
            branchSnapshot = BranchSnapshot(
                branch: branch,
                base: defaultBranch,
                files: comparison.files ?? [],
                commits: comparison.commits ?? []
            )
            statusMessage = "Compared \(branch.name) with \(defaultBranch)"
            errorMessage = nil
        } catch {
            branchSnapshot = BranchSnapshot(branch: branch, base: defaultBranch)
            errorMessage = error.localizedDescription
        }
    }

    func loadRepoTree() async {
        isLoading = true
        defer { isLoading = false }
        client.token = token
        do {
            rememberCurrentRepo()
            let target = repoRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "HEAD" : repoRef
            let response = try await client.fetchTree(repo: repo, ref: target)
            repoFiles = response.tree.sorted { $0.path < $1.path }
            if selectedRepoFile == nil, let first = filteredRepoFiles.first {
                await selectRepoFile(first)
            }
            statusMessage = response.truncated == true ? "Loaded truncated tree" : "Loaded repository tree"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectRepoFile(_ file: RepoTreeItem) async {
        selectedRepoFile = file
        detailLoading = true
        defer { detailLoading = false }
        do {
            let target = repoRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "HEAD" : repoRef
            let content = try await client.fetchContent(repo: repo, path: file.path, ref: target)
            repoFileSHA = content.sha
            repoFileContent = decodeRepoContent(content)
            repoFileIsLikelyBinary = isLikelyBinary(repoFileContent)
            repoFileIsLarge = FileSizePolicy.isLarge(repoFileContent)
            originalRepoFileContent = repoFileContent
            commitMessage = "Update \(file.path)"
            errorMessage = nil
        } catch {
            repoFileContent = ""
            originalRepoFileContent = ""
            repoFileIsLikelyBinary = false
            repoFileIsLarge = false
            repoFileSHA = nil
            errorMessage = error.localizedDescription
        }
    }

    func revertRepoFileEdits() {
        repoFileContent = originalRepoFileContent
    }

    func loadConflictBaseForSelectedFile() async {
        guard let file = selectedRepoFile else {
            errorMessage = "Select a repository file first."
            return
        }
        let baseRef = selectedPull?.base?.ref ?? defaultBranch
        do {
            let content = try await client.fetchContent(repo: repo, path: file.path, ref: baseRef)
            conflictBaseContent = decodeRepoContent(content)
            conflictBaseRef = baseRef
            statusMessage = "Loaded \(file.path) from \(baseRef)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replaceEditorWithConflictBase() {
        guard !conflictBaseContent.isEmpty else { return }
        repoFileContent = conflictBaseContent
        repoFileIsLikelyBinary = isLikelyBinary(repoFileContent)
        repoFileIsLarge = FileSizePolicy.isLarge(repoFileContent)
    }

    func resolveFirstConflict(choice: ConflictChoice) {
        resolveConflict(blockID: 0, choice: choice)
    }

    func resolveConflict(blockID: Int, choice: ConflictChoice) {
        repoFileContent = ConflictMarkerParser.resolve(in: repoFileContent, blockID: blockID, choice: choice)
        repoFileIsLikelyBinary = isLikelyBinary(repoFileContent)
        updateConflictResolutionStatus()
    }

    func resolveAllConflicts(choice: ConflictChoice) {
        repoFileContent = ConflictMarkerParser.resolveAll(in: repoFileContent, choice: choice)
        repoFileIsLikelyBinary = isLikelyBinary(repoFileContent)
        updateConflictResolutionStatus()
    }

    func resolveConflicts(choicesByBlockID: [Int: ConflictChoice]) {
        repoFileContent = ConflictMarkerParser.resolve(in: repoFileContent, choicesByBlockID: choicesByBlockID)
        repoFileIsLikelyBinary = isLikelyBinary(repoFileContent)
        updateConflictResolutionStatus()
    }

    private func updateConflictResolutionStatus() {
        let remaining = conflictBlocks.count
        if remaining == 0 {
            statusMessage = "All conflict markers resolved."
            errorMessage = nil
        } else {
            statusMessage = "\(remaining) conflict marker\(remaining == 1 ? "" : "s") still unresolved."
        }
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "diffmac" else { return }
        let host = url.host() ?? ""
        let code = OAuthCallbackParser.githubCode(from: url)
        let state = OAuthCallbackParser.githubState(from: url)
        let accessToken = OAuthCallbackParser.supabaseAccessToken(from: url)
        let refreshToken = OAuthCallbackParser.supabaseRefreshToken(from: url)

        switch host {
        case "github-oauth":
            if let code, !code.isEmpty {
                oauthCallbackMessage = "Received GitHub OAuth code. Exchanging..."
                statusMessage = oauthCallbackMessage
                Task { await exchangeGitHubOAuthCode(code, state: state) }
                return
            } else {
                oauthCallbackMessage = "GitHub OAuth callback received without a code."
            }
        case "supabase-auth":
            if let accessToken, !accessToken.isEmpty {
                supabaseAccessToken = accessToken
                if let refreshToken, !refreshToken.isEmpty {
                    supabaseRefreshToken = refreshToken
                }
                saveSettings()
                oauthCallbackMessage = refreshToken?.isEmpty == false
                    ? "Supabase session saved from callback."
                    : "Supabase access token saved from callback."
            } else {
                oauthCallbackMessage = "Supabase callback received without an access token."
            }
        default:
            oauthCallbackMessage = "Received callback: \(url.absoluteString)"
        }
        statusMessage = oauthCallbackMessage
    }

    func exchangeGitHubOAuthCode(_ code: String, state: String? = nil) async {
        saveSettings()
        githubOAuthExchange.endpoint = githubOAuthExchangeEndpoint
        do {
            if !githubOAuthState.isEmpty, state != githubOAuthState {
                throw GitHubOAuthExchangeError.stateMismatch
            }
            token = try await githubOAuthExchange.exchange(code: code, state: state)
            githubOAuthState = ""
            saveSettings()
            await loadAccount()
            oauthCallbackMessage = "GitHub browser sign-in complete."
            statusMessage = oauthCallbackMessage
            errorMessage = nil
        } catch {
            oauthCallbackMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            statusMessage = oauthCallbackMessage
        }
    }

    func prepareGitHubBrowserOAuthURL() -> URL? {
        guard (try? GitHubOAuthExchangeClient.validatedEndpointURL(githubOAuthExchangeEndpoint)) != nil else {
            oauthCallbackMessage = GitHubOAuthExchangeError.invalidEndpoint.localizedDescription
            statusMessage = oauthCallbackMessage
            return nil
        }
        githubOAuthState = UUID().uuidString
        saveSettings()
        return try? GitHubOAuthURLBuilder.authorizeURL(clientID: githubOAuthClientID, state: githubOAuthState)
    }

    var canStartGitHubBrowserOAuth: Bool {
        !githubOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? GitHubOAuthExchangeClient.validatedEndpointURL(githubOAuthExchangeEndpoint)) != nil
    }

    var githubOAuthCallbackURL: String {
        "diffmac://github-oauth"
    }

    var supabaseAuthCallbackURL: String {
        "diffmac://supabase-auth"
    }

    func supabaseAuthorizeURL(provider: String = "github") -> URL? {
        try? SupabaseAuthURLBuilder.authorizeURL(projectURL: supabaseURL, provider: provider)
    }

    func refreshSupabaseSession() async {
        saveSettings()
        configureSupabaseClient()
        do {
            try await refreshSupabaseSessionIfNeeded(force: true)
            supabaseSyncMessage = "Refreshed Supabase session."
            statusMessage = supabaseSyncMessage
            errorMessage = nil
        } catch {
            supabaseSyncMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func toggleSavedSelectedPull() {
        guard let pull = selectedPull else { return }
        if let index = savedPulls.firstIndex(where: { $0.owner == repo.owner && $0.repo == repo.name && $0.number == pull.number }) {
            savedPulls.remove(at: index)
        } else {
            savedPulls.insert(
                SavedPull(
                    owner: repo.owner,
                    repo: repo.name,
                    number: pull.number,
                    title: pull.title,
                    state: pull.state,
                    htmlURL: pull.htmlURL,
                    savedAt: Date()
                ),
                at: 0
            )
        }
        savedPulls = Array(savedPulls.prefix(50))
        persistLocalCollections()
    }

    func openSavedPull(_ saved: SavedPull) async {
        repo = RepoRef(owner: saved.owner, name: saved.repo)
        saveSettings()
        mode = .pulls
        do {
            let pull = try await client.fetchPull(repo: repo, number: saved.number)
            await selectPull(pull)
            statusMessage = "Opened \(saved.id)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openRecentRepo(_ recent: RecentRepo) async {
        repo = RepoRef(owner: recent.owner, name: recent.repo)
        saveSettings()
        await refreshCurrentMode()
    }

    private func rememberCurrentRepo() {
        let recent = RecentRepo(owner: repo.owner, repo: repo.name, viewedAt: Date())
        recentRepos.removeAll { $0.id == recent.id }
        recentRepos.insert(recent, at: 0)
        recentRepos = Array(recentRepos.prefix(20))
        persistLocalCollections()
    }

    func postComment() async {
        guard let pull = selectedPull, !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try await client.postIssueComment(repo: repo, number: pull.number, body: commentDraft)
            commentDraft = ""
            await loadPullSnapshot(number: pull.number)
            statusMessage = "Comment posted"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitReview(event: String) async {
        guard let pull = selectedPull else { return }
        do {
            try await client.submitReview(repo: repo, number: pull.number, body: reviewDraft, event: event)
            reviewDraft = ""
            await loadPullSnapshot(number: pull.number)
            statusMessage = "Review submitted"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePullMetadata() async {
        guard let pull = selectedPull else { return }
        do {
            let updated = try await client.updatePull(repo: repo, number: pull.number, title: metadataTitle, body: metadataBody)
            let labels = labelsDraft
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            try await client.replaceLabels(repo: repo, number: pull.number, labels: labels)
            selectedPull = updated
            await loadPullSnapshot(number: pull.number)
            statusMessage = "Pull request updated"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func postInlineReviewComment() async {
        guard
            let pull = selectedPull,
            let commitID = pull.head?.sha,
            !inlineCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let line = Int(inlineCommentLine.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            errorMessage = "Inline comment needs a body, file path, pull head SHA, and line."
            return
        }

        let path = inlineCommentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            errorMessage = "Inline comment path is required."
            return
        }

        do {
            try await client.postReviewComment(repo: repo, number: pull.number, body: inlineCommentDraft, commitID: commitID, path: path, line: line, side: inlineCommentSide)
            inlineCommentDraft = ""
            await loadPullSnapshot(number: pull.number)
            statusMessage = "Inline review comment posted"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePullBranch() async {
        guard let pull = selectedPull else { return }
        do {
            try await client.updateBranch(repo: repo, number: pull.number)
            await loadPullSnapshot(number: pull.number)
            statusMessage = "Branch update requested"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePullHeadBranch() async {
        guard let pull = selectedPull, let branchName = pull.head?.ref else { return }
        do {
            try await client.deleteBranch(repo: repo, name: branchName)
            statusMessage = "Deleted \(branchName)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func mergePull(method: String) async {
        guard let pull = selectedPull else { return }
        do {
            try await client.mergePull(repo: repo, number: pull.number, method: method)
            await loadPullSnapshot(number: pull.number)
            statusMessage = "Merge action completed"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commitRepoFile() async {
        guard let file = selectedRepoFile else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "Commit message is required."
            return
        }
        guard !hasUnresolvedConflicts else {
            errorMessage = "Resolve all conflict markers before committing."
            return
        }

        do {
            let target = repoRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultBranch : repoRef
            try await client.updateContent(
                repo: repo,
                path: file.path,
                sha: repoFileSHA,
                branch: target,
                content: repoFileContent,
                message: message
            )
            await selectRepoFile(file)
            statusMessage = "Committed \(file.path)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runLivePollingLoop() async {
        while !Task.isCancelled {
            let delay = max(livePollingIntervalSeconds, 15)
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled, livePollingEnabled else { continue }
            if mode == .pulls, let pull = selectedPull {
                await loadPullSnapshot(number: pull.number)
            }
        }
    }

    func createRepoFile() async {
        let path = newFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = newFileCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !message.isEmpty else {
            errorMessage = "New file path and commit message are required."
            return
        }
        guard !RepoPathValidator.isInvalid(path) else {
            errorMessage = "New file path is invalid."
            return
        }
        guard !FileSizePolicy.isLarge(newFileContent) else {
            errorMessage = "New file is too large for the built-in editor."
            return
        }

        do {
            let target = repoRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultBranch : repoRef
            try await client.updateContent(repo: repo, path: path, sha: nil, branch: target, content: newFileContent, message: message)
            createFileMode = false
            newFilePath = ""
            newFileContent = ""
            newFileCommitMessage = ""
            await loadRepoTree()
            statusMessage = "Created \(path)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createBranch() async {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Branch name is required."
            return
        }
        let source = selectedBranch?.commit.sha ?? branches.first(where: { $0.name == defaultBranch })?.commit.sha
        guard let source else {
            errorMessage = "Select or load a source branch first."
            return
        }
        do {
            try await client.createBranch(repo: repo, name: name, sourceSHA: source)
            newBranchName = ""
            await loadBranches()
            statusMessage = "Created \(name)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createPullRequest() async {
        let payload = CreatePullPayload(
            title: pullTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            body: pullBody,
            head: pullHead.trimmingCharacters(in: .whitespacesAndNewlines),
            base: pullBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultBranch : pullBase.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !payload.title.isEmpty, !payload.head.isEmpty, !payload.base.isEmpty else {
            errorMessage = "Pull title, head, and base are required."
            return
        }
        do {
            let pull = try await client.createPull(repo: repo, payload: payload)
            pullTitle = ""
            pullBody = ""
            pullHead = ""
            pullBase = defaultBranch
            mode = .pulls
            await loadPulls()
            await selectPull(pull)
            statusMessage = "Created #\(pull.number)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func draftFixFromFirstReviewComment() async {
        guard let snapshot = pullSnapshot,
              let comment = snapshot.reviewComments.first(where: { ($0.path ?? "").isEmpty == false }),
              let path = comment.path else {
            errorMessage = "No review comment with a file path is available."
            return
        }
        do {
            let ref = selectedPull?.head?.ref ?? repoRef
            let content = try await client.fetchContent(repo: repo, path: path, ref: ref)
            let decoded = decodeRepoContent(content)
            let draft = try await gemini.draftFix(comment: comment, filePath: path, fileContent: decoded)
            repoRef = ref
            mode = .code
            selectedRepoFile = RepoTreeItem(path: path, mode: nil, type: "blob", sha: content.sha ?? "", size: nil)
            repoFileSHA = content.sha
            repoFileContent = draft
            repoFileIsLikelyBinary = false
            repoFileIsLarge = FileSizePolicy.isLarge(draft)
            commitMessage = "Address review for \(path)"
            let aiDraft = AIDraft(
                id: "\(repo.owner)/\(repo.name)#\(snapshot.pull.number):\(path):\(comment.id)",
                owner: repo.owner,
                repo: repo.name,
                pullNumber: snapshot.pull.number,
                pullTitle: snapshot.pull.title,
                branch: ref,
                path: path,
                commentID: comment.id,
                commentBody: comment.body,
                originalContent: decoded,
                draftContent: draft,
                summary: "Drafted fix for \(path)",
                updatedAt: Date()
            )
            aiDrafts.removeAll { $0.id == aiDraft.id }
            aiDrafts.insert(aiDraft, at: 0)
            aiDrafts = Array(aiDrafts.prefix(50))
            persistLocalCollections()
            statusMessage = "Drafted fix for \(path)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openAIDraft(_ draft: AIDraft) {
        repo = RepoRef(owner: draft.owner, name: draft.repo)
        repoRef = draft.branch
        mode = .code
        createFileMode = false
        selectedRepoFile = RepoTreeItem(path: draft.path, mode: nil, type: "blob", sha: "", size: nil)
        repoFileSHA = nil
        repoFileContent = draft.draftContent
        originalRepoFileContent = draft.originalContent
        commitMessage = "Address review for \(draft.path)"
        statusMessage = "Opened saved draft for \(draft.path)"
        saveSettings()
    }

    func deleteAIDraft(_ draft: AIDraft) {
        aiDrafts.removeAll { $0.id == draft.id }
        persistLocalCollections()
    }

    func loadCheckAnnotations(for check: CheckRun) async {
        guard loadingCheckAnnotations.contains(check.id) == false else { return }
        loadingCheckAnnotations.insert(check.id)
        defer { loadingCheckAnnotations.remove(check.id) }
        do {
            let annotations = try await client.fetchCheckAnnotations(repo: repo, checkRunID: check.id)
            checkAnnotations[check.id] = annotations
            statusMessage = annotations.isEmpty ? "No annotations for \(check.name)" : "Loaded \(annotations.count) annotations"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startGitHubDeviceOAuth() async {
        saveSettings()
        deviceUserCode = ""
        deviceVerificationURL = nil
        deviceOAuthMessage = ""
        do {
            let response = try await deviceOAuth.requestDeviceCode(clientID: githubOAuthClientID)
            deviceUserCode = response.userCode
            deviceVerificationURL = response.verificationURI
            deviceOAuthMessage = "Enter \(response.userCode) on GitHub, then wait for this app to finish."
            await pollGitHubDeviceOAuth(deviceCode: response.deviceCode, interval: response.interval, expiresIn: response.expiresIn)
        } catch {
            deviceOAuthMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func pushSupabasePreferences() async {
        saveSettings()
        configureSupabaseClient()
        do {
            try await refreshSupabaseSessionIfNeeded()
            try await pushCurrentSupabasePreferences()
            supabaseSyncMessage = "Pushed preferences to Supabase."
            statusMessage = supabaseSyncMessage
            errorMessage = nil
        } catch {
            supabaseSyncMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func pullSupabasePreferences() async {
        saveSettings()
        configureSupabaseClient()
        do {
            try await refreshSupabaseSessionIfNeeded()
            guard let preferences = try await performSupabaseRequestWithRefreshRetry(operation: {
                try await self.supabasePreferences.fetchPreferences()
            }) else {
                supabaseSyncMessage = "No Supabase preferences row exists yet."
                statusMessage = supabaseSyncMessage
                return
            }
            if let owner = preferences.defaultRepoOwner, let name = preferences.defaultRepoName, !owner.isEmpty, !name.isEmpty {
                repo = RepoRef(owner: owner, name: name)
            }
            if let remoteRecent = preferences.recentRepos {
                let decoded = remoteRecent.map {
                    RecentRepo(
                        owner: $0.owner,
                        repo: $0.repo,
                        viewedAt: dateFromISOString($0.lastViewedAt) ?? Date()
                    )
                }
                recentRepos = PreferenceMerge.recentRepos(local: recentRepos, remote: decoded)
            }
            if let remoteSaved = preferences.savedPulls {
                let decoded = remoteSaved.map {
                    SavedPull(
                        owner: $0.owner,
                        repo: $0.repo,
                        number: $0.pullNumber,
                        title: $0.title,
                        state: $0.state,
                        htmlURL: URL(string: $0.htmlURL),
                        savedAt: dateFromISOString($0.savedAt) ?? Date()
                    )
                }
                savedPulls = PreferenceMerge.savedPulls(local: savedPulls, remote: decoded)
            }
            if let remoteDrafts = preferences.aiDrafts {
                let decoded = remoteDrafts.map {
                    AIDraft(
                        id: $0.id,
                        owner: $0.owner,
                        repo: $0.repo,
                        pullNumber: $0.pullNumber,
                        pullTitle: $0.pullTitle,
                        branch: $0.branch,
                        path: $0.path,
                        commentID: $0.commentID,
                        commentBody: $0.commentBody,
                        originalContent: $0.originalContent,
                        draftContent: $0.draftContent,
                        summary: $0.summary,
                        updatedAt: dateFromISOString($0.updatedAt) ?? Date()
                    )
                }
                aiDrafts = PreferenceMerge.aiDrafts(local: aiDrafts, remote: decoded)
            }
            saveSettings()
            persistLocalCollections()
            try await pushCurrentSupabasePreferences()
            supabaseSyncMessage = "Pulled and merged preferences from Supabase."
            statusMessage = supabaseSyncMessage
            errorMessage = nil
        } catch {
            supabaseSyncMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSupabaseSessionIfNeeded(force: Bool = false) async throws {
        let hasRefreshToken = !supabaseRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasRefreshToken else { return }
        guard force || JWTClaims.isExpiredOrExpiringSoon(supabaseAccessToken) else { return }

        let session = try await supabaseAuth.refreshSession(refreshToken: supabaseRefreshToken)
        supabaseAccessToken = session.accessToken
        if let refreshToken = session.refreshToken, !refreshToken.isEmpty {
            supabaseRefreshToken = refreshToken
        }
        saveSettings()
        configureSupabaseClient()
    }

    private func performSupabaseRequestWithRefreshRetry<T: Sendable>(operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as SupabasePreferencesError where error.statusCode == 401 {
            try await refreshSupabaseSessionIfNeeded(force: true)
            return try await operation()
        }
    }

    private func pushCurrentSupabasePreferences() async throws {
        let userID = try supabasePreferences.userIDFromAccessToken()
        let preferences = SupabasePreferences(
            userID: userID,
            defaultRepoOwner: repo.owner,
            defaultRepoName: repo.name,
            recentRepos: recentRepos.map {
                SupabaseRecentRepo(
                    owner: $0.owner,
                    repo: $0.repo,
                    lastViewedAt: isoString($0.viewedAt)
                )
            },
            savedPulls: savedPulls.map {
                SupabaseSavedPull(
                    owner: $0.owner,
                    repo: $0.repo,
                    pullNumber: $0.number,
                    title: $0.title,
                    htmlURL: $0.htmlURL?.absoluteString ?? "",
                    state: $0.state,
                    draft: false,
                    savedAt: isoString($0.savedAt)
                )
            },
            aiDrafts: aiDrafts.map {
                SupabaseAIDraft(
                    id: $0.id,
                    owner: $0.owner,
                    repo: $0.repo,
                    pullNumber: $0.pullNumber,
                    pullTitle: $0.pullTitle,
                    branch: $0.branch,
                    path: $0.path,
                    commentID: $0.commentID,
                    commentBody: $0.commentBody,
                    originalContent: $0.originalContent,
                    draftContent: $0.draftContent,
                    summary: $0.summary,
                    updatedAt: isoString($0.updatedAt)
                )
            }
        )
        try await performSupabaseRequestWithRefreshRetry {
            try await self.supabasePreferences.upsertPreferences(preferences)
        }
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func dateFromISOString(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private func pollGitHubDeviceOAuth(deviceCode: String, interval: Int, expiresIn: Int) async {
        isPollingDeviceOAuth = true
        defer { isPollingDeviceOAuth = false }
        let started = Date()
        var delaySeconds = max(interval, 5)

        while Date().timeIntervalSince(started) < Double(expiresIn) {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            do {
                token = try await deviceOAuth.pollForToken(clientID: githubOAuthClientID, deviceCode: deviceCode)
                saveSettings()
                await loadAccount()
                await refreshCurrentMode()
                deviceOAuthMessage = "GitHub sign-in complete."
                errorMessage = nil
                return
            } catch DeviceOAuthError.authorizationPending {
                deviceOAuthMessage = "Waiting for GitHub authorization..."
            } catch DeviceOAuthError.slowDown {
                delaySeconds += 5
                deviceOAuthMessage = "GitHub asked us to slow down. Still waiting..."
            } catch {
                deviceOAuthMessage = error.localizedDescription
                errorMessage = error.localizedDescription
                return
            }
        }
        deviceOAuthMessage = "GitHub device code expired. Start sign-in again."
    }

    private func decodeRepoContent(_ content: RepoContent) -> String {
        guard let raw = content.content else { return "" }
        if content.encoding == "base64" {
            let cleaned = raw.replacingOccurrences(of: "\n", with: "")
            guard let data = Data(base64Encoded: cleaned) else { return raw }
            return String(data: data, encoding: .utf8) ?? raw
        }
        return raw
    }

    private func isLikelyBinary(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value == 0 || (scalar.value < 9 && scalar.value != 10 && scalar.value != 13)
        }
    }
}
