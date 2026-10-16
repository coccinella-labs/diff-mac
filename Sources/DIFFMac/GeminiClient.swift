import Foundation

enum GeminiClientError: LocalizedError {
    case missingKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add a Gemini API key before drafting fixes."
        case .invalidResponse:
            "Gemini returned an invalid response."
        }
    }
}

final class GeminiClient: @unchecked Sendable {
    var apiKey = ""

    func draftFix(comment: ReviewComment, filePath: String, fileContent: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiClientError.missingKey
        }

        let prompt = """
        You are editing one repository file in response to a pull request review comment.
        Return only the full replacement file content. Keep the change minimal.

        File: \(filePath)

        Review comment:
        \(comment.body)

        Current file content:
        \(fileContent)
        """

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GeminiClientError.invalidResponse
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.compactMap({ $0["text"] as? String }).first
        else {
            throw GeminiClientError.invalidResponse
        }

        return text
            .replacingOccurrences(of: "```swift\n", with: "")
            .replacingOccurrences(of: "```kotlin\n", with: "")
            .replacingOccurrences(of: "```typescript\n", with: "")
            .replacingOccurrences(of: "```\n", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
