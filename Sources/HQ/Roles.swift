import Foundation
import HQKit

/// Roles (T-376): notes in <vault>/hq/roles/, read at each vault scan. Each change writes its note. Leader and Worker ship
/// with HQ: each is written once, when its note is missing.
extension AppModel {
    /// What Claude Code adds from a hook whole: past it, Claude gets a file path and a 2,000-character preview (2026-11-11).
    static let hookTextLimit = 10_000
    /// A role's text that reaches its session whole, beside HQ's own lines; the role editor warns near it.
    static let roleTextLimit = 8_000

    /// A new role, its name unique: "New Role", "New Role 2"…
    @discardableResult
    func newRole(named name: String = "New Role", color: LabelColor? = nil, line: String = "", text: String = "") -> RoleItem {
        let base = RoleItem.clean(name).isEmpty ? "New Role" : RoleItem.clean(name)
        var unique = base
        var count = 1
        while role(named: unique) != nil || vault?.hasRoleNote(unique) == true {
            count += 1
            unique = "\(base) \(count)"
        }
        var role = RoleItem(name: unique, color: color ?? LabelColor.automatic(unique), line: line, text: text,
                            builtin: RoleItem.isShipped(unique), modified: .now)
        if let vault {
            do {
                role = try vault.create(role)
            } catch {
                report { throw error }
                return role
            }
            wrote(role.path)
        }
        roles.append(role)
        sortRoles()
        registerUndo("New Role") { $0.deleteRole(unique) }
        return role
    }

    /// An edit to a role: its name, color, line or text. A new name renames its note and follows to the sessions that have it.
    func changeRole(_ name: String, _ actionName: String = "Edit Role", _ change: (inout RoleItem) -> Void) {
        guard let index = roles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        let old = roles[index]
        var role = old
        change(&role)
        role.name = RoleItem.clean(role.name)
        role.path = old.path
        let renamed = role.name != old.name
        let sameName = role.name.caseInsensitiveCompare(old.name) == .orderedSame
        guard role != old, !role.name.isEmpty, sameName || (self.role(named: role.name) == nil && vault?.hasRoleNote(role.name) != true) else { return }
        role.modified = .now
        role.builtin = RoleItem.isShipped(role.name)
        if let vault, let path = old.path {
            do {
                if renamed {
                    role = try vault.rename(role, from: path)
                } else {
                    try vault.save(role)
                }
            } catch {
                report { throw error }
                return
            }
            wrote(path)
            wrote(role.path)
        }
        roles[index] = role
        if renamed { renameRole(from: old.name, to: role.name) }
        sortRoles()
        let now = role.name
        registerUndo(actionName) { model in model.changeRole(now, actionName) { $0 = old } }
    }

    /// Delete: the note goes to the Trash, with Undo. Sessions that had it keep the text they started with, not the chip.
    func deleteRole(_ name: String) {
        guard let role = role(named: name) else { return }
        let trashed = trash(role.path)
        roles.removeAll { $0.name == role.name }
        registerUndo("Delete Role") { model in
            model.untrash(trashed, to: role.path)
            if model.role(named: role.name) == nil {
                model.roles.append(role)
                model.sortRoles()
            }
            model.registerUndo("Delete Role") { $0.deleteRole(role.name) }
        }
    }

    /// Restore Default: a role that ships with HQ gets its text, line and color back.
    func restoreDefault(_ name: String) {
        guard let shipped = RoleItem.defaults.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        changeRole(name, "Restore Default") { role in
            role.line = shipped.line
            role.text = shipped.text
            role.color = shipped.color
        }
    }

    /// Whether a role that ships with HQ was changed since: Restore Default shows.
    func isChangedDefault(_ role: RoleItem) -> Bool {
        RoleItem.defaults.first { $0.name.caseInsensitiveCompare(role.name) == .orderedSame }
            .map { $0.text != role.text || $0.line != role.line || $0.color != role.color } ?? false
    }

    /// The open sessions that have a role, in the grid's order.
    func sessions(withRole name: String) -> [SessionItem] {
        gridSessions.filter { $0.role?.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Leader and Worker, each written once to the vault when its note is missing: one the user deleted stays deleted.
    func writeShippedRoles() {
        guard let vault else { return }
        let key = "roles.shipped"
        let before = Set(Prefs.defaults.stringArray(forKey: key) ?? [])
        var written = before
        for shipped in RoleItem.defaults {
            let path = vault.rolesDirectory.appending(path: "\(shipped.name).md").path
            guard written.insert(path).inserted, role(named: shipped.name) == nil, !vault.hasRoleNote(shipped.name) else { continue }
            do {
                var role = try vault.create(shipped)
                role.modified = role.path.map { Vault.modified(URL(fileURLWithPath: $0)) } ?? .now
                wrote(role.path)
                roles.append(role)
            } catch {
                report { throw error }
            }
        }
        guard written != before else { return }
        Prefs.defaults.set(written.sorted(), forKey: key)
        sortRoles()
    }

    private func renameRole(from old: String, to new: String) {
        for var session in sessions where session.role?.caseInsensitiveCompare(old) == .orderedSame {
            session.role = new
            put(session)
        }
    }

    /// Leader and Worker first, then by name.
    func sortRoles() {
        let shipped = RoleItem.defaults.map(\.name)
        let sorted = roles.sorted { a, b in
            let x = shipped.firstIndex(of: a.name) ?? shipped.count, y = shipped.firstIndex(of: b.name) ?? shipped.count
            return (x, a.name.lowercased()) < (y, b.name.lowercased())
        }
        if sorted != roles { roles = sorted }
    }
}

nonisolated extension RoleItem {
    /// The roles that ship with HQ.
    static let defaults: [RoleItem] = [
        RoleItem(name: "Leader", color: .indigo, line: "Follows a story and keeps it moving. Never writes the code.", text: leaderText, builtin: true),
        RoleItem(name: "Worker", color: .brown, line: "Works on one task and reports to its leader.", text: workerText, builtin: true),
    ]

    static func isShipped(_ name: String) -> Bool {
        defaults.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// A name a note can have: trimmed, no slash, colon or leading dot.
    static func clean(_ name: String) -> String {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
        while clean.hasPrefix(".") { clean.removeFirst() }
        return clean.trimmingCharacters(in: .whitespaces)
    }

    static let leaderText = """
        You lead a story: the task you were given and all its subtasks. Workers do the work; you keep it moving. You don't write code yourself.

        - Know the whole story: `hq task show T-n --deep`, its files, its pull requests and the Slack threads linked to it.
        - Split the work into subtasks, each with what done means. Start a Worker on each piece that can move now: `hq session new "T-n Title" --task T-n --role Worker`.
        - Your Workers report to you; `hq ctx` lists them with their state. Check what they say against the task: its Done when, the PR, its checks.
        - Keep every task true: its status, its Status section, and Blocked when it waits: `hq task block T-n "why"` on a person or a decision, `hq task link T-n --blocked-by T-m` on another task.
        - Answer your Workers from what you know. What only the user can decide goes to them in one `hq notify`, each question with your recommendation.
        """

    static let workerText = """
        You work on one task for your leader, the session that started you (`hq ctx` names it).

        - Tell your leader each time you move your task forward or change a task: what changed, what's next. Send it a message; don't wait to be asked.
        - Ask your leader first when you need a decision. It asks the user when it can't answer.
        - Keep your task current as the hq skill says. When it's done, tell your leader and stop there.
        """
}
