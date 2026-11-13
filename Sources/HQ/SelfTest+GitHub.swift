import AppKit
import HQKit

extension SelfTest {
    /// Reminder times, a Blocked task's subtasks, which linked PRs a poll asks about, front matter that keeps a newline.
    static func githubFixChecks(_ model: AppModel) async {
        remindChecks()
        heldChecks(model)
        linkOrderChecks(model)
        frontMatterChecks(model)
        unfetchedTitleChecks(model)
        await mermaidChecks()
    }

    /// A GitHub link HQ hasn't fetched reads owner/repo#n, never its whole address (T-449).
    private static func unfetchedTitleChecks(_ model: AppModel) {
        let issue = ModalRoute.github("https://github.com/acme/unfetched/issues/9002")
        let files = ModalRoute.github("https://github.com/acme/unfetched/pull/418/files")
        check("an unfetched GitHub link reads owner/repo#n (T-449)", model.title(of: issue) == "acme/unfetched#9002"
              && model.title(of: files) == "acme/unfetched#418", "\(model.title(of: issue)) · \(model.title(of: files))")
        check("and its short title is its number", model.shortTitle(of: files) == "#418", model.shortTitle(of: files))
    }

    /// A Blocked reason with a line break stays on its key's line and reads back whole.
    private static func frontMatterChecks(_ model: AppModel) {
        guard let task = model.addTask(to: .backlog, title: "Two-line reason") else { return check("a task to block", false) }
        let reason = "Waiting on X\nsee Slack"
        agent("task block", ["task": task.key, "reason": reason])
        let path = model.task(task.id)?.path ?? ""
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let read = Vault.task(at: URL(fileURLWithPath: path), modified: .now)
        check("a reason with a line break is written on one line, and reads back as it was",
              text.contains(#"blocked_reason: "Waiting on X\nsee Slack""#) && read?.blockedReason == reason
                && FrontMatter(text).lines.allSatisfy { $0.contains(":") || $0.hasPrefix(" ") }, text)
        model.deleteTasks([task.id])
    }

    /// A diagram that failed is tried again; one that takes too long doesn't hold the next; a lost web process is replaced.
    private static func mermaidChecks() async {
        let renderer = MermaidRenderer.shared
        let stamp = UUID().uuidString.prefix(8)
        func diagram(_ name: String) -> String { "graph TD\n  A\(stamp)\(name) --> B" }
        guard case .image = await renderer.render(diagram("first"), dark: false) else { return check("a diagram draws", false) }
        // A failure is shown a while, then tried again.
        let broken = "graph TD\n  A\(stamp) -->"
        let failed = await renderer.render(broken, dark: false)
        let lasts = MermaidRenderer.failureLasts
        MermaidRenderer.failureLasts = 0.2
        try? await Task.sleep(for: .milliseconds(300))
        let forgotten = renderer.cached(broken, dark: false) == nil
        MermaidRenderer.failureLasts = lasts
        check("a diagram that failed is tried again later, not failed for good", { if case .failed = failed { forgotten } else { false } }())
        // One that takes too long fails, and the next one draws on a new page.
        let timeout = MermaidRenderer.timeout
        MermaidRenderer.timeout = .milliseconds(1)
        let slow = await renderer.render(diagram("slow"), dark: false)
        MermaidRenderer.timeout = timeout
        let pages = renderer.pages
        let after = await renderer.render(diagram("after"), dark: false)
        check("a diagram that takes too long fails, and the next one still draws, on a new page",
              { if case .failed = slow, case .image = after { renderer.pages == pages + 1 } else { false } }(), "\(slow), \(after)")
        // The page's web process ends: the next diagram makes a new page.
        guard let process = renderer.webProcess else { return check("the Mermaid page's web process is known", false) }
        kill(process, SIGKILL)
        await expect("WebKit tells the renderer its web process ended", renderer.webProcess != process, within: 5)
        let revived = await renderer.render(diagram("revived"), dark: false)
        check("after its web process ends, diagrams draw again", { if case .image = revived { true } else { false } }(), "\(revived)")
    }

    /// `hq remind --at` reads every word or refuses, and says the time it read.
    private static func remindChecks() {
        let calendar = Calendar.current
        let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
            .flatMap { calendar.date(bySettingHour: 15, minute: 0, second: 0, of: $0) }
        let reminded = agent("remind", ["text": "Look at the canary again", "at": "tomorrow at 15:00"])
        let due = (reminded["due"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        let when = expected.map(ReminderTime.full) ?? "-"
        check("hq remind --at \"tomorrow at 15:00\" is tomorrow at 15:00, and its reply says so",
              due == expected && reminded["when"] as? String == when && AgentCLI.human(reminded).contains("due \(when)"), "\(reminded)")
        if let id = reminded["id"] as? String { agent("notification delete", ["id": id]) }
        let refused = agent("remind", ["text": "Look at the canary again", "at": "tomorrow at 15:00 maybe"])
        let message = (refused["error"] as? JSONObject)?["message"] as? String ?? ""
        check("a word hq remind doesn't read is refused, and named", message.contains("\"maybe\""), "\(refused)")
        if let id = refused["id"] as? String { agent("notification delete", ["id": id]) }
    }

    /// A Blocked task holds what's under it: its subtasks aren't ready, and say what holds them.
    private static func heldChecks(_ model: AppModel) {
        guard let parent = model.addTask(to: .backlog, title: "Waits on a decision"),
              let sub = model.addSubtask(to: parent.id, title: "Its first part") else { return check("a task and a subtask to hold", false) }
        model.block(parent.id, reason: "Waiting on infra")
        let shown = agent("task show", ["task": parent.key])
        let line = (shown["subtasks"] as? [JSONObject])?.first { $0["id"] as? String == sub.key }
        check("a Blocked task's subtask isn't ready: held by it, counted blocked",
              model.taskFlow.state(sub.id) == .held && (shown["ready"] as? [String]) == [] && line?["flow"] as? String == "held by \(parent.key)"
                && model.taskFlow.tally(of: parent.id).blocked == 1, "\(shown)")
        model.unblock(parent.id)
        check("unblocked, the subtask is ready again", model.taskFlow.state(sub.id) == .ready
              && (agent("task show", ["task": parent.key])["ready"] as? [String]) == [sub.key])
        model.deleteTasks([sub.id, parent.id])
    }

    /// The poll asks first about the links that need a fresh state, then the done tasks' ones, newest first.
    private static func linkOrderChecks(_ model: AppModel) {
        let urls = (1...3).map { "https://github.com/acme/selftest/pull/\($0)" }
        guard let older = model.addTask(to: .backlog, title: "Shipped first"), let newer = model.addTask(to: .backlog, title: "Shipped next"),
              let open = model.addTask(to: .backlog, title: "Still open") else { return check("tasks to link", false) }
        model.link(task: older.id, url: URL(string: urls[0])!)
        model.setStatus(older.id, .done)
        model.link(task: newer.id, url: URL(string: urls[1])!)
        model.setStatus(newer.id, .done)
        model.link(task: open.id, url: URL(string: urls[2])!)
        let links = model.githubLinks()
        let rest = links.rest.filter(urls.contains)
        check("a poll asks about an open task's PR first, then done tasks' newest first",
              links.fresh.contains(urls[2]) && rest == [urls[1], urls[0]], "fresh \(links.fresh), rest \(links.rest)")
        model.deleteTasks([older.id, newer.id, open.id])
    }
}
