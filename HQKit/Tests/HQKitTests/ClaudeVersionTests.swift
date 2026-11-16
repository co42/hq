import Foundation
import Testing
@testable import HQKit

@Test func claudeVersionFromPathsAndOrder() {
    #expect(ClaudeVersion.inPath("/Users/x/.local/share/claude/versions/2.1.325") == "2.1.325")
    #expect(ClaudeVersion.inPath("/Users/x/.local/share/claude/versions/2.1.325/claude") == "2.1.325")
    #expect(ClaudeVersion.inPath("/opt/homebrew/bin/claude") == nil)
    #expect(ClaudeVersion.isOlder("2.1.99", than: "2.1.325"))
    #expect(!ClaudeVersion.isOlder("2.1.325", than: "2.1.325"))
    #expect(ClaudeVersion.isOlder("2.1", than: "2.1.1"))
    #expect(!ClaudeVersion.isOlder("3.0.0", than: "2.9.9"))
}

@Test func claudeVersionInstalledFollowsTheLink() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let target = dir.appending(path: "claude/versions/2.1.330")
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: target.path, contents: Data())
    let link = dir.appending(path: "claude-link").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)
    #expect(ClaudeVersion.installed(link: link) == "2.1.330")
    try? FileManager.default.removeItem(at: dir)
}
