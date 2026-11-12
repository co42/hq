import AppKit
import HQKit

/// v14's stability fixes: a turn that ends without a Stop (T-371).
extension SelfTest {
    static func stabilityChecks(_ model: AppModel) async {
        await cancelledTurnChecks(model)
        remindedReviewChecks(model)
        windowFrameChecks(model)
        bringForwardChecks(model)
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

    /// T-392: a review with a reminder still to come leaves the Reviews list until the reminder is due, and stays in Needs You.
    private static func remindedReviewChecks(_ model: AppModel) {
        let filter = model.reviewFilter
        model.reviewFilter = .all
        defer { model.reviewFilter = filter }
        guard let review = model.waitingReviews.first(where: { !model.remindedLater.contains($0.url) }) else {
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
        TurnWatch.check(model, now: sent.addingTimeInterval(1.5))
        check("a Stop just behind Claude's idle still wins: Working holds a moment", model.session(id)?.status.state == .working)
        turnEvent("Stop", id, pid: pid, #","last_assistant_message":"Done.""#)
        check("a Stop ends the turn as done", model.session(id)?.status.state == .done)
        TurnWatch.check(model, now: .now.addingTimeInterval(10))
        check("Claude's idle doesn't turn a done session idle", model.session(id)?.status.state == .done)
        turnEvent("UserPromptSubmit", id, pid: pid, #","prompt":"test again""#)
        let again = model.session(id)?.status.since ?? .now
        claudeRecord(pid, session: id, status: "busy", at: again)
        TurnWatch.check(model, now: again.addingTimeInterval(10))
        check("a Claude that says busy keeps Working", model.session(id)?.status.state == .working)
        let ended = TurnWatch.ended
        claudeRecord(pid, session: id, status: "idle", at: again.addingTimeInterval(0.4))
        TurnWatch.check(model, now: again.addingTimeInterval(4))
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
