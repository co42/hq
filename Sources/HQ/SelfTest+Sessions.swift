import AppKit
import HQKit

/// Sessions under hook events and Close Session: the terminal the user watches, Ghostty's one queue, subagents, keys per
/// state, cards that never started, /clear and replayed events.
extension SelfTest {
    static func sessionFixChecks(_ model: AppModel) async {
        await watchedStopChecks(model)
        await bannerChecks(model)
        await bannerClickChecks(model)
        await ghosttyQueueChecks()
        subagentChecks(model)
        await closeKeysChecks(model)
        neverStartedChecks(model)
        await reopenChecks(model)
        clearChecks(model)
        replayOrderChecks(model)
        await teamChecks(model)
        await formsChecks(model)
        Ghostty.fake.withLock { $0 = Ghostty.Fake() }
    }

    /// A hook event as `hq hook` sends it, with the fields every real one carries.
    private static func event(_ name: String, _ id: String, _ extra: String = "", pid: Int32? = nil, tty: String? = nil, at: Date? = nil) {
        var args = ["event": "{\"hook_event_name\":\"\(name)\",\"session_id\":\"\(id)\",\"cwd\":\"\(NSTemporaryDirectory())\","
            + "\"transcript_path\":\"/tmp/HQ-selftest-\(id).jsonl\",\"permission_mode\":\"default\"\(extra)}"]
        if let pid { args["pid"] = "\(pid)" }
        if let tty { args["tty"] = tty }
        if let at { args["at"] = at.formatted(.iso8601) }
        agent("hook", args)
    }

    /// A pid that stands for a running Claude: its exit watch is already in place, on HQ's own process.
    private static func hold(_ pid: Int32, _ model: AppModel) {
        let source = DispatchSource.makeProcessSource(identifier: getpid(), eventMask: .exit, queue: .main)
        source.resume()
        model.exitWatchers[pid] = source
    }

