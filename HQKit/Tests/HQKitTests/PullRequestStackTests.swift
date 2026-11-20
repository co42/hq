import Foundation
import Testing
@testable import HQKit

private func pr(_ number: Int, repo: String = "acme/image-sync", head: String, base: String = "main") -> GitHubItem {
    GitHubItem(url: "https://github.com/\(repo)/pull/\(number)", kind: .pullRequest, number: number, repo: repo, title: "#\(number)",
               author: "alex", state: .open, updatedAt: .now, headBranch: head, baseBranch: base)
}

@Test func aStackSitsWhereItsNewestPRWasWithItsBaseOnTop() {
    // Newest first, as Yours lists them: #82 on #81 on #80.
    let items = [pr(520, repo: "acme/static-cdn", head: "prefetch"), pr(82, head: "report", base: "cache"),
                 pr(418, repo: "acme/registry", head: "retry"), pr(80, head: "bench"), pr(81, head: "cache", base: "bench")]
    let stacks = GitHubItem.stacks(items)
    #expect(stacks.map { $0.map(\.number) } == [[520], [80, 81, 82], [418]])
    #expect(items[1].stacked(in: stacks[1])?.number == 81)
    #expect(stacks[1][0].stacked(in: stacks[1]) == nil)
}

@Test func onlyTheSameRepositoryStacks() {
    let items = [pr(2, repo: "acme/a", head: "two", base: "one"), pr(1, repo: "acme/b", head: "one")]
    #expect(GitHubItem.stacks(items).map { $0.map(\.number) } == [[2], [1]])
}

@Test func twoPRsOnOneBaseFollowItInNumberOrder() {
    let items = [pr(12, head: "c", base: "a"), pr(10, head: "a"), pr(11, head: "b", base: "a"), pr(13, head: "d", base: "b")]
    #expect(GitHubItem.stacks(items).map { $0.map(\.number) } == [[10, 11, 13, 12]])
}

@Test func aLoopOfBasesLeavesEachPRAlone() {
    let items = [pr(1, head: "a", base: "b"), pr(2, head: "b", base: "a"), pr(3, head: "c")]
    #expect(GitHubItem.stacks(items).map { $0.map(\.number) } == [[1], [2], [3]])
}

@Test func thePollReadsEachPRsBaseBranch() throws {
    let snapshot = try GitHubQuery.parse([GitHubFixture.poll], linked: GitHubFixture.linked, now: GitHubFixture.reference)
    let item = try #require(snapshot.items.first { $0.number == 81 })
    #expect(item.baseBranch == "pull-bench")
}
