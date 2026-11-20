import Foundation
import HQKit

/// What a session's files say, read off the main thread (T-683): its repository and branch, and its transcript's titles,
/// last reply and interrupt.
nonisolated struct SessionFiles: Sendable {
    var repo: String?
    var branch: String?
    var origin: String?
    var titles: TranscriptTitle.Titles?
    var usage: ClaudeModel.Usage?
    var interrupt: Date?

    static func read(git cwd: String?, transcript path: String?, interrupt: Bool) -> SessionFiles {
        var found = SessionFiles()
        if let cwd {
            (found.repo, found.branch) = GitInfo.describe(cwd)
            found.origin = GitInfo.origin(cwd)
        }
        if let path {
            found.titles = TranscriptTitle.read(path)
            found.usage = ClaudeModel.usage(path)
            if interrupt { found.interrupt = TranscriptInterrupt.read(path) }
        }
        return found
    }
}

extension AppModel {
    /// Reads a session's files in the background, then puts what changed on it. `git`: its folder's repository;
    /// `transcript`: its titles and last reply, and with `interrupt`, an Esc that no Stop reported.
    func readSessionFiles(_ id: String, git cwd: String? = nil, transcript path: String? = nil, interrupt: Bool = false) {
        guard cwd != nil || path != nil else { return }
        sessionReads += 1
        Task {
            let found = await Task.detached(priority: .userInitiated) { SessionFiles.read(git: cwd, transcript: path, interrupt: interrupt) }.value
            sessionReads -= 1
            guard var item = session(id) else { return }
            var changed = false
            if let repo = found.repo, let branch = found.branch, (item.repo, item.branch, item.origin) != (repo, branch, found.origin) {
                (item.repo, item.branch, item.origin) = (repo, branch, found.origin)
                changed = true
            }
            if let titles = found.titles { changed = Self.applyTitles(titles, to: &item) || changed }
            changed = Self.applyUsage(found.usage, to: &item) || changed
            if let stopped = found.interrupt {
                var live = item.live
                if live.interrupt(at: stopped, now: .now) {
                    item.live = live
                    changed = true
                }
            }
            if changed { put(item) }
        }
    }
}
