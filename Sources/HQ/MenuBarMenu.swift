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
        let rows = model.menuBarRows
        Menu("Focus") {
            ForEach(rows, id: \.session.id) { row in
                Button { model.open(row.session.id) } label: {
                    Label { Text(Self.title(row.session)) } icon: { Image(nsImage: Self.face(row.session, depth: row.depth)) }
                }
                // A closed session that heads a running team shows where its sessions sit; it isn't one to focus.
                .disabled(!row.session.isRunning)
            }
        }
        .disabled(rows.isEmpty)
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

    /// A session's face for a menu, stepped in by its depth in a team: the item's title steps in with it.
    static func face(_ session: SessionItem, depth: Int) -> NSImage {
        let face = FaceArt.image(session.face, size: Metric.faceMenu, ended: !session.isRunning)
        guard depth > 0 else { return face }
        let indent = Metric.menuIndent * CGFloat(depth)
        let image = NSImage(size: NSSize(width: indent + Metric.faceMenu, height: Metric.faceMenu), flipped: false) { _ in
            face.draw(in: NSRect(x: indent, y: 0, width: Metric.faceMenu, height: Metric.faceMenu))
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension AppModel {
    /// The running sessions as the grid has them, each team's under its top card and stepped in; the teams with a session
    /// that waits on the user first. A closed top card stays while its team runs, to say whose sessions they are.
    var menuBarRows: [(session: SessionItem, depth: Int)] {
        let tree = sessionTree
        let teams = tree.roots.compactMap { session($0) }.map { root in
            ([(session: root, depth: 0)] + team(of: root.id, in: tree)).filter { $0.session.isRunning || $0.depth == 0 }
        }
        .filter { $0.contains { $0.session.isRunning } }
        let waits = { (team: [(session: SessionItem, depth: Int)]) in team.contains { $0.session.isRunning && $0.session.status.needsYou } }
        return (teams.filter(waits) + teams.filter { !waits($0) }).flatMap { $0 }
    }

    /// The running sessions in Focus ▸'s order.
    var menuBarSessions: [SessionItem] { menuBarRows.map(\.session).filter(\.isRunning) }

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

    /// HQ's window in front from any app, even after ⌘W hid it (T-318) or on another Space (T-380): an activation the app
    /// in front can't refuse, which takes the user to the window's Space as macOS's own apps do. Test runs stay behind.
    func bringForward() {
        if Store.background {
            NSApp.activate()
            Self.forwardCalls.append("activate")
        } else {
            NSApp.activate(ignoringOtherApps: true)
            Self.forwardCalls.append("activate ignoring other apps")
        }
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak window] in
            guard let window else { return }
            AppLog.write("bring forward: active \(NSApp.isActive), key \(window.isKeyWindow), on this Space \(window.isOnActiveSpace)", to: "window.log")
        }
    }

    /// The activations bringForward asked for, for the self-test.
    static var forwardCalls: [String] = []
}
