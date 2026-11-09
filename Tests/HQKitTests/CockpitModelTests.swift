import Foundation
import Testing
@testable import HQKit

// MARK: Migration

private let modified = NoteDate.parse("2026-10-30T09:15")!

@Test("Each old status gets its list", arguments: [
    ("backlog", ["status": "todo", "list": "backlog"]),
    ("todo", ["list": "backlog"]),
    ("doing", ["list": "overview"]),
    ("review", ["list": "overview"]),
    ("done", ["list": "backlog", "done": "2026-10-30T09:15"]),
])
func migrationPlansEachStatus(_ status: String, _ expected: [String: String]) {
    #expect(TaskMigration.plan(FrontMatter("---\ntitle: T\nstatus: \(status)\n---\nBody\n"), modified: modified) == expected)
}

@Test func migrationKeepsTheRestAndRunsOnce() throws {
    let text = "---\ntitle: Dedup layers\nstatus: backlog\naliases: [dedup]\ntags:\n  - registry\n---\nBody with `code`.\n\n**2026-11-03**: a note.\n"
    let once = try #require(TaskMigration.apply(text, modified: modified))
    let note = FrontMatter(once)
    #expect(note.string("status") == "todo" && note.string("list") == "backlog" && note.string("type") == nil)
    #expect(note.list("aliases") == ["dedup"] && note.list("tags") == ["registry"])
    #expect(note.body == FrontMatter(text).body)
    #expect(once.hasPrefix("---\ntitle: Dedup layers\nstatus: todo\naliases: [dedup]\ntags:\n  - registry\nlist: backlog\n---\n"))
    #expect(TaskMigration.apply(once, modified: .now) == nil)
    // A subtask gets no list; a type the user set stays.
    #expect(TaskMigration.plan(FrontMatter("---\nstatus: todo\nparent: T-3\ntype: bug\n---\n"), modified: modified).isEmpty)
}

// MARK: Titles

@Test("#word in a title becomes a tag", arguments: [
    ("Fix the push #perf", "Fix the push", ["perf"]),
    ("#ux Show progress #chunks #ux", "Show progress", ["ux", "chunks"]),
    ("Merge PR #418 today", "Merge PR #418 today", []),
    ("C# notes", "C# notes", []),
    ("Plain", "Plain", []),
] as [(String, String, [String])])
func titleTags(_ text: String, _ title: String, _ tags: [String]) {
    let split = TitleTags.split(text)
    #expect(split.title == title && split.tags == tags)
}

// MARK: Markdown checkboxes

@Test func checkboxesToggleInTheSource() throws {
    let source = "Intro\r\n\n- [ ] one\n  - [x] nested\n\n```\n- [ ] in code\n```\n> - [ ] quoted\n1. [X] numbered\n- [ ]\n- [] not a box\n"
    #expect(Markdown.taskLines(source) == [2, 3, 8, 9])
    let ticked = try #require(Markdown.toggleTask(source, at: 0))
    #expect(ticked == source.replacingOccurrences(of: "- [ ] one", with: "- [x] one"))
    let cleared = try #require(Markdown.toggleTask(source, at: 3))
    #expect(cleared == source.replacingOccurrences(of: "1. [X] numbered", with: "1. [ ] numbered"))
    #expect(Markdown.toggleTask(source, at: 4) == nil)
    #expect(Markdown.toggleTask(try #require(Markdown.toggleTask(source, at: 2)), at: 2) == source)
}

@Test func checkboxesMatchTheViewer() {
    let source = "- [ ] a\n  - [x] b\n- c\n\n> - [ ] d\n\n1. [x] e\n"
    var checks: [Bool] = []
    func walk(_ blocks: [MarkdownBlock]) {
        for block in blocks {
            switch block {
            case .list(_, _, let items):
                for item in items {
                    if let checked = item.checked { checks.append(checked) }
                    walk(item.blocks)
                }
            case .quote(let inner): walk(inner)
            default: break
            }
        }
    }
    walk(Markdown.blocks(source))
    #expect(checks == [false, true, false, true])
    #expect(Markdown.taskLines(source).count == checks.count)
}

// MARK: Faces

