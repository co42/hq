import AppKit
import HQKit
import SwiftUI

/// Closed Sessions (DESIGN.md §4, T-744, T-770): the Archive's search field, then the sessions closed in the last 14 days,
/// a team's under its top session, open or closed, folded until opened.
struct ClosedSessionsModal: View {
    @Environment(AppModel.self) private var model
    /// Teams the user opened, or closed among those a search opened; a new query starts again.
    @State private var toggled: Set<String> = []

    var body: some View {
        let groups = model.closedGroups
        let shown = model.closedGroups(groups, matching: model.closedQuery)
        ModalPage {
            field(count: model.closedSessions.count, found: shown.found)
            // Open when HQ quit, gone at launch: all of them back in one click (T-505).
            let gone = model.reopenable
            if !gone.isEmpty {
                ModalGroup(title: "Open when HQ quit") {
                    ModalBox {
                        HStack(spacing: Space.sm) {
                            Text("\(gone.count) session\(gone.count == 1 ? " was" : "s were") open when HQ quit and \(gone.count == 1 ? "isn't" : "aren't") running now.")
                                .kitType(.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Dismiss") { model.dismissReopen() }
                                .help("Keep them in Closed Sessions")
                                .uiTestAnchor("reopen-dismiss")
                            Button("Reopen All") { model.reopenAll() }
                                .help("Resume each in a new Ghostty tab, in its place: a team's sessions in its leader's window")
                                .uiTestAnchor("reopen-all")
                        }
                        .padding(.horizontal, Space.md)
                        .frame(height: Metric.boxRow + Space.xs)
                    }
                }
            }
            ModalGroup(title: "Closed in the last 14 days") { list(shown.groups) }
        }
        .onChange(of: model.closedQuery) { toggled = [] }
        .preference(key: OwnsEscape.self, value: true)
    }

    /// The big search field, the keyboard in it: every word, in a session's name, tasks, role or folder.
    private func field(count: Int, found: Int) -> some View {
        @Bindable var model = model
        return HStack(spacing: Space.sm) {
            KitIcon.search.image.foregroundStyle(.secondary)
            QuickOpenField(text: $model.closedQuery, prompt: count > 0 ? "Search \(count) closed session\(count == 1 ? "" : "s")" : "Search Closed Sessions",
                           label: "Search Closed Sessions") { command in
                if command == .cancel { if model.closedQuery.isEmpty { model.closeModal() } else { model.closedQuery = "" } }
            }
            .uiTestAnchor("closed-search")
            Text(model.closedQuery.isEmpty ? "names, tasks, roles, folders" : "\(found) of \(count)")
                .kitType(.meta)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.md)
        .frame(height: Metric.archiveField)
        .surface(radius: Radius.row)
    }

    /// Each team's top session, then its closed sessions behind "12 closed sessions"; a search opens the teams it found in.
    private func list(_ groups: [ClosedGroup]) -> some View {
        ModalBox {
            ForEach(groups) { group in
                row(group.head, depth: 0)
                if !group.rows.isEmpty {
                    let open = group.searched != toggled.contains(group.id)
                    fold(group, open: open)
                    if open {
                        ForEach(group.rows, id: \.session.id) { row($0.session, depth: $0.depth) }
                    }
                }
            }
            if groups.isEmpty {
                let typed = model.closedQuery.trimmingCharacters(in: .whitespaces)
                Text(typed.isEmpty ? "None." : "No closed session has “\(typed)”").kitType(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, Space.md).frame(height: Metric.boxRow)
            }
        }
    }

    /// "12 closed sessions" under a team's top session: a click shows or hides them.
    private func fold(_ group: ClosedGroup, open: Bool) -> some View {
        let count = group.rows.count
        return Button {
            if toggled.contains(group.id) { toggled.remove(group.id) } else { toggled.insert(group.id) }
        } label: {
            HStack(spacing: Space.xs) {
                (open ? KitIcon.disclosed : KitIcon.disclosure).image.kitType(.meta)
                Text("\(count) closed session\(count == 1 ? "" : "s")")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kitType(.secondary)
        .foregroundStyle(.secondary)
        .padding(.leading, Space.md + Metric.subtaskIndent)
        .padding(.trailing, Space.md)
        .frame(height: Metric.boxRow)
        .help(open ? "Hide its closed sessions" : "Show its closed sessions")
        .accessibilityLabel("\(count) closed sessions of \(group.head.name)")
        .uiTestAnchor("closed-fold:\(group.id)")
    }

    /// A session: its face, name and role; when it closed, or its state while it runs; Resume, or Focus while it runs.
    private func row(_ session: SessionItem, depth: Int) -> some View {
        let state = session.closedAt.map { "Closed " + $0.formatted(.relative(presentation: .named)) } ?? session.stateWords
        return HStack(spacing: Space.sm) {
            SessionFace(session, size: Metric.faceRow + Space.xs)
            Button { model.open(.session(session.id), push: true) } label: {
                HStack(spacing: Space.sm) {
                    Text(session.name).lineLimit(1)
                    if let role = model.role(named: session.role) { RoleChip(role: role) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(state).kitType(.secondary).foregroundStyle(.secondary).lineLimit(1)
            if session.isRunning {
                Button("Focus") { model.open(session.id) }
                    .help("Bring its terminal forward in Ghostty")
                    .accessibilityLabel("Focus \(session.name)")
                    .uiTestAnchor("focus:\(session.id)")
            } else {
                Button("Resume") { model.open(session.id) }
                    .help("Resume it in a new Ghostty tab")
                    .accessibilityLabel("Resume \(session.name)")
                    .uiTestAnchor("resume:\(session.id)")
            }
        }
        .kitType(.title)
        .padding(.leading, Space.md + Metric.subtaskIndent * CGFloat(depth))
        .padding(.trailing, Space.md)
        .frame(height: Metric.boxRow + Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.parentSession(of: session.id).map { "\(session.name), \(state), started by \($0.name)" } ?? "\(session.name), \(state)")
        .uiTestAnchor("closed:\(session.id)")
    }
}

/// A team in Closed Sessions: its top session, open or closed, and its closed sessions under it.
struct ClosedGroup: Identifiable {
    var head: SessionItem
    /// Newest first, a sub-team stepped in under the closed session that started it.
    var rows: [(session: SessionItem, depth: Int)]
    /// A search found it in its rows: shown open, with those only.
    var searched = false

    var id: String { head.id }
}

extension AppModel {
    /// Closed Sessions as teams: each under its top session, the team that closed last first.
    var closedGroups: [ClosedGroup] {
        let closed = closedSessions
        let ids = Set(closed.map(\.id))
        let tree = sessionTree
        // When each session, or one under it, last closed.
        var newest: [String: Date] = [:]
        for item in closed {
            let at = item.closedAt ?? .distantPast
            for id in [item.id] + tree.ancestors(of: item.id) where newest[id].map({ $0 < at }) ?? true { newest[id] = at }
        }
        // An open session between two closed ones adds no row and no step.
        func walk(_ parent: String, _ depth: Int, into rows: inout [(session: SessionItem, depth: Int)]) {
            let children = tree.children(of: parent).filter { newest[$0] != nil }
            for child in children.sorted(by: { (newest[$0] ?? .distantPast) > (newest[$1] ?? .distantPast) }) {
                if ids.contains(child), let item = session(child) {
                    rows.append((item, depth))
                    walk(child, depth + 1, into: &rows)
                } else {
                    walk(child, depth, into: &rows)
                }
            }
        }
        var groups: [ClosedGroup] = []
        var placed = Set<String>()
        for item in closed {
            let top = tree.root(of: item.id)
            guard placed.insert(top).inserted, let head = session(top) else { continue }
            var rows: [(session: SessionItem, depth: Int)] = []
            walk(top, 1, into: &rows)
            groups.append(ClosedGroup(head: head, rows: rows))
        }
        return groups
    }

    /// The teams with every word of the query in a session's name, tasks' keys and titles, role or folder: found in its rows,
    /// the team shows open with those, each with the rows above it; found in its top session alone, folded as it was. And how
    /// many closed sessions matched.
    func closedGroups(_ groups: [ClosedGroup], matching query: String) -> (groups: [ClosedGroup], found: Int) {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return (groups, closedSessions.count) }
        var taskText: [String: String] = [:]
        for task in tasks where !task.sessions.isEmpty {
            for id in task.sessions { taskText[id, default: ""] += " \(task.key) \(task.title)" }
        }
        func matches(_ item: SessionItem) -> Bool {
            let text = "\(item.name) \(item.role ?? "") \(item.repo) \(item.branch) \(item.cwd)\(taskText[item.id] ?? "")".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        var found = 0
        var shown: [ClosedGroup] = []
        for group in groups {
            let rows = group.rows
            var kept = Array(repeating: false, count: rows.count)
            for index in rows.indices where matches(rows[index].session) {
                found += 1
                kept[index] = true
                var depth = rows[index].depth
                for above in rows[..<index].indices.reversed() where depth > 1 && rows[above].depth < depth {
                    kept[above] = true
                    depth = rows[above].depth
                }
            }
            let headMatches = matches(group.head)
            if headMatches, group.head.closedAt != nil { found += 1 }
            if kept.contains(true) {
                shown.append(ClosedGroup(head: group.head, rows: rows.indices.filter { kept[$0] }.map { rows[$0] }, searched: true))
            } else if headMatches {
                shown.append(group)
            }
        }
        return (shown, found)
    }
}
