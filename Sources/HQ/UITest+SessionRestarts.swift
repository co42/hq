import AppKit
import HQKit
import SwiftUI

extension UITest {
    /// Restart Session (T-454): a newer Claude Code installed is said once, in Updates, with Restart Idle Sessions (N); a
    /// session restarts on a click only, at its prompt: /exit, then `claude --resume` in the same terminal, its card kept.
    static func sessionRestarts(_ model: AppModel, _ ui: Driver) async {
        let installed = AppModel.claudeInstalledInTest
        defer { AppModel.claudeInstalledInTest = installed }
        Prefs.defaults.removeObject(forKey: "claude.notified")
        func session(_ name: String, _ state: SessionState, pid: Int32, tty: String) -> String {
            let id = UUID().uuidString.lowercased()
            var item = SessionItem(id: id, customName: name, status: SessionStatus(state: state, since: .now), cwd: "/tmp", repo: "restart", branch: "main",
                                   started: .now, pid: pid, tty: tty, order: model.nextGridOrder)
            item.claudeVersion = "2.1.300"
            item.model = "opus"
            item.effort = "high"
            model.put(item)
            return id
        }
        let idle = session("Restart idle", .idle, pid: 991_101, tty: "/dev/ttys901")
        let busy = session("Restart busy", .working, pid: 991_102, tty: "/dev/ttys902")
        func menu(_ id: String) -> NSMenu? {
            guard let item = model.session(id) else { return nil }
            let menu = NSHostingMenu(rootView: SessionMenu(session: item).environment(model))
            menu.update()
            return menu
        }
        func notices() -> [Notice] { model.notices.filter { $0.source == AppModel.claudeUpdateSource } }

        AppModel.claudeInstalledInTest = "2.1.325"
        model.checkClaudeVersions()
        await ui.settle(0.2)
        await check("a newer Claude Code installed is said once, in Updates, with the count of sessions on an older one",
                    notices().count == 1 && notices().first?.level == .update && notices().first?.action == .restartIdle
                    && notices().first?.text.hasPrefix("Claude Code 2.1.325 is installed: 2 sessions run an older one") == true, notices().first?.text ?? "none")
        model.checkClaudeVersions()
        await ui.settle(0.2)
        await check("and only once for that version", notices().count == 1 && notices().first?.count == 1)
        await check("the model chip's tooltip says it", model.session(idle)?.claudeVersionLine(installed: model.installedClaude)
                    == "Claude Code 2.1.300; 2.1.325 is installed: Restart Session picks it up")
        let idleItem = menu(idle)?.items.first { $0.title == "Restart Session" }, busyItem = menu(busy)?.items.first { $0.title == "Restart Session" }
        await check("Restart Session is on at its prompt, off while it works, saying why", idleItem?.isEnabled == true && busyItem?.isEnabled == false
                    && model.session(busy).flatMap(model.restartBlocked)?.hasPrefix("At its prompt only") == true,
                    "\(String(describing: idleItem?.isEnabled)) \(String(describing: busyItem?.isEnabled))")
        await ui.until(2) { MenuState.shared.restartIdleCount == 1 }
        await check("the Session menu's Restart Idle Sessions counts the idle one only", MenuState.shared.restartIdleCount == 1)

        // From the notification's button: the idle one restarts, the working one keeps running.
        let order = model.session(idle)?.order
        model.openCenter()
        await ui.settle(0.4)
        guard let row = notices().first else { return await check("the notification", false) }
        let log = model.ghosttyLog.count
        await ui.click(await ui.steadyAnchor("restart-idle:\(row.id.uuidString)"), inSheet: true)
        await ui.until(2) { model.session(idle)?.restarting == true }
        await check("Restart Idle Sessions asks with its counts, then types /exit in the idle one's terminal only",
                    model.ghosttyLog.dropFirst(log).contains("confirm restart 1 idle, 1 busy")
                    && model.ghosttyLog.dropFirst(log).contains("restart: clear the input, then type /exit in /dev/ttys901")
                    && model.session(idle)?.stateWords == "Restarting" && model.session(busy)?.restarting == false, "\(model.ghosttyLog.dropFirst(log))")
        model.closeModal()
        await ui.settle(0.3)
        model.processExited(991_101)
        await ui.settle(0.2)
        await check("once its Claude quits, claude --resume goes in the same terminal, its model and effort kept, the card in its place",
                    model.ghosttyLog.last == "type claude --resume \(idle) --model 'opus' --effort 'high' in /dev/ttys901"
                    && model.session(idle)?.closedAt == nil && model.session(idle)?.order == order && model.gridSessions.contains { $0.id == idle },
                    model.ghosttyLog.last ?? "-")
        SelfTest.agent("hook", ["event": "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"\(idle)\",\"cwd\":\"/tmp\",\"source\":\"resume\"}"])
        await ui.settle(0.2)
        await check("its Claude back, the card is as it was", model.session(idle)?.restarting == false && model.session(idle)?.awaitingStart == nil
                    && model.session(idle)?.order == order && model.session(idle)?.isRunning == true)
        model.notices.removeAll { $0.source == AppModel.claudeUpdateSource }
        model.sessions.removeAll { [idle, busy].contains($0.id) }
        Prefs.defaults.removeObject(forKey: "claude.notified")
        await ui.settle(0.2)
    }
}
