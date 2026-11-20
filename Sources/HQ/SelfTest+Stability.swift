import AppKit
import HQKit
import SwiftUI

/// v14's stability fixes: a turn that ends without a Stop (T-371).
extension SelfTest {
    static func stabilityChecks(_ model: AppModel) async {
        await cancelledTurnChecks(model)
        await answeredWaitChecks(model)
        remindedReviewChecks(model)
        nextReviewChecks(model)
        draftReviewChecks(model)
        await flowChecks()
        windowFrameChecks(model)
        bringForwardChecks(model)
        await lostClientChecks()
        await hangChecks(model)
        outlineDefectChecks()
    }

    /// T-689: the outline's container rounded to the screen's pixels is no defect; rows cut off or an outline short of it is.
    private static func outlineDefectChecks() {
        let page = NSRect(x: 0, y: 0, width: 885, height: 4327.5)
        check("an outline container rounded to half a point under its rows logs no defect (T-689)",
              OutlineContainer.defect(container: page, outline: page, rows: 4328.05) == nil)
        check("rows a point past their container, or an outline short of it, are a defect",
              OutlineContainer.defect(container: page, outline: page, rows: 4329) != nil
              && OutlineContainer.defect(container: page, outline: NSRect(x: 0, y: 0, width: 885, height: 4300), rows: 4327.5) != nil)
    }

