import Foundation
import Testing
@testable import DIFFMac

@Suite(.serialized)
struct NetworkClientTests {
@Test func githubClientFetchViewerUsesTokenAndDecodesUser() async throws {
    let session = makeMockSession()
    let client = GitHubClient(session: session)
    client.token = "ghp_test"

    MockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "https://api.github.com/user")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_test")
        return MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"login":"octocat","avatar_url":null,"html_url":"https://github.com/octocat"}"#.utf8)
        )
    }

    let viewer = try await client.fetchViewer()
    #expect(viewer.login == "octocat")
    #expect(viewer.htmlURL?.absoluteString == "https://github.com/octocat")
}

@Test func githubClientSurfacesStructuredErrorMessage() async {
    let session = makeMockSession()
    let client = GitHubClient(session: session)

    MockURLProtocol.handler = { _ in
        MockURLProtocol.Response(
            statusCode: 422,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"message":"Validation Failed","errors":[{"message":"branch missing"}]}"#.utf8)
        )
    }

    await #expect(throws: GitHubClientError.self) {
        _ = try await client.fetchViewer()
    }
}

@Test func githubOAuthExchangeClientPostsCodeAndReturnsToken() async throws {
    let session = makeMockSession()
    let client = GitHubOAuthExchangeClient(session: session)
    client.endpoint = "https://auth.example.com/github"

    MockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "https://auth.example.com/github")
        #expect(request.httpMethod == "POST")
        let bodyData = Data(requestBodyString(request).utf8)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        #expect(body["code"] == "oauth-code")
        #expect(body["state"] == "nonce")
        return MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"access_token":"gho_token","token_type":"bearer","scope":"repo"}"#.utf8)
        )
    }

    let token = try await client.exchange(code: "oauth-code", state: "nonce")
    #expect(token == "gho_token")
}

@Test func githubOAuthExchangeClientSurfacesHTTPError() async {
    let session = makeMockSession()
    let client = GitHubOAuthExchangeClient(session: session)
    client.endpoint = "https://auth.example.com/github"

    MockURLProtocol.handler = { _ in
        MockURLProtocol.Response(
            statusCode: 400,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"message":"Bad code"}"#.utf8)
        )
    }

    await #expect(throws: GitHubOAuthExchangeError.self) {
        _ = try await client.exchange(code: "bad-code")
    }
}

@Test func githubOAuthExchangeClientRejectsInsecureEndpoint() async {
    let session = makeMockSession()
    let client = GitHubOAuthExchangeClient(session: session)
    client.endpoint = "http://auth.example.com/github"

    await #expect(throws: GitHubOAuthExchangeError.self) {
        _ = try await client.exchange(code: "oauth-code")
    }
}

@Test func supabaseClientFetchesPreferenceRow() async throws {
    let session = makeMockSession()
    let client = SupabasePreferencesClient(session: session)
    client.projectURL = "https://example.supabase.co"
    client.anonKey = "anon"
    client.accessToken = jwt(sub: "user-123")

    MockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString.contains("/rest/v1/user_preferences") == true)
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        return MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"[{"user_id":"user-123","default_repo_owner":"owner","default_repo_name":"repo","recent_repos":[],"saved_pulls":[],"ai_drafts":[]}]"#.utf8)
        )
    }

    let preferences = try await client.fetchPreferences()
    #expect(preferences?.userID == "user-123")
    #expect(preferences?.defaultRepoOwner == "owner")
    #expect(preferences?.defaultRepoName == "repo")
}

@Test func supabaseClientSurfacesStructuredErrorMessage() async {
    let session = makeMockSession()
    let client = SupabasePreferencesClient(session: session)
    client.projectURL = "https://example.supabase.co"
    client.anonKey = "anon"
    client.accessToken = jwt(sub: "user-123")

    MockURLProtocol.handler = { _ in
        MockURLProtocol.Response(
            statusCode: 401,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"message":"JWT expired"}"#.utf8)
        )
    }

    await #expect(throws: SupabasePreferencesError.self) {
        _ = try await client.fetchPreferences()
    }
}

