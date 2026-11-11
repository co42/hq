import Foundation
import Testing
@testable import HQKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func urls(_ range: ClosedRange<Int>, repo: String = "a/b") -> [String] {
    range.map { "https://github.com/\(repo)/pull/\($0)" }
}

private func item(_ url: String, _ state: GitHubItem.State = .open, at: Date = now) -> GitHubItem {
    GitHubItem(url: url, kind: .pullRequest, number: Int(url.split(separator: "/").last!)!, repo: "a/b", title: url, author: "x",
               state: state, updatedAt: at)
}

@Test func githubLinksPastTheLimitAreReadInTurn() {
    // 100 done tasks' links, newest first, all known open.
    let rest = urls(1...100)
    let known = Dictionary(uniqueKeysWithValues: rest.map { ($0, GitHubItem.State.open) })
    let first = GitHubQuery.pick(fresh: [], rest: rest, known: known, asked: [:], now: now)
    #expect(first == Array(rest.prefix(GitHubQuery.linkedLimit)))
    let asked = Dictionary(uniqueKeysWithValues: first.map { ($0, now) })
    let second = GitHubQuery.pick(fresh: [], rest: rest, known: known, asked: asked, now: now + 120)
    #expect(second.count == GitHubQuery.linkedLimit)
    #expect(Set(first).union(second) == Set(rest))
    // The ones never asked come first, newest first.
    #expect(Array(second.prefix(40)) == Array(rest.suffix(40)))
}

@Test func githubLinksThatNeedAFreshStateComeFirst() {
    let fresh = urls(1...50, repo: "o/open")
    let rest = urls(1...30, repo: "o/done")
    var known = Dictionary(uniqueKeysWithValues: (fresh + rest).map { ($0, GitHubItem.State.open) })
    let unknown = "https://github.com/o/new/pull/1"
    let picked = GitHubQuery.pick(fresh: fresh, rest: rest + [unknown], known: known, asked: [:], now: now)
    #expect(picked.count == GitHubQuery.linkedLimit)
    // One never read, then fresh ones, fill all but one request; the last one takes turns among the others.
    #expect(Array(picked.prefix(40)) == [unknown] + Array(fresh.prefix(39)))
    #expect(Array(picked.suffix(20)) == Array(fresh.suffix(11)) + Array(rest.prefix(9)))
    // A merged one isn't asked again within a day, then is.
    known[rest[0]] = .merged
    let asked = [rest[0]: now]
    #expect(!GitHubQuery.pick(fresh: [], rest: rest, known: known, asked: asked, now: now + 3600).contains(rest[0]))
    #expect(GitHubQuery.pick(fresh: [], rest: rest, known: known, asked: asked, now: now + GitHubQuery.finalRecheck).contains(rest[0]))
    // Each link once, also when a task and a session share it.
    #expect(GitHubQuery.pick(fresh: [fresh[0]], rest: [fresh[0]], known: [:], asked: [:], now: now) == [fresh[0]])
}

@Test func githubItemsNotAskedKeepTheirLastAnswer() {
    let a = urls(1...3)
    let previous = GitHubSnapshot(viewer: "alex", items: [item(a[0], .merged), item(a[1], .open, at: now - 60), item(a[2])], fetchedAt: now - 120)
    var snapshot = GitHubSnapshot(viewer: "alex", items: [item(a[1], .closed, at: now)], fetchedAt: now)
    // a[0] wasn't asked; a[2] is no longer linked.
    snapshot.keep([a[0], a[1]], from: previous)
    #expect(snapshot.items.map(\.url) == [a[1], a[0]])
    #expect(snapshot.items.first { $0.url == a[1] }?.state == .closed)
    #expect(snapshot.items.first { $0.url == a[0] }?.state == .merged)
}

@Test func githubPollPaceAndBackOff() {
    #expect(GitHubPoll.delay(onScreen: true, failures: 0, limitedUntil: nil, now: now) == 120)
    #expect(GitHubPoll.delay(onScreen: false, failures: 0, limitedUntil: nil, now: now) == 300)
    #expect(GitHubPoll.delay(onScreen: true, failures: 2, limitedUntil: nil, now: now) == 480)
    #expect(GitHubPoll.delay(onScreen: false, failures: 9, limitedUntil: nil, now: now) == 1_800)
    #expect(GitHubPoll.delay(onScreen: true, failures: 0, limitedUntil: now + 1_000, now: now) == 1_001)
}

@Test func githubIsNotAskedAtEveryReturn() {
    #expect(GitHubPoll.asksOnReturn(lastAttempt: nil, failures: 0, limitedUntil: nil, now: now))
    #expect(!GitHubPoll.asksOnReturn(lastAttempt: now - 10, failures: 0, limitedUntil: nil, now: now))
    #expect(GitHubPoll.asksOnReturn(lastAttempt: now - 61, failures: 0, limitedUntil: nil, now: now))
    // Failing or limited: only the back-off's retry and Refresh ask.
    #expect(!GitHubPoll.asksOnReturn(lastAttempt: now - 600, failures: 1, limitedUntil: nil, now: now))
    #expect(!GitHubPoll.asksOnReturn(lastAttempt: now - 600, failures: 0, limitedUntil: now + 30, now: now))
}

@Test func githubRateLimitHeaders() {
    let reset = now + 1_800
    let spent = ["x-ratelimit-remaining": "12", "x-ratelimit-reset": "\(Int(reset.timeIntervalSince1970))"]
    #expect(GitHubPoll.limitedUntil(status: 200, headers: spent, now: now) == reset)
    #expect(GitHubPoll.limitedUntil(status: 200, headers: ["x-ratelimit-remaining": "4000", "x-ratelimit-reset": "1"], now: now) == nil)
    #expect(GitHubPoll.limitedUntil(status: 403, headers: ["retry-after": "60"], now: now) == now + 60)
    #expect(GitHubPoll.limitedUntil(status: 200, headers: ["retry-after": "60"], now: now) == nil)
}

@Test func githubReviewAskedAgainWaitsWithoutANewCommit() throws {
    let snapshot = try GitHubQuery.parse([GitHubFixture.poll], linked: GitHubFixture.linked, now: GitHubFixture.reference)
    // The user commented after the last commit: quiet, until their review is asked again.
    var shard = try #require(snapshot.items.first { $0.number == 233 })
    #expect(!shard.waitsForReview(markedReviewedAt: nil))
    let review = try #require(shard.myReviewAt)
    shard.reviewRequestedAt = review.addingTimeInterval(600)
    #expect(shard.waitsForReview(markedReviewedAt: nil))
    // Mark Reviewed after that request quiets it again.
    #expect(!shard.waitsForReview(markedReviewedAt: review.addingTimeInterval(900)))
}
