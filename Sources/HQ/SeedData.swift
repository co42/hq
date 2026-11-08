import Foundation
import HQKit

/// Sample data for snapshots and tests (`APP_SEED=1` with APP_STORE in /tmp): the mockup's day.
/// Sessions in every state, tasks with subtasks, types, tags and projects, descriptions with
/// checkboxes and code, the Backlog, PRs in every state, files, artifacts, closed
/// sessions. `APP_SEED=large` adds 500 tasks and 30 sessions.
enum SeedData {
    static var requested: Bool { ["1", "large"].contains(ProcessInfo.processInfo.environment["APP_SEED"] ?? "") }
    static var large: Bool { ProcessInfo.processInfo.environment["APP_SEED"] == "large" }

    static func insertIfRequested(into model: AppModel) {
        guard requested else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        fill(model, now: .now)
        if large { fillLarge(model, now: .now) }
    }

    static func fill(_ model: AppModel, now: Date) {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let undo = model.undoManager
        undo?.disableUndoRegistration()
        defer { undo?.enableUndoRegistration() }

        let s1 = "ef032aac-66d1-4b82-b6e1-03b8ee32dc93", s2 = "250a8563-5c74-4592-a463-b41398dc5b55"
        let s3 = "83b6ab7a-8155-40ac-b149-16e2b8313b81", s4 = "9aa6f823-1036-48e7-b290-d9851a3e5a8e"
        let s5 = "b42584f5-c7b6-4872-9e93-ab43a6805836", s6 = "0907d834-b1ae-4456-b6de-bbd0e091fdad"
        let s7 = "66c2019e-a381-4058-aa47-ea27abf4bd0c", s8 = "e6d1730b-dfe1-472f-b130-c8183a051ef5"
        let e1 = "ac27ce47-a53b-4dc6-ab34-110588f59740", e2 = "66c2019e-a381-4058-aa47-ea27abf4bd0d"
        let plan = "/tmp/HQ-seed-plan.md"
        try? "## Chunk cache eviction\nThe chunk cache grows **without bound** during long pushes. Evict least recently used chunks, keep the chunks of files in flight.\n\n1. A byte budget for `ChunkCache`, 2 GB by default\n2. LRU eviction that skips pinned chunks\n3. Metrics for evictions and cache size\n4. A test: a 10 GB push under a 512 MB budget\n"
            .write(toFile: plan, atomically: true, encoding: .utf8)
        func session(_ id: String, _ name: String, _ state: SessionState, minutes: Double, repo: String, branch: String,
                     order: Double, unread: Bool = false, closed: Date? = nil, started: Double = 120,
                     last: String? = nil, configure: (inout SessionItem) -> Void = { _ in }) -> SessionItem {
            var item = SessionItem(id: id, customName: name, status: SessionStatus(state: state, unread: unread, since: ago(minutes)),
                                   cwd: "~/code/\(repo)", repo: repo, branch: branch, origin: "acme/\(repo)",
                                   started: ago(started), tty: closed == nil ? "/dev/ttys0\(Int(order) + 10)" : nil, lastMessage: last,
                                   order: order, closedAt: closed)
            configure(&item)
            return item
        }
        var sessions = [
            session(s2, "Secrets identity rotation", .waiting(.question), minutes: 12, repo: "infra-secrets", branch: "machine-identities", order: 1,
                    last: "The plan is written. Before I write the Terraform, one choice is yours.") {
                $0.question = "Per-identity credentials or one shared machine identity for the CDN workers?"
                $0.options = ["One identity per worker pool (Recommended)", "One shared identity"]
            },
            session(s3, "chunk cache eviction", .waiting(.plan), minutes: 1, repo: "storage-core", branch: "chunk-cache-eviction", order: 2,
                    last: "Plan ready. Approve it in the session and I start with the cache budget.") { $0.planPath = plan },
            session(s1, "registry: retry budget", .idle, minutes: 15, repo: "registry", branch: "retry-budget", order: 3,
                    last: "PR #418 is open and the canary is green. I moved T-13 to Review."),
            session(s8, "image-sync push progress", .working, minutes: 4, repo: "image-sync", branch: "push-progress", order: 4,
                    last: "Wiring chunk counts into the push progress bar."),
            session(s5, "Redesign HQ", .done, minutes: 3, repo: "hq", branch: "main", order: 5, unread: true,
                    last: "Mockup published, waiting for your review."),
            session(s6, "Reading highlights export", .failed, minutes: 18, repo: "home-scripts", branch: "highlights-export", order: 6,
                    last: "Fetching the last 30 days of highlights from the reading app.") { $0.error = "API error 529, overloaded" },
            session(s4, "CDN chunk bridge prefetch", .ended, minutes: 30, repo: "static-cdn", branch: "chunk-bridge-prefetch", order: 7, closed: ago(30),
                    last: "Running the sweep again with 4 MB and 8 MB windows."),
            session(s7, "Weekly infra notes", .ended, minutes: 90, repo: "infra", branch: "main", order: 8, closed: ago(90),
                    last: "Notes for the weekly infra sync are in the vault."),
            session(e1, "CDN pull cron analysis", .ended, minutes: 260, repo: "static-cdn", branch: "main", order: 9, closed: ago(260),
                    last: "Analysis done and published."),
            session(e2, "hq plan review", .ended, minutes: 1_400, repo: "hq", branch: "main", order: 10, closed: ago(1_400),
                    last: "Plan reviewed; notes in PLAN.md."),
        ]
        // A long name and a long branch, to check truncation.
        sessions.append(session("5eed0000-0000-4000-8000-00000000000b", "Investigate why blob uploads retry on 503 from the S3 multipart complete endpoint under load",
                                .waiting(.permission), minutes: 6, repo: "registry", branch: "s3-multipart-complete-retries-under-load", order: 7.5) {
            $0.tool = "Bash"
            $0.toolInput = "kubectl rollout restart deploy/registry-api -n registry-staging"
        })
        for index in sessions.indices { sessions[index].faceSalt = 0 }
        model.sessions = sessions
        for index in model.sessions.indices { model.sessions[index].faceSalt = model.faceSalt(for: model.sessions[index].id) }

        struct Row {
            var id: Int, title: String, status: TaskStatus = .todo, type: TaskType = .feature, project: String? = nil
            var tags: [String] = [], parent: Int? = nil, list: TaskList = .overview, order: Double, body = ""
            var sessions: [String] = [], links: [String] = [], review: String? = nil, reviewBy: String? = nil
        }
        let gh = "https://github.com/acme/"
        let rows: [Row] = [
            Row(id: 13, title: "Retry budget for blob uploads", status: .doing, project: "Registry", tags: ["perf"], order: 1,
                body: "Blob uploads retry with **no budget**: a slow S3 multipart complete turns into minutes of retries.\n\n## Done when\n- [x] At most 3 attempts per part, full jitter\n- [x] A `503` on complete retries once, then reaches the client\n- [ ] The canary stays green for 30 minutes\n\n```toml\n[upload]\nretry_budget = 3\n```\n\n> Keep the budget per upload: a push of 40 layers must not retry 40 × 3 times.",
                sessions: [s1], links: [gh + "registry/pull/418", SlackService.fixtureLink]),
            Row(id: 47, title: "Budget per upload in upload::retry", status: .done, parent: 13, order: 1),
            Row(id: 48, title: "A 503 on multipart complete retries once", status: .done, parent: 13, order: 2),
            Row(id: 49, title: "Canary on registry-staging, 30 minutes green", status: .doing, parent: 13, order: 3),
            Row(id: 16, title: "Move CDN workers to machine identities", status: .doing, type: .chore, project: "CDN", tags: ["security"], order: 2,
                body: "CDN workers read a static `SECRETS_TOKEN` nobody rotates.\n\n- [x] Plan: *machine identities for CDN workers*\n- [ ] One identity per pool, in Terraform\n- [ ] Drop the static secret",
                sessions: [s2], links: [gh + "infra-secrets/pull/44"]),
            Row(id: 50, title: "One identity per worker pool, in Terraform", status: .doing, parent: 16, order: 1, sessions: [s2]),
            Row(id: 51, title: "Universal auth in the worker init container", parent: 16, order: 2),
            Row(id: 7, title: "Rotate the per-identity credentials", type: .chore, tags: ["security"], parent: 16, order: 3),
            Row(id: 22, title: "Ship chunk-aware pull/push progress in image-sync", status: .doing, project: "Registry", tags: ["ux", "chunks"], order: 3,
                body: "image-sync shows **no progress** during chunked pulls and pushes.\n\nShow bytes and chunks as they land, the same way in both directions.",
                links: [gh + "image-sync/pull/80"]),
            Row(id: 52, title: "Progress for pulls", status: .done, parent: 22, order: 1),
            Row(id: 53, title: "Progress for pushes", status: .doing, parent: 22, order: 2, sessions: [s3, s8], links: [gh + "image-sync/issues/77"]),
            Row(id: 25, title: "Decide on capping the chunk download buffer", type: .research, parent: 22, order: 3, sessions: [s3]),
            Row(id: 14, title: "Prefetch window for the CDN chunk bridge", status: .doing, project: "CDN", tags: ["perf"], order: 4,
                body: "The bridge fetches one range at a time. Prefetch the next window while serving the current one.\n\n```\nprefetch_window = 8 MiB\n```",
                sessions: [s4], links: [gh + "static-cdn/pull/520", gh + "static-cdn/pull/512"]),
            Row(id: 44, title: "HQ overview: sessions on top, tasks as an outline", status: .doing, project: "HQ", tags: ["ui"], order: 5,
                body: "One page for the day: **sessions on top**, the task outline below, a click opens anything big.\n\n- [x] First mockup\n- [x] Faces for sessions, an outline for tasks\n- [ ] Types, tags and projects\n- [ ] Plan, then build",
                sessions: [s5]),
            Row(id: 54, title: "Mockup with fake data", status: .done, parent: 44, order: 1),
            Row(id: 55, title: "Plan", parent: 44, order: 2),
            Row(id: 56, title: "Build it", parent: 44, order: 3),
            Row(id: 45, title: "Keep hq file show's header out of notes", type: .bug, project: "HQ", order: 6,
                body: "`hq file show` prints a header that ends up pasted into notes.", sessions: [s5]),
            Row(id: 5, title: "Auto-export reading highlights to the vault", status: .doing, project: "Home", order: 7,
                body: "Every book with highlights lands in the vault as a note, **one quote per line**.", sessions: [s6]),
            Row(id: 8, title: "Dedup layers on push before the manifest commit", type: .story, project: "Registry", tags: ["perf", "chunks"], order: 8),
            Row(id: 23, title: "Analyse the hourly CDN pull cron by time of day", status: .done, type: .research, project: "CDN", order: 9,
                body: "Does the hourly pull cron line up with traffic peaks? **Yes**: it peaks two hours before US traffic.", sessions: [e1]),
            Row(id: 39, title: "Colors for tags and folders", project: "HQ", tags: ["ui"], list: .backlog, order: 1),
            Row(id: 36, title: "Capture typed artifacts: dashboards, docs, decks", type: .bug, project: "HQ", list: .backlog, order: 2),
            Row(id: 35, title: "Add an existing artifact to HQ by its URL", type: .story, project: "HQ", list: .backlog, order: 3),
            Row(id: 33, title: "Retry stalled chunk ranges sooner in image-sync", type: .bug, project: "Registry", tags: ["chunks"], list: .backlog, order: 4),
            Row(id: 29, title: "Unread clears when the user focuses a session's terminal", type: .bug, project: "HQ", list: .backlog, order: 5),
            Row(id: 27, title: "Commit bench Terraform and clean up bench hosts", type: .chore, project: "Registry", tags: ["infra"], list: .backlog, order: 6),
            Row(id: 26, title: "Flag the cdn-us autoscaler to its owners", type: .chore, project: "CDN", list: .backlog, order: 7),
            Row(id: 24, title: "Write up the CDN cache key normalisation", type: .docs, project: "CDN", list: .backlog, order: 8),
            Row(id: 3, title: "Registry GC dry run on staging", status: .done, project: "Registry", list: .backlog, order: 9,
                links: [gh + "registry/pull/405"]),
        ]
        model.tasks = rows.map { row in
            TaskItem(id: row.id, title: row.title, status: row.status, type: row.type, project: row.project, tags: row.tags,
                     parent: row.parent, list: row.list, order: row.order, review: row.review, reviewBy: row.reviewBy,
                     reviewAt: row.review == nil ? nil : ago(row.id == 13 ? 25 : 3), done: row.status == .done ? ago(90) : nil,
                     links: row.links.compactMap(URL.init(string:)), related: row.id == 14 ? [33] : [], sessions: row.sessions,
                     created: ago(Double(3_000 - row.id * 20)), modified: ago(Double(row.id)), body: row.body)
        }

        model.files = [
            FileItem(id: "2026-11-04 - Retry budget plan.md", title: "Retry budget plan", date: ago(300), modified: ago(300), sessions: [s1], tasks: [13],
                     project: "Registry", tags: ["perf"], pinned: true),
            FileItem(id: "2026-11-04 - Machine identities for CDN workers.md", title: "Machine identities for CDN workers", date: ago(20), modified: ago(20), sessions: [s2], tasks: [16]),
            FileItem(id: "2026-11-04 - image-sync pull push perf.md", title: "image-sync pull/push perf", date: ago(120), modified: ago(120), sessions: [s3], tasks: [22]),
            FileItem(id: "2026-11-04 - Weekly infra sync notes.md", title: "Weekly infra sync notes", date: ago(60), modified: ago(60), sessions: [s7],
                     tags: ["meeting"]),
        ]
        model.fileDrafts = [
            model.files[0].id: "# Retry budget plan\nOne budget per upload, shared by its parts, so a slow part cannot starve the others.\n\n- 3 attempts per part, **full jitter**, base 100 ms, cap 2 s\n- A `503` on complete retries once\n\n```mermaid\ngraph LR\n  push[Upload part] -->|503| retry{Budget left?}\n  retry -->|yes| push\n  retry -->|no| fail[Return the error]\n```\n\n```\nlet budget = RetryBudget::new(3).with_jitter(Jitter::Full);\n```\n",
            model.files[1].id: "# Machine identities for CDN workers\nWorkers read `SECRETS_TOKEN` from a secret nobody rotates. Machine identities give each pool **short-lived** credentials.\n\n## Steps\n1. One identity per pool, in Terraform\n2. Universal auth in the worker init container\n3. Drop the static secret once every pool runs on an identity\n",
            model.files[2].id: "# image-sync pull/push perf\nPulls wait on single ranges; pushes spend their time hashing.\n\n- Pull: 8 ranges in flight\n- Push: hash while uploading\n",
            model.files[3].id: "# Weekly infra sync\n- Registry: retry budget in review\n- CDN: machine identities next\n- Chunks: cache eviction plan\n",
        ]
        model.artifacts = [
            ArtifactItem(id: URL(string: "https://claude.ai/artifact/5eed-canary")!, title: "Retry budget canary", session: s1, published: ago(70), tasks: [13]),
            ArtifactItem(id: URL(string: "https://claude.ai/artifact/5eed-sweep")!, title: "Prefetch window sweep", session: s4, published: ago(1_500), tasks: [14]),
            ArtifactItem(id: URL(string: "https://claude.ai/artifact/5eed-mockup")!, title: "HQ Unified Overview", session: s5, published: ago(3), tasks: [44],
                         project: "HQ", tags: ["ui"], pinned: true),
            ArtifactItem(id: URL(string: "https://claude.ai/artifact/5eed-cron")!, title: "CDN pull cron by hour of day", session: e1, published: ago(280), tasks: [23]),
        ]
        model.github = GitHubService.fixture(now: now)
        model.slackMessages = SlackService.fixtures
        model.setup = SetupStatus(pluginInstalled: true, ghosttyAllowed: true, vaultPath: SetupStatus.defaultVault,
                                  ghPath: "/opt/homebrew/bin/gh", githubAccount: "alex")
        model.seen = [:]
        // The center: two pings, updates from sessions and GitHub, reminders in Later, what was read earlier.
        let pr418 = gh + "registry/pull/418", pr520 = gh + "static-cdn/pull/520", pr80 = gh + "image-sync/pull/80"
        model.noticeStore = NoticeStore(notices: [
            Notice(kind: .session, level: .important, source: s8, text: "Push progress works on a 10 GB image. Watch it run before I merge?",
                   links: ["task:53", "github:\(pr80)"], at: ago(8)),
            Notice(kind: .reminder, level: .important, text: "Call noor about the GPU quota", links: ["task:13"], at: ago(5)),
            Notice(kind: .session, level: .update, source: s1, text: "Retry budget ready to check: PR #418 is open, the canary is green. The plan has the numbers per region: eu-west still retries twice on large layers, left for a follow-up since the fix touches the S3 client. Merge when you're happy with the canary.",
                   count: 2, links: ["task:13", "file:2026-11-04 - Retry budget plan.md", "artifact:https://claude.ai/artifact/5eed-canary", "github:\(pr418)"],
                   at: ago(15)),
            Notice(kind: .session, level: .update, source: s5, text: "The mockup is ready to look at",
                   links: ["task:44", "artifact:https://claude.ai/artifact/5eed-mockup"], at: ago(3)),
            Notice(kind: .github, level: .update, source: pr418, text: "noor approved your PR: “Nice, the budget per upload reads well”",
                   count: 3, links: ["github:\(pr418)", "task:13"], at: ago(20)),
            Notice(kind: .github, level: .update, source: pr520, text: "theo asked for changes: “Split the window change from the metrics”",
                   links: ["github:\(pr520)", "task:14"], at: ago(55)),
            Notice(kind: .reminder, level: .update, text: "Write the Q1 infra plan", at: ago(600),
                   dueAt: ReminderTime.date(.nextWeek, now: now)),
            Notice(kind: .reminder, level: .update, text: "Review the tokio bump before standup", links: ["github:\(gh)registry/pull/430"], at: ago(40),
                   dueAt: ReminderTime.date(.tomorrow, now: now)),
            Notice(kind: .github, level: .update, source: gh + "registry/pull/430", text: "Look again once theo pushes the fixes",
                   links: ["github:\(gh)registry/pull/430"], at: ago(120), dueAt: ReminderTime.date(.tomorrow, now: now)),
            Notice(kind: .session, level: .update, source: e1, text: "The cron analysis is published", links: ["task:23", "artifact:https://claude.ai/artifact/5eed-cron"],
                   at: ago(270), readAt: ago(200)),
            Notice(kind: .session, level: .update, source: s7, text: "Notes for the weekly infra sync are in the vault", at: ago(95), readAt: ago(80)),
        ], bellSeenAt: ago(30))
        model.collapsed = [13]
        model.shownDescriptions = [44]
    }

