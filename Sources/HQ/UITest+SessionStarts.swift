import AppKit
import HQKit
import SwiftUI

extension UITest {
    /// A session HQ opened a tab for whose Claude doesn't report (T-507): Didn't start, drawn like Failed, with Start Again
    /// and Close; Not reporting when Claude runs on its terminal without HQ's hooks. A hook clears either.
    static func sessionStarts(_ model: AppModel, _ ui: Driver) async {
        let deadline = AppModel.startDeadline
        AppModel.startDeadline = 0.3
        defer { AppModel.startDeadline = deadline }
        func menu(_ id: String) -> [String] {
            guard let session = model.session(id) else { return [] }
            let menu = NSHostingMenu(rootView: SessionMenu(session: session).environment(model))
            menu.update()
            return menu.items.map(\.title)
        }
        func notice(_ id: String) -> Notice? { model.notices.last { $0.source == id } }

        // Started from HQ by the user: Needs You.
        AppModel.claudeRunsInTest = false
        let tabs = { model.ghosttyLog.filter { $0.hasPrefix("new tab in /tmp: claude --session-id") }.count }
        let log = tabs()
        let id = model.startSession(named: "Never starts", in: "/tmp")
        await ui.until(3) { model.session(id)?.startTrouble != nil }
        await check("a session whose Claude never reports turns to Didn't start, drawn like Failed",
                    model.session(id)?.startTrouble == .didntStart && model.session(id)?.stateWords == "Didn't start", "\(String(describing: model.session(id)?.startTrouble))")
        await check("its menu has Start Again and Close Session", ["Start Again", "Close Session"].allSatisfy(menu(id).contains), menu(id).joined(separator: ", "))
        await check("the user started it: Needs You says it didn't start", notice(id)?.level == .important && notice(id)?.text.contains("didn't start") == true,
                    notice(id)?.text ?? "none")
        await check("hq says so", (model.session(id)?.agentJSON(model)["state"] as? String) == "Didn't start")
        model.selectedSession = id
        func barMenu() -> [String] {
            guard let menu = NSApp.mainMenu?.item(withTitle: "Session")?.submenu else { return [] }
            menu.update()
            return menu.items.map(\.title)
        }
        func barItem(_ title: String) -> NSMenuItem? {
            guard let menu = NSApp.mainMenu?.item(withTitle: "Session")?.submenu else { return nil }
            menu.update()
            return menu.items.first { $0.title == title }
        }
        // A background copy's menu bar items are all off: the state they read is judged.
        await ui.until(2) { MenuState.shared.sessionCanStartAgain }
        await check("the menu bar's Session menu has Start Again, on for it, and Close Session", barItem("Start Again") != nil && MenuState.shared.sessionCanStartAgain
                    && MenuState.shared.sessionClosable, barMenu().joined(separator: ", "))
        model.selectedSession = nil
        let before = Set(model.sessions.map(\.id))
        if let session = model.session(id) {
            let made = NSHostingMenu(rootView: SessionMenu(session: session).environment(model))
            made.update()
            if let index = made.items.firstIndex(where: { $0.title == "Start Again" }) { made.performActionForItem(at: index) }
        }
        await ui.settle(0.2)
        let again = Set(model.sessions.map(\.id)).subtracting(before).first
        await check("Start Again opens a fresh tab with the same name and drops the card that didn't start",
                    model.session(id) == nil && again.flatMap { model.session($0)?.name } == "Never starts" && tabs() == log + 2,
                    "\(model.ghosttyLog.suffix(3))")
        if let again {
            await ui.until(3) { model.session(again)?.startTrouble != nil }
            model.closeSession(again)
            await ui.settle(0.2)
            await check("Close Session removes a card that didn't start", model.session(again) == nil)
        }

        // Started by a session, Claude running without HQ's hooks: Not reporting, in Updates; a hook clears it.
        AppModel.claudeRunsInTest = true
        let quiet = model.startSession(named: "Runs quietly", in: "/tmp", behind: true)
        await ui.until(3) { model.session(quiet)?.startTrouble != nil }
        await check("a session whose Claude runs without reporting shows Not reporting", model.session(quiet)?.startTrouble == .notReporting
                    && model.session(quiet)?.stateWords == "Not reporting", "\(String(describing: model.session(quiet)?.startTrouble))")
        await check("its menu has Close Session and no Start Again", menu(quiet).contains("Close Session") && !menu(quiet).contains("Start Again"),
                    menu(quiet).joined(separator: ", "))
        await check("a session started it: the notice is an update", notice(quiet)?.level == .update && notice(quiet)?.text.contains("doesn't report") == true,
                    notice(quiet)?.text ?? "none")
        SelfTest.agent("hook", ["event": "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"\(quiet)\",\"cwd\":\"/tmp\",\"source\":\"startup\"}"])
        await ui.settle(0.2)
        await check("a hook from it clears what HQ judged", model.session(quiet)?.startTrouble == nil && model.session(quiet)?.awaitingStart == nil)
        AppModel.claudeRunsInTest = false
        for id in [quiet] { model.closeSession(id) }
        await ui.settle(0.2)
    }
}
