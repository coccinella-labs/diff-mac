import Foundation
import Testing
@testable import DIFFMac

@Test func repoDisplayNameCombinesOwnerAndName() {
    let repo = RepoRef(owner: "bniladridas", name: "diff")
    #expect(repo.displayName == "bniladridas/diff")
}

@Test func savedPullIDMatchesRepoAndNumber() {
    let pull = SavedPull(
        owner: "bniladridas",
        repo: "diff",
        number: 42,
        title: "Test",
        state: "open",
        htmlURL: URL(string: "https://github.com/bniladridas/diff/pull/42"),
        savedAt: Date(timeIntervalSince1970: 0)
    )
    #expect(pull.id == "bniladridas/diff#42")
}

@Test func preferenceMergeKeepsLocalAndRemoteSavedPulls() {
    let local = SavedPull(
        owner: "owner",
        repo: "repo",
        number: 1,
        title: "Local",
        state: "open",
        htmlURL: nil,
        savedAt: Date(timeIntervalSince1970: 20)
    )
    let remote = SavedPull(
        owner: "owner",
        repo: "repo",
        number: 2,
        title: "Remote",
        state: "open",
        htmlURL: nil,
        savedAt: Date(timeIntervalSince1970: 10)
    )

    let merged = PreferenceMerge.savedPulls(local: [local], remote: [remote])
    #expect(merged.map(\.id) == ["owner/repo#1", "owner/repo#2"])
}

@Test func preferenceMergePrefersNewestMatchingRecentRepo() {
    let local = RecentRepo(owner: "owner", repo: "repo", viewedAt: Date(timeIntervalSince1970: 10))
    let remote = RecentRepo(owner: "owner", repo: "repo", viewedAt: Date(timeIntervalSince1970: 20))

    let merged = PreferenceMerge.recentRepos(local: [local], remote: [remote])
    #expect(merged.count == 1)
    #expect(merged[0].viewedAt == Date(timeIntervalSince1970: 20))
}