@Test func supabaseAuthClientRefreshesSessionAndRotatesRefreshToken() async throws {
    let session = makeMockSession()
    let client = SupabaseAuthClient(session: session)
    client.projectURL = "https://example.supabase.co"
    client.anonKey = "anon"

    MockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "https://example.supabase.co/auth/v1/token?grant_type=refresh_token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon")
        let bodyData = Data(requestBodyString(request).utf8)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        #expect(body["refresh_token"] == "refresh-old")
        return MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"access_token":"access-new","refresh_token":"refresh-new","expires_in":3600,"token_type":"bearer"}"#.utf8)
        )
    }

    let refreshed = try await client.refreshSession(refreshToken: "refresh-old")
    #expect(refreshed.accessToken == "access-new")
    #expect(refreshed.refreshToken == "refresh-new")
    #expect(refreshed.expiresIn == 3600)
}

@Test func supabaseAuthClientSurfacesRefreshError() async {
    let session = makeMockSession()
    let client = SupabaseAuthClient(session: session)
    client.projectURL = "https://example.supabase.co"
    client.anonKey = "anon"

    MockURLProtocol.handler = { _ in
        MockURLProtocol.Response(
            statusCode: 401,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"message":"Invalid refresh token"}"#.utf8)
        )
    }

    await #expect(throws: SupabasePreferencesError.self) {
        _ = try await client.refreshSession(refreshToken: "refresh-old")
    }
}

@Test func deviceOAuthRequestsDeviceCodeWithEncodedFormBody() async throws {
    let session = makeMockSession()
    let client = GitHubDeviceOAuthClient(session: session)

    MockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "https://github.com/login/device/code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = requestBodyString(request)
        #expect(body.contains("client_id=client%20id"))
        #expect(body.contains("scope=repo%20read:user%20user:email"))
        return MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"device_code":"device-123","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#.utf8)
        )
    }

    let response = try await client.requestDeviceCode(clientID: "client id")
    #expect(response.deviceCode == "device-123")
    #expect(response.userCode == "ABCD-EFGH")
    #expect(response.verificationURI.absoluteString == "https://github.com/login/device")
}

@Test func deviceOAuthPollReturnsToken() async throws {
    let session = makeMockSession()
    let client = GitHubDeviceOAuthClient(session: session)

    MockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(request.httpMethod == "POST")
        let body = requestBodyString(request)
        #expect(body.contains("client_id=client-id"))
        #expect(body.contains("device_code=device-code"))
        #expect(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
        return MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"access_token":"gho_token","token_type":"bearer","scope":"repo"}"#.utf8)
        )
    }

    let token = try await client.pollForToken(clientID: "client-id", deviceCode: "device-code")
    #expect(token == "gho_token")
}

@Test func deviceOAuthPollSurfacesPendingAndSlowDownStates() async {
    let session = makeMockSession()
    let client = GitHubDeviceOAuthClient(session: session)

    MockURLProtocol.handler = { _ in
        MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"error":"authorization_pending"}"#.utf8)
        )
    }
    await #expect(throws: DeviceOAuthError.self) {
        _ = try await client.pollForToken(clientID: "client-id", deviceCode: "device-code")
    }

    MockURLProtocol.handler = { _ in
        MockURLProtocol.Response(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data(#"{"error":"slow_down"}"#.utf8)
        )
    }
    await #expect(throws: DeviceOAuthError.self) {
        _ = try await client.pollForToken(clientID: "client-id", deviceCode: "device-code")
    }
}
}

private func jwt(sub: String) -> String {
    let payload = #"{"sub":"\#(sub)"}"#
    let encodedPayload = Data(payload.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    return "header.\(encodedPayload).signature"
}

private func requestBodyString(_ request: URLRequest) -> String {
    if let body = request.httpBody {
        return String(data: body, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else {
        return ""
    }
    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
}