@Test func facesAreStable() {
    let id = "ef032aac-66d1-4b82-b6e1-03b8ee32dc93"
    #expect(FaceSpec(id: id) == FaceSpec(id: id))
    #expect(FaceSpec(id: id, salt: 1) != FaceSpec(id: id))
    #expect(FaceSpec(id: id) != FaceSpec(id: "250a8563-5c74-4592-a463-b41398dc5b55"))
}

@Test func facesSpreadTheirParts() {
    let faces = (0..<10_000).map { FaceSpec(id: "session-\($0)") }
    /// No part shows up more than twice as often as its weight's share.
    func check<T: Hashable>(_ name: String, _ values: [T], weights: [T: Double]) {
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        let total = weights.values.reduce(0, +)
        for (value, weight) in weights {
            let share = weight / total
            let observed = Double(counts[value] ?? 0) / Double(values.count)
            #expect(observed <= share * 2, "\(name) \(value): \(observed) over twice \(share)")
        }
    }
    let even = { (count: Int) -> [Int: Double] in Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, 1) }) }
    check("background", faces.map(\.background), weights: even(FacePalette.backgrounds.count))
    check("skin", faces.map(\.skin), weights: even(FacePalette.skins.count))
    let hair: [FaceSpec.Hair: Double] = [.bald: 1, .short: 3, .swoop: 3, .curly: 3, .bun: 2, .long: 3, .bob: 3, .afro: 2, .mohawk: 1, .spikes: 1]
    check("hair", faces.map(\.hair), weights: hair)
    let headwear: [FaceSpec.Headwear: Double] = [.none: 12, .beanie: 2, .cap: 2, .topHat: 1, .beret: 1, .party: 1, .headband: 1, .crown: 1, .bucket: 1, .hood: 1]
    check("headwear", faces.map(\.headwear), weights: headwear)
    let eyewear: [FaceSpec.Eyewear: Double] = [.none: 10, .round: 2, .square: 2, .shades: 1, .visor: 1, .monocle: 1]
    check("eyewear", faces.map(\.eyewear), weights: eyewear)
    // Every part shows up.
    #expect(Set(faces.map(\.hair)).count == FaceSpec.Hair.allCases.count)
    #expect(Set(faces.map(\.headwear)).count == FaceSpec.Headwear.allCases.count)
    #expect(Set(faces.map(\.mouth)).count == FaceSpec.Mouth.allCases.count)
}