    /// 500 tasks in nests of up to three levels, and 30 sessions, for the performance check.
    static func fillLarge(_ model: AppModel, now: Date) {
        let undo = model.undoManager
        undo?.disableUndoRegistration()
        defer { undo?.enableUndoRegistration() }
        let words = ["registry", "cdn", "chunks", "bridge", "cache", "push", "pull", "retry", "budget", "canary", "shard", "layer", "metrics", "Terraform", "alerts"]
        var tasks = model.tasks
        let start = (tasks.map(\.id).max() ?? 0) + 1
        for index in 0..<500 {
            let id = start + index
            let parent: Int? = index % 5 == 0 ? nil : start + index - index % 5
            let title = (0..<4).map { words[(index * 7 + $0 * 3) % words.count] }.joined(separator: " ").capitalized
            tasks.append(TaskItem(id: id, title: title, status: TaskStatus.allCases[index % TaskStatus.allCases.count], type: TaskType.allCases[index % 5],
                                  project: ["Registry", "CDN", "HQ", nil][index % 4], tags: index % 3 == 0 ? ["perf"] : [],
                                  parent: parent, list: index % 10 < 3 ? .overview : .backlog, order: Double(index),
                                  created: now, modified: now, body: index % 25 == 0 ? "A description with a list:\n\n- [ ] one\n- [x] two" : ""))
        }
        model.tasks = tasks
        var sessions = model.sessions
        for index in 0..<30 {
            let id = String(format: "5eed1a26-0000-4000-8000-%012d", index)
            sessions.append(SessionItem(id: id, customName: "Large seed session \(index + 1)", status: SessionStatus(state: index % 7 == 0 ? .waiting(.question) : .working, since: now.addingTimeInterval(Double(-index * 60))),
                                        cwd: "~/code/repo\(index)", repo: "repo\(index)", branch: "branch-\(index)", started: now, tty: "/dev/ttys\(100 + index)",
                                        question: "Which one?", order: Double(20 + index)))
        }
        model.sessions = sessions
        for index in model.sessions.indices { model.sessions[index].faceSalt = model.faceSalt(for: model.sessions[index].id) }
    }

