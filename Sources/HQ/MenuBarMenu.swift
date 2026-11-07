import AppKit
import HQKit
import SwiftUI

/// The menu bar icon's menu (DESIGN.md §3, T-325): HQ from any app, what needs the user, a new task or reminder, and a
/// session's terminal. The Dock menu's items say the same and do the same.
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Open HQ") { model.bringForward() }
        Button(model.importantCount > 0 ? "Notifications · \(model.importantCount) need you" : "Notifications") {
            model.bringForward()
            model.openCenter()
        }
        Divider()
        Button("New Task") {
            model.bringForward()
            model.focusQuickAdd(.overview)
        }
        Button("New Reminder…") {
            model.bringForward()
            model.beginReminder()
        }
        Divider()
        let sessions = model.menuBarSessions
        Menu("Focus") {
            ForEach(sessions) { session in
                Button("\(session.name) · \(session.stateWords)") { model.open(session.id) }
            }
        }
        .disabled(sessions.isEmpty)
        Divider()
        Button("Quit HQ") { NSApp.terminate(nil) }
    }
}

extension AppModel {
    /// The running sessions, those that wait on the user first, then as on the grid.
    var menuBarSessions: [SessionItem] {
        let running = gridSessions.filter(\.isRunning)
        return running.filter(\.status.needsYou) + running.filter { !$0.status.needsYou }
    }

    /// HQ's window in front from any app, even after ⌘W hid it (T-318). Activation alone may be refused while another
    /// app is in front; ordering the window front regardless brings it anyway.
    func bringForward() {
        NSApp.activate()
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