    /// T-683: a main thread held over 2 s leaves a line in hangs.log and a sample of its stack; a banner click logs its steps.
    private static func hangChecks(_ model: AppModel) async {
        let before = HangWatch.stalls.count
        AppLog.expected.append("main thread stalled")
        usleep(4_000_000)
        for _ in 0..<50 where HangWatch.stalls.count == before { try? await Task.sleep(for: .milliseconds(100)) }
        let stall = HangWatch.stalls.count > before ? HangWatch.stalls.last : nil
        // sample(1) takes its second, then writes.
        func stack() -> String { stall?.sample.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" } // io: ok the self-test
        for _ in 0..<50 where !stack().contains("usleep") { try? await Task.sleep(for: .milliseconds(100)) }
        check("a main thread held 4 s leaves a line in hangs.log and a sample of its stack (T-683)",
              (stall?.seconds ?? 0) >= 2 && stack().contains("usleep"), "\(String(describing: stall?.seconds)) s, \(stall?.sample?.path ?? "no sample")")
        model.closeModal()
        AppLog.expected.append("banner click:")
        model.openFromBanner(clicked: CACurrentMediaTime())
        for _ in 0..<50 where AppLog.expected.contains("banner click:") { try? await Task.sleep(for: .milliseconds(100)) }
        check("a banner click opens the center and logs how long it took (T-683)", model.modal == .notifications && !AppLog.expected.contains("banner click:"),
              String(describing: model.modal))
        model.closeModal()
    }

    /// T-686: a hook gives up after 1 s while the main thread is busy; HQ writing its reply to the closed socket lives on.
    private static func lostClientChecks() async {
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        guard client >= 0, var address = try? AgentSocket.address(AgentSocket.path) else { return check("the self-test reaches HQ's socket", false) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        let request = Data("{\"command\":\"status\"}\n".utf8)
        let sent = request.withUnsafeBytes { Darwin.write(client, $0.baseAddress!, $0.count) }
        // Gone before the reply: the main thread, this one, answers only once it yields.
        close(client)
        try? await Task.sleep(for: .milliseconds(500))
        check("HQ lives on after replying to an hq command that left before its answer (T-686)", connected == 0 && sent == request.count,
              "connect \(connected), sent \(sent)")
    }

    /// T-380: Open HQ and every menu bar item that shows the window bring it from another Space. Spaces can't be driven
    /// here: what's checked is the call, and that the window belongs to one Space, which a real activation switches to.
    private static func bringForwardChecks(_ model: AppModel) {
        guard let window = model.window else { return check("the self-test has a window to bring forward", false) }
        let calls = AppModel.forwardCalls.count
        model.bringForward()
        check("Open HQ activates HQ (a test run without taking the focus) and orders its window front",
              AppModel.forwardCalls.count == calls + 1 && AppModel.forwardCalls.last == (Store.background ? "activate" : "activate ignoring other apps")
              && window.isVisible, "\(AppModel.forwardCalls.suffix(1))")
        check("HQ's window lives on one Space, so activating HQ goes to it (T-380)",
              window.collectionBehavior.isDisjoint(with: [.canJoinAllSpaces, .moveToActiveSpace, .stationary]), "\(window.collectionBehavior.rawValue)")
    }

    /// T-373: the window reopens where it was for this screen setup; a frame off every screen leaves today's placement.
    private static func windowFrameChecks(_ model: AppModel) {
        guard let window = model.window, let screen = (Store.testScreen ?? NSScreen.main)?.visibleFrame else {
            return check("the self-test has a window to place", false)
        }
        let defaults = Prefs.defaults, key = WindowFrame.currentKey
        defer {
            defaults.removeObject(forKey: key)
            Store.moveToTestScreen(window)
        }
        window.setFrame(window.frame.offsetBy(dx: -1, dy: 0), display: false)
        check("a test run keeps its own placement: it saves no frame", defaults.string(forKey: key) == nil)
        let frame = NSRect(x: screen.minX + 40, y: screen.minY + 40, width: max(Metric.windowMin.width, min(900, screen.width - 80)),
                           height: max(Metric.windowMin.height, min(700, screen.height - 80))).integral
        defaults.set(NSStringFromRect(frame), forKey: key)
        let restored = WindowFrame.restore(window, from: defaults)
        check("a saved frame for this screen setup is restored (T-373)", restored && window.frame == frame, "\(window.frame) for \(frame)")
        let before = window.frame
        let away = frame.offsetBy(dx: (NSScreen.screens.map(\.frame.maxX).max() ?? 0) + 4000, dy: 0)
        defaults.set(NSStringFromRect(away), forKey: key)
        check("a saved frame off every screen falls back to today's placement", !WindowFrame.restore(window, from: defaults) && window.frame == before)
        check("each screen setup keeps its own frame", WindowFrame.key(screens: [NSRect(x: 0, y: 0, width: 1512, height: 982)]) // grid: ok a laptop screen's size
              != WindowFrame.key(screens: [NSRect(x: 0, y: 0, width: 1512, height: 982), NSRect(x: 1512, y: 0, width: 2560, height: 1440)])) // grid: ok screen sizes
    }

    /// T-392, T-462: a review with something about it in Later leaves the Reviews list until it comes back; a reminder leaves it in Needs You.
    private static func remindedReviewChecks(_ model: AppModel) {
        let filter = model.reviewFilter
        model.reviewFilter = .all
        defer { model.reviewFilter = filter }
        guard let review = model.waitingReviews.first(where: { !model.inLater.contains($0.url) }) else {
            return check("the seed has a review that waits, with no reminder on it", false)
        }
        let other = model.reviewRequests.first { $0.url != review.url }
        let row = model.remind("Review this after lunch", at: .now.addingTimeInterval(3600), level: .important,
                               links: [ModalRoute.github(review.url).selectionKey])
        defer { model.notices.removeAll { $0.id == row.id } }
        check("a review with a reminder still to come leaves Reviews (T-392)", !model.reviewRequests.contains { $0.url == review.url }
              && other.map { o in model.reviewRequests.contains { $0.url == o.url } } != false, "\(model.reviewRequests.map(\.number))")
        check("and stays in Needs You", model.waitingReviews.contains { $0.url == review.url })
        if let index = model.notices.firstIndex(where: { $0.id == row.id }) { model.notices[index].dueAt = .now.addingTimeInterval(-1) }
        model.fireDue()
        check("it comes back to Reviews once the reminder is due", model.reviewRequests.contains { $0.url == review.url })
        let done = model.remind("Look again", at: .now.addingTimeInterval(3600), level: .update, links: [ModalRoute.github(review.url).selectionKey])
        defer { model.notices.removeAll { $0.id == done.id } }
        model.markRead(done.id)
        check("a reminder marked done before its time doesn't hide the review", model.reviewRequests.contains { $0.url == review.url })
        // T-462: Later on the review itself in Needs You, or on a notification about it, hides it too.
        model.putReviewLater(review.url, until: .now.addingTimeInterval(3600))
        check("a review put Later leaves Reviews until it comes back (T-462)", !model.reviewRequests.contains { $0.url == review.url },
              "\(model.reviewRequests.map(\.number))")
        model.putReviewLater(review.url, until: nil)
        check("and Bring Back Now brings it back", model.reviewRequests.contains { $0.url == review.url })
        let note = model.notify("Look at this one", level: .update, source: "selftest-later", links: [ModalRoute.github(review.url).selectionKey])
        defer { model.notices.removeAll { $0.id == note.id } }
        model.snooze(note.id, until: .now.addingTimeInterval(3600))
        check("a notification about it put Later hides it too", !model.reviewRequests.contains { $0.url == review.url })
    }

    /// T-456: Next Review marks the PR reviewed and shows the next one waiting in its place, Back kept; the last one has none.
    private static func nextReviewChecks(_ model: AppModel) {
        let seen = model.seen, saved = model.github
        defer { model.seen = seen; model.github = saved; model.closeModal() }
        // Two more like the seed's waiting review, asked a minute and two before it.
        guard var snapshot = saved, let first = model.waitingReviews.first else { return check("the seed has a review that waits", false) }
        for step in 1...2 {
            var copy = first
            copy.number = 9100 + step
            copy.url = first.url.replacingOccurrences(of: "/\(first.number)", with: "/\(copy.number)")
            copy.reviewRequestedAt = first.reviewRequestedAt.map { $0.addingTimeInterval(-60 * Double(step)) }
            snapshot.items.append(copy)
        }
        model.github = snapshot
        let filter = model.reviewFilter
        defer { model.reviewFilter = filter }
        model.reviewFilter = .waiting
        let waiting = model.reviewRequests
        guard waiting.count >= 3 else { return check("three reviews that wait", false, "\(waiting.count)") }
        model.open(.notifications)
        model.open(.github(waiting[0].url), push: true)
        check("Next Review goes to the next PR of the Reviews list", model.nextReview(after: waiting[0].url)?.url == waiting[1].url)
        model.goToNextReview(from: waiting[0].url)
        check("it shows the next in its place, the one it leaves still waiting, Back still to the center",
              model.githubItem(waiting[0].url).map(model.waitsForReview) == true && model.modal == .github(waiting[1].url)
              && model.modalStack == [.notifications], "\(String(describing: model.modal)) \(model.modalStack)")
        check("from the last one it goes around to the first the list shows",
              model.nextReview(after: waiting[waiting.count - 1].url)?.url == model.reviewRequests.first?.url)
        // The list as it shows: a reviewed PR is next with All or Not Approved, never with Waiting.
        var reviewedOne = snapshot
        if let index = reviewedOne.items.firstIndex(where: { $0.url == waiting[0].url }) { reviewedOne.items[index].myReviewAt = .now }
        model.github = reviewedOne
        model.reviewFilter = .all
        let all = model.reviewRequests
        let reviewed = all.firstIndex { $0.url == waiting[0].url }
        let before = reviewed.map { all[($0 + all.count - 1) % all.count].url }
        check("with All, a PR already reviewed is next too", before.flatMap { model.nextReview(after: $0) }?.url == waiting[0].url,
              "\(all.map(\.number))")
        model.reviewFilter = .waiting
        var reviewedAll = reviewedOne
        for item in waiting.dropFirst(2) {
            if let index = reviewedAll.items.firstIndex(where: { $0.url == item.url }) { reviewedAll.items[index].myReviewAt = .now }
        }
        model.github = reviewedAll
        check("with no other in the list, there is none: Open on GitHub instead", model.nextReview(after: waiting[1].url) == nil,
              "\(model.reviewRequests.map(\.number))")
    }

    /// T-457: a draft that asks for the user's review leaves Reviews and Needs You until Show Drafts.
    private static func draftReviewChecks(_ model: AppModel) {
        let saved = model.github
        defer { model.github = saved; model.reviewDrafts = false }
        guard var snapshot = saved, let index = snapshot.items.firstIndex(where: { item in model.waitingReviews.contains { $0.url == item.url } }) else {
            return check("the seed has a review that waits", false)
        }
        let url = snapshot.items[index].url
        snapshot.items[index].state = .draft
        model.github = snapshot
        func shown() -> (reviews: Bool, needsYou: Bool) {
            (model.allReviewRequests.contains { $0.url == url }, model.waitingReviews.contains { $0.url == url })
        }
        check("a draft that asks for your review leaves Reviews and Needs You by default (T-457)", shown() == (false, false), "\(shown())")
        model.reviewDrafts = true
        check("Show Drafts brings it back to both", shown() == (true, true), "\(shown())")
    }

    /// T-451: wrapping chips keep the lines they were measured with, however SwiftUI rounds their bounds: what follows
    /// never sits over the last line. Widths with fractions, the widest line just fitting, at every width around it.
    private static func flowChecks() async {
        final class Probe { var chips: CGFloat = 0; var below: CGFloat = 0 }
        var overlaps: [String] = []
        for width in stride(from: CGFloat(200), through: 224, by: 0.25) {
            let probe = Probe()
            let root = VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 8) {
                    ForEach([100.3, 100.2, 50.15], id: \.self) { chip in
                        Color.clear.frame(width: chip, height: 12)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("flow")).maxY } action: { probe.chips = max(probe.chips, $0) }
                    }
                }
                Color.clear.frame(height: 1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("flow")).minY } action: { probe.below = $0 }
            }
            .frame(width: width, alignment: .leading)
            .coordinateSpace(.named("flow"))
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 100)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
            if probe.chips > probe.below + 0.01 { overlaps.append("\(width): chips to \(probe.chips), next at \(probe.below)") }
        }
        check("wrapping chips never run under what follows them (T-451)", overlaps.isEmpty, overlaps.prefix(3).joined(separator: "; "))
    }

    /// A hook event with the session's pid, as `hq hook` sends it.
    private static func turnEvent(_ name: String, _ id: String, pid: Int32, _ extra: String = "") {
        _ = agent("hook", ["event": "{\"hook_event_name\":\"\(name)\",\"session_id\":\"\(id)\",\"cwd\":\"\(NSTemporaryDirectory())\"\(extra)}",
                           "pid": "\(pid)"])
    }

    /// Claude Code's record of `pid`, as it writes it in `~/.claude/sessions`.
    private static func claudeRecord(_ pid: Int32, session: String, status: String, at time: Date) {
        let millis = Int(time.timeIntervalSince1970 * 1000)
        try? FileManager.default.createDirectory(at: TurnWatch.directory, withIntermediateDirectories: true)
        try? #"{"pid":\#(pid),"sessionId":"\#(session)","status":"\#(status)","statusUpdatedAt":\#(millis),"updatedAt":\#(millis)}"#
            .write(to: TurnWatch.directory.appending(path: "\(pid).json"), atomically: true, encoding: .utf8)
    }

    /// T-691: an answer in the terminal sends no hook; Claude's own record stops saying "waiting". Approved, a long command
    /// runs with no tool event until it ends: Working at once. Refused, the turn ends: idle.
    private static func answeredWaitChecks(_ model: AppModel) async {
        let id = "57ab0000-0000-4000-8000-0000000000c2", pid: Int32 = 999_972
        let source = DispatchSource.makeProcessSource(identifier: getpid(), eventMask: .exit, queue: .main)
        source.resume()
        model.exitWatchers[pid] = source
        defer {
            model.sessions.removeAll { $0.id == id }
            model.exitWatchers[pid] = nil
            try? FileManager.default.removeItem(at: TurnWatch.directory.appending(path: "\(pid).json"))
        }
        func state() -> SessionState? { model.session(id)?.status.state }
        turnEvent("SessionStart", id, pid: pid, #","source":"startup""#)
        turnEvent("UserPromptSubmit", id, pid: pid, #","prompt":"deploy""#)
        let cases: [(name: String, event: String, extra: String, wait: WaitReason, claude: String, after: SessionState)] = [
            ("an approved permission", "PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"cargo run"}"#, .permission, "busy", .working),
            ("an approved long command", "PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"cargo run --release"}"#, .permission, "shell", .working),
            ("a refused permission", "PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"rm -rf target"}"#, .permission, "idle", .idle),
            ("a question answered", "PreToolUse", #","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Ship?","options":[{"label":"Yes"}]}]}"#, .question, "busy", .working),
            ("a plan approved", "PreToolUse", #","tool_name":"ExitPlanMode","tool_input":{"plan":"Do it"}"#, .plan, "busy", .working),
        ]
        for test in cases {
            if state() != .working { turnEvent("UserPromptSubmit", id, pid: pid, #","prompt":"go on""#) }
            turnEvent(test.event, id, pid: pid, test.extra)
            let asked = model.session(id)?.status.since ?? .now
            check("\(test.name): waits on the user first, and the watch runs", state() == .waiting(test.wait) && TurnWatch.running, String(describing: state()))
            claudeRecord(pid, session: id, status: "busy", at: asked.addingTimeInterval(-1))
            await TurnWatch.check(model)
            check("\(test.name): Claude's busy from before the wait answers nothing", state() == .waiting(test.wait), String(describing: state()))
            claudeRecord(pid, session: id, status: "waiting", at: asked.addingTimeInterval(0.1))
            await TurnWatch.check(model)
            check("\(test.name): Claude waiting holds the wait", state() == .waiting(test.wait), String(describing: state()))
            let answered = TurnWatch.answered
            claudeRecord(pid, session: id, status: test.claude, at: asked.addingTimeInterval(1))
            await TurnWatch.check(model)
            check("\(test.name): Claude \(test.claude) after the wait ends it, no hook needed", state() == test.after && TurnWatch.answered == answered + 1,
                  String(describing: state()))
        }
    }

    /// T-371: a prompt cancelled before any answer leaves no Stop and nothing in the transcript; Claude's own record says idle.
    private static func cancelledTurnChecks(_ model: AppModel) async {
        let id = "57ab0000-0000-4000-8000-0000000000c1", pid: Int32 = 999_971
        let source = DispatchSource.makeProcessSource(identifier: getpid(), eventMask: .exit, queue: .main)
        source.resume()
        model.exitWatchers[pid] = source
        defer {
            model.sessions.removeAll { $0.id == id }
            model.exitWatchers[pid] = nil
            try? FileManager.default.removeItem(at: TurnWatch.directory.appending(path: "\(pid).json"))
        }
        turnEvent("SessionStart", id, pid: pid, #","source":"startup""#)
        turnEvent("UserPromptSubmit", id, pid: pid, #","prompt":"test""#)
        check("a prompt makes the session work and starts the turn watch", model.session(id)?.status.state == .working && TurnWatch.running,
              "\(String(describing: model.session(id)?.status.state)), watch \(TurnWatch.running)")
        // Claude went busy, then the user pressed Esc before any answer: idle, and no Stop comes.
        let sent = model.session(id)?.status.since ?? .now
        claudeRecord(pid, session: id, status: "idle", at: sent.addingTimeInterval(0.4))
        await TurnWatch.check(model, now: sent.addingTimeInterval(1.5))
        check("a Stop just behind Claude's idle still wins: Working holds a moment", model.session(id)?.status.state == .working)
        turnEvent("Stop", id, pid: pid, #","last_assistant_message":"Done.""#)
        check("a Stop ends the turn as done", model.session(id)?.status.state == .done)
        await TurnWatch.check(model, now: .now.addingTimeInterval(10))
        check("Claude's idle doesn't turn a done session idle", model.session(id)?.status.state == .done)
        turnEvent("UserPromptSubmit", id, pid: pid, #","prompt":"test again""#)
        let again = model.session(id)?.status.since ?? .now
        claudeRecord(pid, session: id, status: "busy", at: again)
        await TurnWatch.check(model, now: again.addingTimeInterval(10))
        check("a Claude that says busy keeps Working", model.session(id)?.status.state == .working)
        let ended = TurnWatch.ended
        claudeRecord(pid, session: id, status: "idle", at: again.addingTimeInterval(0.4))
        await TurnWatch.check(model, now: again.addingTimeInterval(4))
        check("a prompt cancelled before any answer leaves Working within seconds (T-371)",
              model.session(id)?.status.state == .idle && TurnWatch.ended == ended + 1, String(describing: model.session(id)?.status.state))
        check("and the watch stops when no session works", !TurnWatch.running || model.sessions.contains { $0.isRunning && $0.pid != nil && $0.status.state == .working })
        // The real timer, not a call: Claude idle for a while with no Stop ends Working on its own.
        turnEvent("UserPromptSubmit", id, pid: pid, #","prompt":"once more""#)
        let last = model.session(id)?.status.since ?? .now
        claudeRecord(pid, session: id, status: "idle", at: last.addingTimeInterval(0.2))
        await expect("the turn watch ends a cancelled prompt's Working on its own", model.session(id)?.status.state == .idle,
                     String(describing: model.session(id)?.status.state), within: 8)
    }
}