    /// What a seed artifact shows in test runs, which never reach claude.ai.
    static func githubPage(_ item: GitHubItem) -> String {
        """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <style>
          :root { color-scheme: light dark; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0; --bg: #ffffff; }
          @media (prefers-color-scheme: dark) { :root { --fg: #f0f6fc; --muted: #9198a1; --line: #3d444d; --bg: #0d1117; } }
          body { margin: 0; background: var(--bg); color: var(--fg); font: 14px/1.5 -apple-system, sans-serif; }
          main { max-width: 1012px; margin: 0 auto; padding: 32px 24px; display: grid; gap: 16px; }
          h1 { margin: 0; font-size: 32px; font-weight: 400; line-height: 40px; }
          h1 span { color: var(--muted); }
          p { margin: 0; color: var(--muted); }
          .tabs { display: flex; gap: 24px; border-bottom: 1px solid var(--line); padding-bottom: 8px; }
        </style>
        <main>
          <h1>\(item.title) <span>\(item.reference)</span></h1>
          <p>\(item.author) wants to merge into main. In test runs HQ shows this stand-in for the GitHub page.</p>
          <div class="tabs"><b>Conversation</b><span>Commits</span><span>Checks</span><span>Files changed</span></div>
        </main>
        """
    }

    static func artifactPage(_ artifact: ArtifactItem) -> String {
        """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <style>
          :root { color-scheme: light dark; --fg: #1c2230; --muted: #5b6475; --line: #dde1e8; --bg: #ffffff; }
          @media (prefers-color-scheme: dark) { :root { --fg: #e6e9ef; --muted: #9aa3b4; --line: #2a303b; --bg: #1e1e1e; } }
          body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.5 -apple-system, sans-serif; }
          main { max-width: 640px; margin: 0 auto; padding: 40px 24px; display: grid; gap: 16px; }
          h1 { margin: 0; font-size: 28px; line-height: 36px; }
          p { margin: 0; color: var(--muted); }
          table { border-collapse: collapse; }
          td, th { border-bottom: 1px solid var(--line); padding: 6px 16px 6px 0; text-align: left; }
        </style>
        <main>
          <h1>\(artifact.title)</h1>
          <p>A page Claude published on claude.ai. In test runs HQ shows this stand-in instead.</p>
          <table>
            <tr><th>Metric</th><th>Before</th><th>After</th></tr>
            <tr><td>Upload p99</td><td>4.1 s</td><td>2.7 s</td></tr>
            <tr><td>Retries per upload</td><td>0.9</td><td>0.08</td></tr>
          </table>
        </main>
        """
    }
}
