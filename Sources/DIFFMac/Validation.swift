import Foundation

enum RepoPathValidator {
    static func isInvalid(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ||
            trimmed.hasPrefix("/") ||
            trimmed.hasSuffix("/") ||
            trimmed.contains("//") ||
            trimmed.split(separator: "/").contains("..")
    }
}

enum FileSizePolicy {
    static let largeFileThreshold = 250_000

    static func isLarge(_ text: String) -> Bool {
        text.utf8.count > largeFileThreshold
    }
}