@Test func facesMeetTheirRules() {
    for index in 0..<10_000 {
        let face = FaceSpec(id: "session-\(index)")
        let skin = FacePalette.skins[face.skin]
        #expect(skin.contrast(FacePalette.backgrounds[face.background]) >= FaceSpec.skinContrast)
        #expect(skin.contrast(FacePalette.ink(on: face.skin)) >= FaceSpec.featureContrast)
        #expect(FaceSpec.fits(face.hair, under: face.headwear))
        if face.headwear != .none && face.headwear != .headband { #expect(!face.extras.contains(.headphones)) }
    }
}

// MARK: GitHub

private func fixture() throws -> GitHubSnapshot {
    try GitHubQuery.parse(GitHubFixture.poll, linked: GitHubFixture.linked, now: GitHubFixture.reference)
}

@Test func githubReviewRequests() throws {
    let snapshot = try fixture()
    #expect(snapshot.viewer == "alex")
    let cdn = try #require(snapshot.items.first { $0.number == 512 })
    #expect(cdn.reviewRequested && !cdn.mine && cdn.review == .required && cdn.checks == .passed && cdn.reference == "static-cdn #512")
    #expect(cdn.waitsForReview(markedReviewedAt: nil))
    #expect(!cdn.waitsForReview(markedReviewedAt: cdn.lastCommitAt))
    let tokio = try #require(snapshot.items.first { $0.number == 430 })
    #expect(tokio.checks == .running && tokio.checkRuns == [.init(name: "ci / test", checks: .running)])
    // The user commented after the last commit: quiet until the next commit.
    let shard = try #require(snapshot.items.first { $0.number == 233 })
    #expect(shard.myReviewAt != nil && !shard.waitsForReview(markedReviewedAt: nil))
    var pushed = shard
    pushed.lastCommitAt = shard.myReviewAt?.addingTimeInterval(60)
    #expect(pushed.waitsForReview(markedReviewedAt: nil))
}

@Test func githubReviewAskedAndApproved() throws {
    let items = try fixture().items
    func at(_ time: String) -> Date? { ISO8601DateFormatter().date(from: "2026-11-04T\(time):00Z") }
    // The user's own request, not another user's made later.
    let cdn = try #require(items.first { $0.number == 512 })
    #expect(cdn.reviewRequestedAt == at("13:58") && cdn.myReview == .none && !cdn.approved)
    // A team's request when none is the user's.
    let tokio = try #require(items.first { $0.number == 430 })
    #expect(tokio.reviewRequestedAt == at("15:32"))
    // Approved by the user: approved, though GitHub still requires a review.
    let cache = try #require(items.first { $0.number == 433 })
    #expect(cache.reviewedByMe && cache.review == .required && cache.myReview == .approved && cache.approved)
    #expect(cache.reviewAskedAt == at("09:00"))
    let shard = try #require(items.first { $0.number == 233 })
    #expect(shard.myReview == .none && !shard.approved)
}

@Test func githubOwnPullRequests() throws {
    let items = try fixture().items
    let approved = try #require(items.first { $0.number == 418 })
    #expect(approved.mine && approved.review == .approved && approved.reviewers == ["noor"] && approved.headBranch == "retry-budget")
    #expect(approved.checkRuns.map(\.name) == ["ci / test", "ci / clippy", "canary / registry-staging"])
    let changes = try #require(items.first { $0.number == 80 })
    #expect(changes.review == .changesRequested && changes.reviewers == ["theo"])
    let draft = try #require(items.first { $0.number == 44 })
    #expect(draft.state == .draft && draft.checks == .running)
    let failing = try #require(items.first { $0.number == 520 })
    #expect(failing.checks == .failed && failing.review == .required)
    let merged = try #require(items.first { $0.number == 405 })
    #expect(merged.state == .merged)
    let issue = try #require(items.first { $0.number == 77 })
    #expect(issue.kind == .issue && issue.state == .open && issue.author == "theo" && issue.body?.contains("99%") == true)
}

@Test func githubErrorsAndQuery() {
    #expect(throws: GitHubQuery.ParseError.github("Bad credentials")) {
        try GitHubQuery.parse(Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8), linked: [])
    }
    let query = GitHubQuery.query(linked: ["https://github.com/a/b/pull/1"])
    #expect(query.contains(#"r0: resource(url: "https://github.com/a/b/pull/1")"#) && query.contains("user-review-requested:@me"))
    // GitHub refuses a fragment the query doesn't use.
    #expect(!GitHubQuery.query(linked: []).contains("fragment issue") && query.contains("fragment issue"))
}

@Test func githubLinkRules() throws {
    let output = "Creating pull request for retry-budget into main\n\nhttps://github.com/acme/registry/pull/418\nsee https://github.com/acme/registry/pull/418 and https://github.com/acme/image-sync/issues/77."
    #expect(GitHubLinks.urls(in: output) == ["https://github.com/acme/registry/pull/418", "https://github.com/acme/image-sync/issues/77"])
    let approved = try #require(try fixture().items.first { $0.number == 418 })
    #expect(GitHubLinks.matches(approved, branch: "retry-budget", origin: "acme/registry"))
    #expect(GitHubLinks.matches(approved, branch: "retry-budget", origin: "Acme/registry"))
    #expect(!GitHubLinks.matches(approved, branch: "main", origin: "acme/registry"))
    #expect(!GitHubLinks.matches(approved, branch: "retry-budget", origin: "acme/image-sync"))
    #expect(GitInfo.remote(in: "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = git@github.com:acme/registry.git\n") == "acme/registry")
    #expect(GitInfo.remote(in: "[remote \"origin\"]\n\turl = https://github.com/acme/storage-core\n") == "acme/storage-core")
    let event = HookEvent(json: Data(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":"https:\/\/github.com\/acme\/registry\/pull\/418\n"}}"#.utf8))
    #expect(event?.pullRequests == ["https://github.com/acme/registry/pull/418"])
    let list = HookEvent(json: Data(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"gh pr list"},"tool_response":"https://github.com/a/b/pull/1"}"#.utf8))
    #expect(list?.pullRequests == [])
}