@Test func preferenceMergePrefersNewestMatchingAIDraft() {
    let local = AIDraft(
        id: "draft-1",
        owner: "owner",
        repo: "repo",
        pullNumber: 1,
        pullTitle: "PR",
        branch: "main",
        path: "a.swift",
        commentID: 1,
        commentBody: "old",
        originalContent: "old",
        draftContent: "local",
        summary: "local",
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    let remote = AIDraft(
        id: "draft-1",
        owner: "owner",
        repo: "repo",
        pullNumber: 1,
        pullTitle: "PR",
        branch: "main",
        path: "a.swift",
        commentID: 1,
        commentBody: "old",
        originalContent: "old",
        draftContent: "remote",
        summary: "remote",
        updatedAt: Date(timeIntervalSince1970: 20)
    )

    let merged = PreferenceMerge.aiDrafts(local: [local], remote: [remote])
    #expect(merged.count == 1)
    #expect(merged[0].draftContent == "local")
}

@Test func supabaseUserIDCanBeDecodedFromJWT() throws {
    let payload = #"{"sub":"user-123"}"#
    let encodedPayload = Data(payload.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    let client = SupabasePreferencesClient()
    client.accessToken = "header.\(encodedPayload).signature"
    #expect(try client.userIDFromAccessToken() == "user-123")
}

@Test func supabaseUserIDRejectsMalformedJWT() {
    let client = SupabasePreferencesClient()
    client.accessToken = "not-a-jwt"
    #expect(throws: SupabasePreferencesError.self) {
        try client.userIDFromAccessToken()
    }
}

@Test func supabaseHTTPErrorExposesStatusCode() {
    let error = SupabasePreferencesError.http(401, "JWT expired")
    #expect(error.statusCode == 401)
    #expect(SupabasePreferencesError.missingConfig.statusCode == nil)
}

@Test func jwtClaimsDetectExpiringToken() {
    let now = Date(timeIntervalSince1970: 1_000)
    let token = jwtToken(payload: #"{"sub":"user-123","exp":1200}"#)
    #expect(JWTClaims.subject(from: token) == "user-123")
    #expect(JWTClaims.isExpiredOrExpiringSoon(token, now: now, leeway: 300))
}

@Test func jwtClaimsDetectTokenWithEnoughTimeRemaining() {
    let now = Date(timeIntervalSince1970: 1_000)
    let token = jwtToken(payload: #"{"sub":"user-123","exp":2000}"#)
    #expect(!JWTClaims.isExpiredOrExpiringSoon(token, now: now, leeway: 300))
}

@Test func aiDraftRetainsStableIdentifier() {
    let draft = AIDraft(
        id: "bniladridas/diff#12:Sources/App.swift:99",
        owner: "bniladridas",
        repo: "diff",
        pullNumber: 12,
        pullTitle: "Fix review",
        branch: "feature/review",
        path: "Sources/App.swift",
        commentID: 99,
        commentBody: "Please handle nil.",
        originalContent: "let value = value!",
        draftContent: "guard let value else { return }",
        summary: "Drafted fix",
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    #expect(draft.id == "bniladridas/diff#12:Sources/App.swift:99")
}

@Test func checkAnnotationIDIncludesLocationAndMessage() {
    let annotation = CheckAnnotation(
        path: "Sources/App.swift",
        startLine: 10,
        endLine: 12,
        annotationLevel: "warning",
        title: "Lint",
        message: "Use let",
        rawDetails: nil
    )
    #expect(annotation.id == "Sources/App.swift:10:12:Use let")
}

@Test func conflictParserFindsBlocks() {
    let text = """
    before
    <<<<<<< HEAD
    ours
    =======
    theirs
    >>>>>>> branch
    after
    """
    let blocks = ConflictMarkerParser.blocks(in: text)
    #expect(blocks.count == 1)
    #expect(blocks[0].ours == "ours")
    #expect(blocks[0].theirs == "theirs")
}

@Test func conflictParserResolvesOurs() {
    let text = """
    before
    <<<<<<< HEAD
    ours
    =======
    theirs
    >>>>>>> branch
    after
    """
    let resolved = ConflictMarkerParser.resolveFirst(in: text, choice: .ours)
    #expect(resolved == "before\nours\nafter")
}

@Test func conflictBlockResolvedTextPreviewsChoice() {
    let block = ConflictBlock(id: 0, startLine: 1, endLine: 5, ours: "ours", theirs: "theirs")
    #expect(block.resolvedText(choice: .both) == "ours\ntheirs")
}

@Test func conflictParserResolvesSelectedBlock() {
    let text = """
    before
    <<<<<<< HEAD
    ours-one
    =======
    theirs-one
    >>>>>>> branch
    middle
    <<<<<<< HEAD
    ours-two
    =======
    theirs-two
    >>>>>>> branch
    after
    """
    let resolved = ConflictMarkerParser.resolve(in: text, blockID: 1, choice: .theirs)
    #expect(resolved == """
    before
    <<<<<<< HEAD
    ours-one
    =======
    theirs-one
    >>>>>>> branch
    middle
    theirs-two
    after
    """)
}

@Test func conflictParserResolvesAllBlocks() {
    let text = """
    before
    <<<<<<< HEAD
    ours-one
    =======
    theirs-one
    >>>>>>> branch
    middle
    <<<<<<< HEAD
    ours-two
    =======
    theirs-two
    >>>>>>> branch
    after
    """
    let resolved = ConflictMarkerParser.resolveAll(in: text, choice: .both)
    #expect(resolved == """
    before
    ours-one
    theirs-one
    middle
    ours-two
    theirs-two
    after
    """)
}

@Test func conflictParserResolvesDifferentChoicesByBlock() {
    let text = """
    before
    <<<<<<< HEAD
    ours-one
    =======
    theirs-one
    >>>>>>> branch
    middle
    <<<<<<< HEAD
    ours-two
    =======
    theirs-two
    >>>>>>> branch
    after
    """
    let resolved = ConflictMarkerParser.resolve(in: text, choicesByBlockID: [0: .ours, 1: .theirs])
    #expect(resolved == """
    before
    ours-one
    middle
    theirs-two
    after
    """)
}

@Test func editorToolsReplaceAll() {
    let result = EditorTextTools.replacing("one two one", find: "one", replacement: "three")
    #expect(result == "three two three")
}

@Test func editorToolsLinePreviewIncludesNeighbors() {
    let preview = EditorTextTools.linePreview("a\nb\nc\nd\ne", line: 3, radius: 1)
    #expect(preview == "2: b\n3: c\n4: d")
}

@Test func editorToolsLineRangePreviewIncludesNeighbors() {
    let preview = EditorTextTools.lineRangePreview("a\nb\nc\nd\ne\nf", startLine: 3, endLine: 4, radius: 1)
    #expect(preview == "2: b\n3: c\n4: d\n5: e")
}

@Test func syntaxHighlighterClassifiesSwiftTokens() {
    let tokens = SyntaxHighlighter.tokens(for: #"let count = 42 // items"#, path: "Sources/App.swift")
    #expect(tokens.contains(SyntaxToken(text: "let", kind: .keyword)))
    #expect(tokens.contains(SyntaxToken(text: "42", kind: .number)))
}

@Test func syntaxHighlighterClassifiesStrings() {
    let tokens = SyntaxHighlighter.tokens(for: #"const title = "DIFF""#, path: "app.ts")
    #expect(tokens.contains(SyntaxToken(text: "const", kind: .keyword)))
    #expect(tokens.contains(SyntaxToken(text: #""DIFF""#, kind: .string)))
}

@Test func syntaxHighlighterClassifiesWholeLineComments() {
    let tokens = SyntaxHighlighter.tokens(for: "// hello", path: "App.swift")
    #expect(tokens == [SyntaxToken(text: "// hello", kind: .comment)])
}

@Test func syntaxHighlighterClassifiesInlineComments() {
    let tokens = SyntaxHighlighter.tokens(for: "let value = 1 // keep this", path: "App.swift")
    #expect(tokens.contains(SyntaxToken(text: "// keep this", kind: .comment)))
}

@Test func syntaxHighlighterCarriesBlockCommentsAcrossLines() {
    let lines = SyntaxHighlighter.highlightedLines(
        for: """
        let value = 1 /* start
        still comment
        end */ let next = 2
        """,
        path: "App.swift"
    )
    #expect(lines[0].contains(SyntaxToken(text: "/* start", kind: .comment)))
    #expect(lines[1] == [SyntaxToken(text: "still comment", kind: .comment)])
    #expect(lines[2].contains(SyntaxToken(text: "end */", kind: .comment)))
    #expect(lines[2].contains(SyntaxToken(text: "let", kind: .keyword)))
}

@Test func syntaxHighlighterHandlesNestedBlockComments() {
    let tokens = SyntaxHighlighter.tokens(for: "let x = 1 /* outer /* inner */ done */ let y = 2", path: "App.swift")
    #expect(tokens.contains(SyntaxToken(text: "/* outer /* inner */ done */", kind: .comment)))
    #expect(tokens.filter { $0 == SyntaxToken(text: "let", kind: .keyword) }.count == 2)
}

@Test func syntaxHighlighterUsesTreeSitterForSwiftFiles() {
    let lines = SyntaxHighlighter.highlightedLines(for: #"func greet() { print("hi") }"#, path: "App.swift")
    #expect(lines[0].contains(SyntaxToken(text: "func", kind: .keyword)))
    #expect(lines[0].contains(SyntaxToken(text: #""hi""#, kind: .string)))
}

@Test func syntaxHighlighterClassifiesDiffLines() {
    #expect(SyntaxHighlighter.tokens(for: "+added", path: "change.diff") == [SyntaxToken(text: "+added", kind: .diffAddition)])
    #expect(SyntaxHighlighter.tokens(for: "-removed", path: "change.diff") == [SyntaxToken(text: "-removed", kind: .diffDeletion)])
    #expect(SyntaxHighlighter.tokens(for: "@@ -1 +1 @@", path: "change.diff") == [SyntaxToken(text: "@@ -1 +1 @@", kind: .markup)])
}

@Test func syntaxHighlighterClassifiesMarkupLines() {
    let tokens = SyntaxHighlighter.tokens(for: #"<Text value="DIFF">Name</Text>"#, path: "View.xml")
    #expect(tokens.contains(SyntaxToken(text: #"<Text value="DIFF">"#, kind: .markup)))
    #expect(tokens.contains(SyntaxToken(text: "Name", kind: .plain)))
    #expect(tokens.contains(SyntaxToken(text: "</Text>", kind: .markup)))
}

@Test func syntaxHighlighterClassifiesMarkdownStructure() {
    #expect(SyntaxHighlighter.tokens(for: "## Release Notes", path: "README.md") == [SyntaxToken(text: "## Release Notes", kind: .markup)])
}

@Test func repoPathValidatorRejectsUnsafePaths() {
    #expect(RepoPathValidator.isInvalid(""))
    #expect(RepoPathValidator.isInvalid("/absolute.swift"))
    #expect(RepoPathValidator.isInvalid("folder/"))
    #expect(RepoPathValidator.isInvalid("folder//file.swift"))
    #expect(RepoPathValidator.isInvalid("folder/../file.swift"))
}

@Test func repoPathValidatorAcceptsRelativeFilePath() {
    #expect(!RepoPathValidator.isInvalid("Sources/DIFFMac/App.swift"))
}

@Test func fileSizePolicyMarksLargeContent() {
    #expect(FileSizePolicy.isLarge(String(repeating: "a", count: FileSizePolicy.largeFileThreshold + 1)))
    #expect(!FileSizePolicy.isLarge("small"))
}

@Test func githubPullsURLIncludesPaginationAndState() throws {
    let url = try GitHubRequestBuilder.pullsURL(
        repo: RepoRef(owner: "owner", name: "repo"),
        state: .closed,
        page: 2,
        perPage: 25
    )
    #expect(url.absoluteString == "https://api.github.com/repos/owner/repo/pulls?state=closed&page=2&per_page=25")
}

@Test func githubContentURLEncodesPathAndRef() throws {
    let url = try GitHubRequestBuilder.contentURL(
        repo: RepoRef(owner: "owner", name: "repo"),
        path: "Sources/My File.swift",
        ref: "feature/test"
    )
    #expect(url.absoluteString == "https://api.github.com/repos/owner/repo/contents/Sources/My%20File.swift?ref=feature/test")
}

@Test func githubOAuthAuthorizeURLIncludesStateAndRedirect() throws {
    let url = try GitHubOAuthURLBuilder.authorizeURL(clientID: "client id", state: "nonce")
    #expect(url.absoluteString.contains("https://github.com/login/oauth/authorize?"))
    #expect(url.absoluteString.contains("client_id=client%20id"))
    #expect(url.absoluteString.contains("redirect_uri=diffmac://github-oauth"))
    #expect(url.absoluteString.contains("scope=repo%20read:user%20user:email"))
    #expect(url.absoluteString.contains("state=nonce"))
}

@Test func githubOAuthExchangeEndpointRequiresHTTPS() throws {
    let url = try GitHubOAuthExchangeClient.validatedEndpointURL("https://auth.example.com/github")
    #expect(url.absoluteString == "https://auth.example.com/github")
    #expect(throws: GitHubOAuthExchangeError.self) {
        try GitHubOAuthExchangeClient.validatedEndpointURL("http://auth.example.com/github")
    }
    #expect(throws: GitHubOAuthExchangeError.self) {
        try GitHubOAuthExchangeClient.validatedEndpointURL("")
    }
}

@Test func githubUpdateContentPayloadIncludesBase64AndSha() throws {
    let data = try GitHubRequestBuilder.updateContentPayload(
        sha: "abc",
        branch: "main",
        content: "hello",
        message: "Update file"
    )
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(json["sha"] == "abc")
    #expect(json["branch"] == "main")
    #expect(json["message"] == "Update file")
    #expect(json["content"] == Data("hello".utf8).base64EncodedString())
}

@Test func apiErrorMessageExtractsMessageAndDetails() {
    let data = Data(#"{"message":"Validation Failed","errors":[{"message":"path is invalid"}]}"#.utf8)
    #expect(APIErrorMessage.extract(from: data) == "Validation Failed: path is invalid")
}

@Test func apiErrorMessageFallsBackToText() {
    let data = Data("plain failure".utf8)
    #expect(APIErrorMessage.extract(from: data) == "plain failure")
}

@Test func supabaseFetchPreferencesURLMatchesPostgrestShape() throws {
    let url = try SupabaseRequestBuilder.fetchPreferencesURL(
        projectURL: "https://example.supabase.co",
        userID: "user-123"
    )
    #expect(url.absoluteString.contains("https://example.supabase.co/rest/v1/user_preferences?"))
    #expect(url.absoluteString.contains("user_id=eq.user-123"))
    #expect(url.absoluteString.contains("limit=1"))
}

@Test func supabaseUpsertPreferencesURLIncludesConflictTarget() throws {
    let url = try SupabaseRequestBuilder.upsertPreferencesURL(projectURL: "https://example.supabase.co")
    #expect(url.absoluteString == "https://example.supabase.co/rest/v1/user_preferences?on_conflict=user_id")
}

@Test func appMetadataHasReleaseArchiveName() {
    #expect(AppMetadata.releaseArchiveName == "DIFFMac-0.1.0")
}

@Test func diagnosticsSnapshotRedactsSecrets() {
    let snapshot = DiagnosticsSnapshot(
        appVersion: "0.1.0 (1)",
        repo: "owner/repo",
        viewer: "octocat",
        mode: "Pulls",
        savedPullsCount: 1,
        recentReposCount: 2,
        aiDraftsCount: 3,
        hasGitHubToken: true,
        hasGeminiKey: true,
        hasSupabaseConfig: true,
        livePollingEnabled: false
    )
    #expect(snapshot.redactedText.contains("GitHub token configured: true"))
    #expect(!snapshot.redactedText.contains("ghp_"))
    #expect(!snapshot.redactedText.contains("secret"))
}

@Test func oauthCallbackParserReadsQueryValues() throws {
    let url = try #require(URL(string: "diffmac://github-oauth?code=abc123&state=nonce"))
    #expect(OAuthCallbackParser.githubCode(from: url) == "abc123")
    #expect(OAuthCallbackParser.githubState(from: url) == "nonce")
}

@Test func oauthCallbackParserReadsSupabaseFragmentValues() throws {
    let url = try #require(URL(string: "diffmac://supabase-auth#access_token=token-123&expires_in=3600"))
    #expect(OAuthCallbackParser.supabaseAccessToken(from: url) == "token-123")
}

@Test func oauthCallbackParserReadsSupabaseRefreshToken() throws {
    let url = try #require(URL(string: "diffmac://supabase-auth#access_token=token-123&refresh_token=refresh-123"))
    #expect(OAuthCallbackParser.supabaseRefreshToken(from: url) == "refresh-123")
}

@Test func oauthCallbackParserPrefersQueryOverFragment() throws {
    let url = try #require(URL(string: "diffmac://supabase-auth?access_token=query-token#access_token=fragment-token"))
    #expect(OAuthCallbackParser.supabaseAccessToken(from: url) == "query-token")
}

@Test func supabaseAuthorizeURLUsesProjectAuthEndpoint() throws {
    let url = try SupabaseAuthURLBuilder.authorizeURL(projectURL: "https://example.supabase.co")
    #expect(url.absoluteString.contains("https://example.supabase.co/auth/v1/authorize?"))
    #expect(url.absoluteString.contains("provider=github"))
    #expect(url.absoluteString.contains("redirect_to=diffmac://supabase-auth"))
}

@Test func supabaseAuthorizeURLPreservesBasePath() throws {
    let url = try SupabaseAuthURLBuilder.authorizeURL(projectURL: "https://example.com/base/")
    #expect(url.absoluteString.contains("https://example.com/base/auth/v1/authorize?"))
}

@Test func supabaseRefreshTokenURLMatchesAuthEndpoint() throws {
    let url = try SupabaseAuthRequestBuilder.refreshTokenURL(projectURL: "https://example.supabase.co")
    #expect(url.absoluteString == "https://example.supabase.co/auth/v1/token?grant_type=refresh_token")
}

private func jwtToken(payload: String) -> String {
    let encodedPayload = Data(payload.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    return "header.\(encodedPayload).signature"
}
