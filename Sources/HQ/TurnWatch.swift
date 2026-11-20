import Foundation
import HQKit

/// What no hook reports (PLAN.md §6): while a session works or waits on the user, Claude Code's own record of it is read
/// every few seconds. A session its Claude says is idle leaves Working; one its Claude says no longer waits was answered
/// in the terminal (T-691).
@MainActor
enum TurnWatch {
    private static var timer: Timer?
    /// How many sessions it ended, and how many waits it ended, for the self-test.
    static var ended = 0
    static var answered = 0

    /// Claude Code's records: `~/.claude/sessions`, or a folder beside a test store.
    static var directory: URL {
        Store.isOverridden ? Store.directory.appending(path: "claude-sessions", directoryHint: .isDirectory)
            : URL.homeDirectory.appending(path: ".claude/sessions", directoryHint: .isDirectory)
    }

    static var running: Bool { timer != nil }

    private static func watched(_ item: SessionItem) -> Bool {
        guard item.isRunning, item.pid != nil else { return false }
        if case .waiting = item.status.state { return true }
        return item.status.state == .working
    }

    /// Runs while a running session works or waits, stops when none does.
    static func update(_ model: AppModel) {
        let watching = model.sessions.contains(where: watched)
        if watching, timer == nil {
            let next = Timer(timeInterval: 2, repeats: true) { [weak model] _ in
                MainActor.assumeIsolated { if let model { Task { await check(model) } } }
            }
            next.tolerance = 0.5
            RunLoop.main.add(next, forMode: .common)
            timer = next
        } else if !watching {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Claude's records are read off the main thread (T-683).
    static func check(_ model: AppModel, now: Date = .now) async {
        let directory = directory
        let records = model.sessions.filter(watched)
            .compactMap { item in item.pid.map { (item.id, directory.appending(path: "\($0).json").path) } }
        let said = await Task.detached(priority: .utility) {
            records.compactMap { id, path in ClaudeSessionFile.status(path, sessionID: id).map { (id, $0) } }
        }.value
        for (id, claude) in said {
            guard var item = model.session(id), watched(item) else { continue }
            var live = item.live
            let before = item.status.title
            if item.status.state == .working {
                guard claude.status == "idle", live.claudeIdle(since: claude.since, now: now) else { continue }
                AppLog.write("\(item.id.prefix(8)) \(item.name): Claude idle since \(claude.since.formatted(.iso8601)) with no Stop, Working ends", to: "sessions.log")
                ended += 1
            } else {
                guard live.claudeAnswered(claude.status, since: claude.since) else { continue }
                AppLog.write("\(item.id.prefix(8)) \(item.name): Claude \(claude.status) since \(claude.since.formatted(.iso8601)), \(before) answered in the terminal", to: "sessions.log")
                answered += 1
            }
            item.live = live
            model.put(item)
        }
        update(model)
    }
}
