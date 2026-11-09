import Testing
@testable import HQKit

@Test func itemLines() {
    #expect(ItemLine.line("Task", "T-12", "Retry budget for blob uploads") == "Task T-12: Retry budget for blob uploads")
    #expect(ItemLine.line("Task", "T-12", "  ") == "Task T-12")
    #expect(ItemLine.line("Link", "https://example.com", "https://example.com") == "Link https://example.com")
    #expect(ItemLine.file("2026-11-09 - Jobs network.md") == "File \"2026-11-09 - Jobs network\"")
    #expect(ItemLine.file("plans/Push") == "File \"plans/Push\"")
}

@Test func itemLineGitHubKeys() {
    #expect(ItemLine.github("https://github.com/acme/registry/pull/418")! == ("PR", "acme/registry#418"))
    #expect(ItemLine.github("https://github.com/acme/registry/pull/418/files")! == ("PR", "acme/registry#418"))
    #expect(ItemLine.github("https://github.com/acme/registry/issues/77")! == ("Issue", "acme/registry#77"))
    #expect(ItemLine.github("https://github.com/acme/registry") == nil)
    #expect(ItemLine.github("https://example.com/acme/registry/pull/418") == nil)
}
