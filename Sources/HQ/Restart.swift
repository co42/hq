import AppKit
import HQKit

/// Restart Session (T-454): a session picks up a newly installed Claude Code. Its input emptied and /exit typed, as Close
/// Session does; once its Claude has quit, `claude --resume` in the same terminal, its model and effort kept: the tab, the
/// card's place, its team and its conversation stay. Only on the user's click: nothing restarts on its own.
extension AppModel {
    /// A test copy's installed Claude Code.
    static var claudeInstalledInTest: String?
    /// The source of the notification that says a newer Claude Code is installed.
    static let claudeUpdateSource = "claude-code"

    /// Off the main thread: the installed Claude Code and the one each running session runs. Says once per version when
    /// sessions run an older one.
    func checkClaudeVersions() {
        claudeCheckedAt = .now
        if Store.isOverridden { return applyClaudeVersions(installed: Self.claudeInstalledInTest, running: [:]) }
        let pids = sessions.filter(\.isRunning).compactMap { item in item.pid.map { (item.id, $0) } }
        Task {
            let (installed, running) = await Task.detached { () -> (String?, [String: String]) in
                (ClaudeVersion.installed(),
                 Dictionary(pids.compactMap { id, pid in ClaudeVersion.running(pid).map { (id, $0) } }, uniquingKeysWith: { first, _ in first }))
            }.value
            applyClaudeVersions(installed: installed, running: running)
        }
    }

    func applyClaudeVersions(installed: String?, running: [String: String]) {
        if installedClaude != installed { installedClaude = installed }
        for (id, version) in running {
            guard var item = session(id), item.claudeVersion != version else { continue }
            item.claudeVersion = version
            put(item)
        }
        let older = outdatedSessions
        guard let installed, !older.isEmpty, Prefs.defaults.string(forKey: "claude.notified") != installed else { return }
        Prefs.defaults.set(installed, forKey: "claude.notified")
        let runs = older.count == 1 ? "1 session runs" : "\(older.count) sessions run"
        notify("Claude Code \(installed) is installed: \(runs) an older one. Restart Session on its card picks it up.", level: .update,
               source: Self.claudeUpdateSource, action: .restartIdle)
    }

    /// Running sessions on an older Claude Code than the installed one.
    var outdatedSessions: [SessionItem] {
        guard let installedClaude else { return [] }
        return gridSessions.filter { $0.isRunning && !$0.restarting && $0.claudeVersion.map { ClaudeVersion.isOlder($0, than: installedClaude) } == true }
    }

    /// The outdated ones at their prompt: Restart Idle Sessions restarts these.
    var restartableIdle: [SessionItem] { outdatedSessions.filter(canChangeRun) }

    /// Why an action at its prompt only (Restart Session, Clear Conversation) is off, or nil when it's on.
    func promptBlocked(_ item: SessionItem) -> String? {
        if canChangeRun(item) { return nil }
        if !item.isRunning { return "It isn't running: Resume starts it again" }
        if item.tty == nil || !item.inGhostty || backgroundHandles[item.id] != nil { return "It doesn't run in a Ghostty terminal HQ can type into" }
        return "At its prompt only: it's \(item.stateWords.lowercased()) now"
    }

    func restartSession(_ id: String) {
        guard var item = session(id), canChangeRun(item), let pid = item.pid, let tty = item.tty else { return }
        sessionRestarts[pid] = (id, tty)
        item.restarting = true
        put(item)
        AppLog.write("\(id.prefix(8)) \(item.name): restarting on \(tty), Claude Code \(item.claudeVersion ?? "?") to \(installedClaude ?? "?")", to: "sessions.log")
        // A /exit that didn't take: the session runs on as it was.
        Task { [weak self] in
            try? await Task.sleep(for: Self.exitWait)
            guard let self, self.sessionRestarts[pid]?.id == id else { return }
            self.sessionRestarts[pid] = nil
            if var back = self.session(id) { back.restarting = false; self.put(back) }
        }
        if Store.isOverridden { return ghosttyLog.append("restart: clear the input, then type /exit in \(tty)") }
        Task {
            let typed = await Task.detached { () -> Result<Bool, Ghostty.Failure> in
                do throws(Ghostty.Failure) { return .success(try Ghostty.type("/exit", tty: tty, clearing: true)) } catch { return .failure(error) }
            }.value
            ghostty { if case .failure(let failure) = typed { throw failure } }
        }
    }

