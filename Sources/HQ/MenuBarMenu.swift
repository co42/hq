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
        Button("New Task…") {
            model.bringForward()
            model.beginTask(.overview)
        }
        Button("New Reminder…") {
            model.bringForward()
            model.beginReminder()
        }
        Divider()
        let sessions = model.menuBarSessions
        Menu("Focus") {
            ForEach(sessions) { session in
                Button { model.open(session.id) } label: {
                    Label { Text(Self.title(session)) } icon: { Image(nsImage: FaceArt.image(session.face, size: Metric.faceMenu)) }
                }
            }
        }
        .disabled(sessions.isEmpty)
        Divider()
        Button("Restart HQ") { model.restart() }
        Button("Quit HQ") { NSApp.terminate(nil) }
    }

    /// "registry: retry budget · Idle", the name cut at 30 characters so the menu stays narrow.
    static func title(_ session: SessionItem) -> String {
        let name = session.name.count > nameLimit ? session.name.prefix(nameLimit - 1).trimmingCharacters(in: .whitespaces) + "…" : session.name
        return "\(name) · \(session.stateWords)"
    }

    static let nameLimit = 30
}

extension AppModel {
    /// The running sessions, those that wait on the user first, then as on the grid.
    var menuBarSessions: [SessionItem] {
        let running = gridSessions.filter(\.isRunning)
        return running.filter(\.status.needsYou) + running.filter { !$0.status.needsYou }
    }

    /// Restart HQ (T-336): it quits, and a small shell opens it again once this process is gone (giving up after a minute,
    /// should the quit be cancelled). Test runs only count it.
    /// Before HQ quits: the editors' text by their rule, the open sheet closed (it would refuse to quit), and the
    /// notifications, seen marks and sessions changed in the last second.
    func saveForQuit() {
        window?.makeFirstResponder(nil)
        editingDescription = nil
        closeModal()
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        saveNoticesNow()
        saveAttentionNow()
        saveSessionsNow()
    }

    func restart() {
        guard !Store.isOverridden else { return restarts += 1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "for i in $(seq 300); do kill -0 \"$1\" 2>/dev/null || break; sleep 0.2; done; kill -0 \"$1\" 2>/dev/null || open \"$0\"",
                             Bundle.main.bundlePath, "\(ProcessInfo.processInfo.processIdentifier)"]
        do { try process.run() } catch { return }
        NSApp.terminate(nil)
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
