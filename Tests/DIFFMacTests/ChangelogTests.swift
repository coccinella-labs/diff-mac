import Foundation
import Testing

@Test func changelogPointsToGitHubReleases() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let changelog = root.appendingPathComponent("CHANGELOG.md")
    let text = try String(contentsOf: changelog, encoding: .utf8)
    #expect(text.contains("See GitHub Releases"))
    #expect(text.contains("https://github.com/coccinella-labs/diff-mac/releases"))
    #expect(text.contains("Release entries should be written and reviewed on the release page"))
}