    /// Clear Conversation (T-757): /clear typed at its prompt, its input emptied first. The /clear hooks keep its card.
    func clearConversation(_ id: String) {
        guard let item = session(id), canChangeRun(item), let tty = item.tty else { return }
        AppLog.write("\(id.prefix(8)) \(item.name): clearing its conversation on \(tty)", to: "sessions.log")
        if Store.isOverridden { return ghosttyLog.append("clear the input, then type /clear in \(tty)") }
        Task {
            let typed = await Task.detached { () -> Result<Bool, Ghostty.Failure> in
                do throws(Ghostty.Failure) { return .success(try Ghostty.type("/clear", tty: tty, clearing: true)) } catch { return .failure(error) }
            }.value
            ghostty { if case .failure(let failure) = typed { throw failure } }
        }
    }

    /// Its Claude quit for a restart: `claude --resume` in the same terminal once its shell is back.
    func resumeAfterRestart(_ id: String, tty: String) {
        guard let item = session(id) else { return }
        let command = item.restartCommand
        if Store.isOverridden {
            ghosttyLog.append("type \(command) in \(tty)")
            return awaitStart(id, tty: tty)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            let typed = await Task.detached { () -> Result<Bool, Ghostty.Failure> in
                do throws(Ghostty.Failure) { return .success(try Ghostty.type(command, tty: tty)) } catch { return .failure(error) }
            }.value
            ghostty { if case .failure(let failure) = typed { throw failure } }
            awaitStart(id, tty: tty)
        }
    }

    /// Restart Idle Sessions (N): asks with the counts, then restarts each outdated session at its prompt.
    func restartIdleSessions() {
        let idle = restartableIdle
        guard !idle.isEmpty, let installedClaude else { return }
        let busy = outdatedSessions.count - idle.count
        let restart = { [weak self] in for item in idle { self?.restartSession(item.id) } }
        if Store.isOverridden {
            ghosttyLog.append("confirm restart \(idle.count) idle, \(busy) busy")
            return restart()
        }
        let alert = NSAlert()
        alert.messageText = "Restart \(idle.count) idle session\(idle.count == 1 ? "" : "s") on Claude Code \(installedClaude)?"
        alert.informativeText = "Each quits and resumes in its own tab, its conversation kept; text left unsent in its input is cleared."
            + (busy == 0 ? "" : " The \(busy) working or waiting one\(busy == 1 ? " keeps" : "s keep") running until you restart \(busy == 1 ? "it" : "them").")
        alert.addButton(withTitle: "Restart \(idle.count) Session\(idle.count == 1 ? "" : "s")")
        alert.addButton(withTitle: "Cancel")
        let finish = { (response: NSApplication.ModalResponse) in if response == .alertFirstButtonReturn { restart() } }
        if let window = window.map({ $0.attachedSheet ?? $0 }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}

extension SessionItem {
    /// "Claude Code 2.1.320", and when a newer one is installed, that Restart Session picks it up (its model chip's tooltip).
    func claudeVersionLine(installed: String?) -> String? {
        guard let claudeVersion else { return nil }
        guard let installed, ClaudeVersion.isOlder(claudeVersion, than: installed) else { return "Claude Code \(claudeVersion)" }
        return "Claude Code \(claudeVersion); \(installed) is installed: Restart Session picks it up"
    }

    /// `claude --resume`, with the model and effort it ran on.
    var restartCommand: String {
        var command = resumeCommand
        if let model { command += " --model \(AppModel.shellQuoted(model))" }
        if let effort { command += " --effort \(AppModel.shellQuoted(effort))" }
        return command
    }
}