    private static func watchedStopChecks(_ model: AppModel) async {
        let id = "5e550000-0000-4000-8000-0000000000b1", tty = "/dev/ttys0b1"
        Ghostty.fake.withLock { $0 = Ghostty.Fake(); $0.focused = tty }
        event("SessionStart", id, #","source":"startup""#, tty: tty)
        event("UserPromptSubmit", id, #","prompt":"Tidy the push path""#)
        event("Stop", id, #","last_assistant_message":"Done.""#)
        check("a Stop while Ghostty isn't in front stays unread", model.session(id)?.status.isNew == true)
        Ghostty.fake.withLock { $0.front = true }
        event("UserPromptSubmit", id, #","prompt":"Go on""#)
        event("Stop", id, #","last_assistant_message":"Done again.""#)
        await expect("a Stop on the terminal the user watches in Ghostty is read", model.session(id)?.status.unread == false,
                     String(describing: model.session(id)?.status))
        let fake = Ghostty.fake.withLock { $0 }
        check("and Ghostty was asked off the main thread", fake.scripts.count == 1 && fake.onMain == 0, "\(fake.scripts.count) scripts, \(fake.onMain) on main")
        Ghostty.fake.withLock { $0.front = false }
        model.sessions.removeAll { $0.id == id }
    }

    /// T-657: a banner with its sound for everything that needs the user, HQ in front too; none only while that session's
    /// terminal has the focus (Ghostty in front, its front window's selected tab), not when it's merely on screen.
    private static func bannerChecks(_ model: AppModel) async {
        let id = "5e550000-0000-4000-8000-0000000000b3", tty = "/dev/ttys0b3", name = "Banner rules"
        let delay = AppModel.bannerDelay
        AppModel.bannerDelay = 0.1
        defer {
            AppModel.bannerDelay = delay
            Ghostty.fake.withLock { $0 = Ghostty.Fake() }
            model.sessions.removeAll { $0.id == id }
        }
        check("a banner shows with its sound while HQ is in front", BannerDelegate.presentation.contains(.banner) && BannerDelegate.presentation.contains(.sound))
        event("SessionStart", id, #","source":"startup""#, tty: tty)
        model.renameSession(id, to: name)
        func asks(_ question: String) async -> String {
            event("UserPromptSubmit", id, #","prompt":"go""#)
            let before = model.ghosttyLog.count
            event("PreToolUse", id, #","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"\#(question)","options":[{"label":"Yes"}]}]}"#)
            await expect("\(question): HQ decides about its banner", model.ghosttyLog.dropFirst(before).contains { $0.contains("banner \(name) needs you") }, within: 2)
            return model.ghosttyLog.dropFirst(before).last { $0.contains("banner \(name)") } ?? ""
        }
        let cases: [(name: String, front: Bool, focused: String?, banner: Bool)] = [
            ("Ghostty in the back", false, nil, true),
            ("its terminal on screen, Ghostty in the back", false, tty, true),
            ("Ghostty in front on another terminal", true, "/dev/ttys0b4", true),
            ("its terminal has the focus", true, tty, false),
        ]
        for test in cases {
            Ghostty.fake.withLock { $0 = Ghostty.Fake(); $0.front = test.front; $0.focused = test.focused }
            let said = await asks(test.name)
            check("\(test.name): \(test.banner ? "a banner" : "no banner")", said.hasPrefix(test.banner ? "banner" : "no banner"), said)
        }
        Ghostty.fake.withLock { $0 = Ghostty.Fake(); $0.front = true; $0.focused = tty }
        let skipped = "banner skipped: \(name) needs you → notice:", shown = "banner shown: \(name) needs you → notice:"
        AppLog.expected.append(skipped)
        let ping = model.notify("Merge it?", level: .important, source: id)
        await expect("a ping from a session whose terminal has the focus: no banner", model.ghosttyLog.contains("no banner \(name) needs you: its terminal has the focus"))
        await expect("notices.log says the banner was skipped and why (T-705)", !AppLog.expected.contains(skipped), within: 1)
        model.notices.removeAll { $0.id == ping.id }
        Ghostty.fake.withLock { $0.front = false }
        AppLog.expected.append(shown)
        let other = model.notify("Merge it now?", level: .important, source: id)
        await expect("the same ping, Ghostty in the back: a banner", model.ghosttyLog.contains { $0.hasPrefix("banner \(name) needs you: Merge it now?") })
        await expect("notices.log says the banner was shown (T-705)", !AppLog.expected.contains(shown), within: 1)
        model.notices.removeAll { $0.id == other.id }
        // A review asked of the user: a banner, once; the ones waiting the first time are known, not new.
        guard let review = model.waitingReviews.first else { return check("a review that waits", false) }
        let events = model.noticeStore.githubEvents
        defer { model.noticeStore.githubEvents = events }
        model.noticeStore.githubEvents = events.filter { !$0.key.contains("|review|") }
        let logged = model.ghosttyLog.count
        model.bannerNewReviews()
        check("the reviews waiting the first time post no banner", !model.ghosttyLog.dropFirst(logged).contains { $0.contains("waits for your review") })
        model.noticeStore.githubEvents = model.noticeStore.githubEvents.filter { !$0.key.hasPrefix("\(review.url)|review|") }
        model.bannerNewReviews()
        model.bannerNewReviews()
        check("a review newly asked: one banner", model.ghosttyLog.dropFirst(logged).filter { $0.hasPrefix("banner \(review.reference) waits for your review") }.count == 1,
              model.ghosttyLog.dropFirst(logged).joined(separator: "; "))
    }

    /// T-690: a banner click opens its item: a waiting session's or a ping's terminal, a review's PR, the rest the center
    /// on its row. Each banner is clicked by what it carries.
    private static func bannerClickChecks(_ model: AppModel) async {
        let id = "5e550000-0000-4000-8000-0000000000b5", tty = "/dev/ttys0b5"
        let delay = AppModel.bannerDelay
        AppModel.bannerDelay = 0.1
        Ghostty.fake.withLock { $0 = Ghostty.Fake() }
        defer {
            AppModel.bannerDelay = delay
            model.sessions.removeAll { $0.id == id }
            model.closeModal()
        }
        /// The last banner whose line has `text`, clicked.
        func click(_ text: String) async -> String? {
            await expect("a banner with “\(text)”", model.ghosttyLog.contains { $0.hasPrefix("banner") && $0.contains(text) }, within: 2)
            guard let line = model.ghosttyLog.last(where: { $0.hasPrefix("banner") && $0.contains(text) }),
                  let opens = line.components(separatedBy: " → ").last else { return nil }
            model.closeModal()
            let logged = model.ghosttyLog.count
            model.openFromBanner(clicked: CACurrentMediaTime(), opens: opens)
            await expect("the click on “\(text)” lands", AppModel.bannerOpened.last != nil, within: 1)
            return model.ghosttyLog.dropFirst(logged).first { $0.hasPrefix("focus") } ?? AppModel.bannerOpened.last
        }
        event("SessionStart", id, #","source":"startup""#, tty: tty)
        model.renameSession(id, to: "Banner clicks")
        event("UserPromptSubmit", id, #","prompt":"go""#)
        event("PermissionRequest", id, #","tool_name":"Bash","tool_input":{"command":"make deploy"}"#)
        let waiting = await click("Banner clicks needs you: ")
        check("a waiting session's banner focuses its terminal, the center stays shut", waiting == "focus \(tty)" && model.modal == nil, waiting ?? "none")
        let ping = model.notify("Canary green: merge?", level: .important, source: id)
        AppLog.expected.append("ping read by a click on its banner: session Banner clicks")
        let pinged = await click("Canary green: merge?")
        check("a ping's banner focuses its session's terminal and reads it", pinged == "focus \(tty)" && model.notices.first { $0.id == ping.id }?.readAt != nil,
              pinged ?? "none")
        check("notices.log says what read the ping (T-705)", !AppLog.expected.contains("ping read by a click on its banner: session Banner clicks"))
        let reminder = model.remind("Call the bank", at: .now.addingTimeInterval(-1), level: .important)
        model.fireDue()
        _ = await click("Call the bank")
        check("a reminder's banner opens the center on its row", model.modal == .notifications && model.noticeSelection == reminder.id.uuidString,
              "\(String(describing: model.modal)), \(model.noticeSelection ?? "-")")
        model.notices.removeAll { $0.id == reminder.id }
        if let review = model.waitingReviews.first {
            let events = model.noticeStore.githubEvents
            model.noticeStore.githubEvents = events.filter { !$0.key.hasPrefix("\(review.url)|review|") }.merging(["|review|seeded": .now]) { a, _ in a }
            model.bannerNewReviews()
            _ = await click("\(review.reference) waits for your review")
            check("a review's banner opens its PR's window", model.modal == .github(review.url), String(describing: model.modal))
            model.noticeStore.githubEvents = events
        } else {
            check("a review that waits", false)
        }
    }

    private static func ghosttyQueueChecks() async {
        Ghostty.fake.withLock { $0 = Ghostty.Fake(); $0.focused = "/dev/ttys0b2"; $0.delay = 0.05 }
        let calls = (0..<4).map { _ in Task.detached { try? Ghostty.focusedTTY() } }
        var answers: [String?] = []
        for call in calls { answers.append(await call.value) }
        let fake = Ghostty.fake.withLock { $0 }
        check("Ghostty's scripts run one at a time, whoever calls", fake.mostAtOnce == 1 && answers.allSatisfy { $0 == "/dev/ttys0b2" },
              "\(fake.mostAtOnce) at once, \(answers)")
        check("each gives Ghostty \(Ghostty.timeout) s to answer", fake.scripts.count == 4
              && fake.scripts.allSatisfy { $0.hasPrefix("with timeout of \(Ghostty.timeout) seconds\n") && $0.hasSuffix("\nend timeout") })
    }

    private static func subagentChecks(_ model: AppModel) {
        let id = "5e550000-0000-4000-8000-0000000000b3"
        let subagent = #","agent_id":"a30b76807c386c37b","agent_type":"general-purpose""#
        event("SessionStart", id, #","source":"startup""#)
        event("UserPromptSubmit", id, #","prompt":"Review the push path with three agents""#)
        event("PreToolUse", id, #","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which bucket?","options":[{"label":"A"}]}]}"#)
        event("PostToolUse", id, #","tool_name":"Read","tool_input":{"file_path":"/tmp/a.go"},"tool_response":{"type":"text"}"# + subagent)
        check("a subagent's tool call leaves the question its session asks", model.session(id)?.status.state == .waiting(.question),
              String(describing: model.session(id)?.status.state))
        event("PostToolUse", id, #","tool_name":"AskUserQuestion","tool_input":{"questions":[]}"#)
        check("and the answer ends it", model.session(id)?.status.state == .working)
        event("PermissionRequest", id, #","tool_name":"Bash","tool_input":{"command":"rm -rf build"}"# + subagent)
        event("PostToolUse", id, #","tool_name":"Read","tool_input":{"file_path":"/tmp/b.go"}"#)
        check("a subagent's permission holds through the main thread's tool calls", model.session(id)?.status.state == .waiting(.permission))
        event("PostToolUse", id, #","tool_name":"Bash","tool_input":{"command":"rm -rf build"}"# + subagent)
        check("and ends with the subagent's own", model.session(id)?.status.state == .working)
        model.sessions.removeAll { $0.id == id }
    }

    private static func closeKeysChecks(_ model: AppModel) async {
        let id = "5e550000-0000-4000-8000-0000000000b4", tty = "/dev/ttys0b4", pid: Int32 = 999_994
        event("SessionStart", id, #","source":"startup""#)
        event("UserPromptSubmit", id, #","prompt":"Restart the API""#)
        event("PermissionRequest", id, #","tool_name":"Bash","tool_input":{"command":"kubectl rollout restart deploy/api"}"#)
        guard var item = model.session(id) else { return check("Close Session per state", false, "no session") }
        item.pid = pid
        item.tty = tty
        model.put(item)
        model.closeSession(id)
        check("Close Session types nothing into a permission prompt: it asks the user to answer first",
              model.ghosttyLog.last == "ask answer first \(id)" && model.closingTerminals[pid] == nil, model.ghosttyLog.last ?? "-")
        event("PostToolUse", id, #","tool_name":"Bash","tool_input":{"command":"kubectl rollout restart deploy/api"}"#)
        let wait = AppModel.exitWait
        AppModel.exitWait = .milliseconds(200)
        model.closeSession(id)
        check("Close Session on a working session stops its turn with Escape before /exit",
              model.ghosttyLog.last == "escape, then clear the input, then type /exit in \(tty)" && model.closingTerminals[pid] == tty, model.ghosttyLog.last ?? "-")
        // Text the user left in Claude's input would turn /exit into a message: Control-C empties it first (T-443).
        let script = Ghostty.typeScript("/exit", tty: tty, interrupting: true, clearing: true)
        let keys = ["send key \"escape\"", "send key \"c\" modifiers \"control\"", "input text \"/exit\"", "send key \"enter\""].map { script.range(of: $0)?.lowerBound }
        check("Close Session's keys: Escape while it works, then Control-C to empty Claude's input, then /exit and Return, in that order",
              keys.allSatisfy { $0 != nil } && keys.compactMap(\.self) == keys.compactMap(\.self).sorted(), script)
        await expect("a /exit that didn't take never closes the terminal later", model.closingTerminals[pid] == nil)
        AppModel.exitWait = wait
        model.sessions.removeAll { $0.id == id }
    }

    private static func neverStartedChecks(_ model: AppModel) {
        let started = model.startSession(named: "Never ran", in: NSTemporaryDirectory())
        model.closeSession(started)
        check("Close Session on a card whose Claude never reported removes it", model.session(started) == nil
              && !model.gridSessions.contains { $0.id == started })
        // A resume whose tab never opens: the card goes back to Closed Sessions.
        let id = "5e550000-0000-4000-8000-0000000000b5"
        event("SessionStart", id, #","source":"startup""#)
        event("UserPromptSubmit", id, #","prompt":"Check the bucket policy""#)
        event("SessionEnd", id, #","reason":"prompt_input_exit""#)
        let closed = model.session(id)?.closedAt
        model.ghosttyFails = true
        model.resume(id)
        model.ghosttyFails = false
        model.problem = nil
        check("a resume whose tab fails leaves the card in Closed Sessions", closed != nil && model.session(id)?.closedAt == closed
              && !model.gridSessions.contains { $0.id == id })
        // Ended but still on the grid (a resume that never reported): Close Session closes it.
        if var item = model.session(id) {
            item.closedAt = nil
            model.put(item)
        }
        model.closeSession(id)
        check("Close Session on an ended card still on the grid closes it", model.session(id)?.closedAt != nil
              && !model.gridSessions.contains { $0.id == id })
        model.sessions.removeAll { $0.id == id }
        // At launch: a card that never reported goes, unless it was just started.
        let saved = model.sessions
        let old = SessionItem(id: "5e550000-0000-4000-8000-0000000000b6", customName: "Started long ago", status: SessionStatus(state: .idle, since: .now),
                              cwd: "/tmp", repo: "", branch: "", origin: nil, started: .now.addingTimeInterval(-600), order: 1)
        var fresh = old
        fresh.id = "5e550000-0000-4000-8000-0000000000b7"
        fresh.started = .now
        fresh.order = 2
        model.sessions = [old, fresh]
        model.reviveSessions()
        check("a card that never reported doesn't survive a relaunch; one just started does", model.session(old.id) == nil && model.session(fresh.id) != nil,
              "\(model.sessions.map(\.customName))")
        model.sessions = saved
    }

    /// Open when HQ quit, gone at launch: Closed Sessions offers to reopen them, top cards first (T-505).
    private static func reopenChecks(_ model: AppModel) async {
        let saved = model.sessions
        let lead = "5e550000-0000-4000-8000-0000000000d1", worker = "5e550000-0000-4000-8000-0000000000d2", closed = "5e550000-0000-4000-8000-0000000000d3"
        func item(_ id: String, _ name: String, parent: String? = nil, closedAt: Date? = nil) -> SessionItem {
            var item = SessionItem(id: id, customName: name, status: SessionStatus(state: .done, since: .now), cwd: "/tmp", repo: "reopen", branch: "main",
                                   started: .now.addingTimeInterval(-600), pid: 999_981, tty: "/dev/ttys981", order: 1)
            item.transcriptPath = "/tmp/HQ-selftest-\(id).jsonl"
            item.parent = parent
            item.closedAt = closedAt
            return item
        }
        model.dismissReopen()
        model.sessions = [item(worker, "Reopen worker", parent: lead), item(lead, "Reopen lead"), item(closed, "Closed before", closedAt: .now.addingTimeInterval(-60))]
        model.reviveSessions()
        check("at launch, the sessions open when HQ quit whose Claude is gone are offered, top cards first; one closed before isn't",
              model.reopenable.map(\.id) == [lead, worker] && model.session(lead)?.closedAt != nil, "\(model.reopenable.map(\.name))")
        model.reviveSessions()
        check("the offer outlives a relaunch", model.reopenable.map(\.id) == [lead, worker])
        let log = model.ghosttyLog.count
        model.reopenAll()
        await expect("Reopen All resumes the top card first, and the offer goes", model.ghosttyLog.dropFirst(log).first?.contains("claude --resume \(lead)") == true
              && model.reopenable.isEmpty, "\(model.ghosttyLog.dropFirst(log))")
        await expect("then the one under it, once its leader runs or after a while", model.ghosttyLog.dropFirst(log).contains { $0.contains("claude --resume \(worker)") },
                     "\(model.ghosttyLog.dropFirst(log))")
        model.sessions = [item(lead, "Reopen lead")]
        model.reviveSessions()
        model.dismissReopen()
        model.reviveSessions()
        check("Dismiss ends the offer, for good", model.reopenable.isEmpty)
        model.sessions = [item(lead, "Reopen lead")]
        model.reviveSessions()
        model.reopenOffer?.at = .now.addingTimeInterval(-AppModel.reopenKept - 60)
        check("after 24 h it's gone", model.reopenable.isEmpty)
        model.dismissReopen()
        // HQ quit first, then Ghostty: launch can't tell an idle session with no pid is gone; its SessionEnd, kept by `hq hook`
        // while HQ was off, replays a moment later and it joins the offer.
        var quiet = item(lead, "Reopen lead")
        quiet.status = SessionStatus(state: .idle, since: .now.addingTimeInterval(-120))
        quiet.pid = nil
        model.sessions = [quiet]
        model.reviveSessions()
        let openAfterLaunch = model.session(lead)?.isRunning == true
        event("SessionEnd", lead, ",\"reason\":\"other\"", at: .now.addingTimeInterval(-30))
        await expect("a session whose end replays at launch, from hooks kept while HQ was off, is offered too",
                     openAfterLaunch && model.session(lead)?.closedAt != nil && model.reopenable.map(\.id) == [lead],
                     "open after launch \(openAfterLaunch), closed \(String(describing: model.session(lead)?.closedAt)), offer \(model.reopenable.map(\.name))")
        model.dismissReopen()
        model.sessions = saved
    }

    private static func clearChecks(_ model: AppModel) {
        let old = "5e550000-0000-4000-8000-0000000000c1", new = "5e550000-0000-4000-8000-0000000000c2", pid: Int32 = 999_991
        hold(pid, model)
        event("SessionStart", old, #","source":"startup""#)
        event("UserPromptSubmit", old, #","prompt":"Harden the push path""#)
        model.renameSession(old, to: "Push path")
        if var item = model.session(old) {
            item.pid = pid
            item.tty = "/dev/ttys0c1"
            model.put(item)
        }
        let done = model.tasks.first { $0.status == .done }
        model.link(task: 45, session: old)
        if let done { model.link(task: done.id, session: old) }
        let before = model.session(old)
        event("SessionEnd", old, #","reason":"clear""#)
        event("SessionStart", new, #","source":"clear""#, pid: pid, tty: "/dev/ttys0c1")
        let after = model.session(new)
        check("after /clear the session keeps its face, its name and its place on the grid",
              after?.face == before?.face && after?.name == "Push path" && after?.order == before?.order && after?.onGrid == true,
              "\(String(describing: after?.name)), order \(String(describing: after?.order)) vs \(String(describing: before?.order))")
        check("the conversation before /clear goes to Closed Sessions", model.closedSessions.contains { $0.id == old })
        check("and its tasks not done come along", model.tasks(of: new).map(\.id).contains(45)
              && (done.map { !model.tasks(of: new).map(\.id).contains($0.id) } ?? true), "\(model.tasks(of: new).map(\.key))")
        let linked = agent("task link", ["task": "T-45", "item": "https://example.com/clear-check", "_session": new])
        check("its hq task commands keep working on them", linked["error"] == nil, "\(linked)")
        model.unlink(task: 45, session: old)
        model.unlink(task: 45, session: new)
        if let done { model.unlink(task: done.id, session: old) }
        model.changeTask(45, "Unlink") { $0.links.removeAll { $0.absoluteString == "https://example.com/clear-check" } }
        model.exitWatchers.removeValue(forKey: pid)?.cancel()
        model.sessions.removeAll { $0.id == old || $0.id == new }
    }

    private static func replayOrderChecks(_ model: AppModel) {
        let id = "5e550000-0000-4000-8000-0000000000d1"
        event("SessionStart", id, #","source":"startup""#)
        event("UserPromptSubmit", id, #","prompt":"Ship it""#)
        event("Stop", id, #","last_assistant_message":"Shipped.""#)
        let status = model.session(id)?.status
        // `hq hook` kept these while HQ launched; they replay after the live Stop.
        event("UserPromptSubmit", id, #","prompt":"Ship it""#, at: .now.addingTimeInterval(-5))
        event("PermissionRequest", id, #","tool_name":"Bash","tool_input":{"command":"make ship"}"#, at: .now.addingTimeInterval(-4))
        check("a replayed event older than a live one changes nothing", model.session(id)?.status == status && status?.isNew == true,
              String(describing: model.session(id)?.status))
        model.sessions.removeAll { $0.id == id }
    }
}
