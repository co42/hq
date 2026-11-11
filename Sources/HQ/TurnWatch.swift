import Foundation
import HQKit

/// A turn that ends without a Stop (PLAN.md §6): while a session works, Claude Code's own record of it is read every
/// few seconds, and a session its Claude says is idle leaves Working.
@MainActor
enum TurnWatch {
    private static var timer: Timer?
    /// How many sessions it ended, for the self-test.
    static var ended = 0

    /// Claude Code's records: `~/.claude/sessions`, or a folder beside a test store.
    static var directory: URL {
        Store.isOverridden ? Store.directory.appending(path: "claude-sessions", directoryHint: .isDirectory)
            : URL.homeDirectory.appending(path: ".claude/sessions", directoryHint: .isDirectory)
    }

    static var running: Bool { timer != nil }

    /// Runs while a running session works, stops when none does.
    static func update(_ model: AppModel) {
        let working = model.sessions.contains { $0.isRunning && $0.pid != nil && $0.status.state == .working }
        if working, timer == nil {
            let next = Timer(timeInterval: 2, repeats: true) { [weak model] _ in
                MainActor.assumeIsolated { if let model { check(model) } }
            }
            next.tolerance = 0.5
            RunLoop.main.add(next, forMode: .common)
            timer = next
        } else if !working {
            timer?.invalidate()
            timer = nil
        }
    }

    static func check(_ model: AppModel, now: Date = .now) {
        for var item in model.sessions where item.isRunning && item.status.state == .working {
            guard let pid = item.pid,
                  let idle = ClaudeSessionFile.idleSince(directory.appending(path: "\(pid).json").path, sessionID: item.id) else { continue }
            var live = item.live
            guard live.claudeIdle(since: idle, now: now) else { continue }
            AppLog.write("\(item.id.prefix(8)) \(item.name): Claude idle since \(idle.formatted(.iso8601)) with no Stop, Working ends", to: "sessions.log")
            item.live = live
            model.put(item)
            ended += 1
        }
        update(model)
    }
}
