import AppKit
import HQKit
import SwiftUI

/// A role's name, line or text while the Roles modal edits it in place.
struct RoleEdit: Hashable {
    enum Field: Hashable { case name, line, text }
    var role: String
    var field: Field
    /// The value when the edit began: unchanged, nothing is written.
    var base: String
    var text: String
    /// A New Role's first name: its text is edited next.
    var fresh = false
}

/// Roles (DESIGN.md §8, T-415): the list card beside the role picked, laid out like a File; stacked at 756 pt and narrower.
/// ↑ ↓ pick a role, ⌘E edits its text.
struct RolesModal: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        let sideBySide = width >= Metric.rolesSideBySide
        Group {
            if sideBySide {
                HStack(alignment: .top, spacing: Space.xxl) {
                    ScrollView { list.padding(.vertical, Space.xs) }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: Metric.rolesList)
                    ScrollView {
                        detail
                            .frame(maxWidth: Metric.pageWidth, alignment: .leading)
                            .padding(.vertical, Space.xs)
                            .padding(.bottom, Space.xl)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Space.xxl)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        list
                        detail
                    }
                    .padding(.horizontal, Space.xxl)
                    .padding(.vertical, Space.xs)
                    .padding(.bottom, Space.xl)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .focusable(model.roleEdit == nil)
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onChange(of: model.roleEdit) { _, edit in if edit == nil { focused = true } }
        .onKeyPress(.downArrow) { pick(1) }
        .onKeyPress(.upArrow) { pick(-1) }
        .preference(key: OwnsEscape.self, value: model.roleEdit != nil)
        .uiTestAnchor("roles-page")
    }

    private func pick(_ step: Int) -> KeyPress.Result {
        guard model.roleEdit == nil else { return .ignored }
        model.moveRoleSelection(by: step)
        return .handled
    }

    // MARK: The list

    private var list: some View {
        ModalBox(rows: true) {
            ForEach(model.roles) { role in
                RoleRow(role: role, selected: role.name == model.pickedRole?.name, active: focused)
            }
            Button { model.addRole() } label: {
                Label("New Role", icon: .new)
                    .frame(maxWidth: .infinity, minHeight: Metric.boxRow, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Ink.accentText)
            .kitType(.title)
            .padding(.horizontal, Space.sm)
            .clickable()
            .help("Make a new role: name it, then write what a session with it gets")
            .uiTestAnchor("roles-new")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Roles")
    }

    // MARK: The role

    @ViewBuilder
    private var detail: some View {
        if let role = model.pickedRole {
            RoleDetail(role: role)
        } else {
            ContentUnavailableView {
                Label("No Role Selected", icon: .roles)
            } description: {
                Text("Pick one, or make a New Role.")
            }
            .frame(maxWidth: .infinity, minHeight: Metric.messageEditor)
        }
    }
}

/// A role in the list: a tile in its color, its name over its line, how many open sessions have it.
private struct RoleRow: View {
    let role: RoleItem
    let selected: Bool
    let active: Bool
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let users = model.sessions(withRole: role.name).count
        // A click picks it, on the press: a row in this list does nothing more on a double-click.
        Button { model.pickRole(role.name) } label: {
            HStack(spacing: Space.md) {
                SectionTile(icon: .role, tint: role.color.base)
                VStack(alignment: .leading, spacing: 0) {
                    Text(role.name).kitType(.titleStrong).foregroundStyle(.primary).lineLimit(1)
                    Text(role.line.isEmpty ? "No line yet" : role.line)
                        .kitType(.secondary)
                        .foregroundStyle(role.line.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(users)")
                    .kitType(.meta)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.sm - 1)
                    .frame(height: Metric.chipHeight)
                    .background(Ink.chipFill, in: Capsule())
                    .help("Open sessions with this role: \(users)")
            }
            .padding(.horizontal, Space.sm)
            .frame(minHeight: Metric.roleRow)
            .rowHighlight(selected: selected, hovering: hovering, active: active)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { RoleMenu(role: role) }
        .help(role.line.isEmpty ? role.name : "\(role.name): \(role.line)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(role.name), \(users) open session\(users == 1 ? "" : "s")")
        .accessibilityValue(role.line)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.pickRole(role.name) }
        .uiTestAnchor("role:\(role.name)")
    }
}

/// A role's menu, on its row: what its header and chip do.
private struct RoleMenu: View {
    let role: RoleItem
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Rename") { model.pickRole(role.name); model.beginRoleEdit(.name) }
        RoleColorMenu(role: role)
        Divider()
        Button("Copy") { Pasteboard.copy(model.line(ofRole: role)) }
        Button("Open in Obsidian") { model.openInObsidian(role.path) }.disabled(role.path == nil)
        Divider()
        if model.isChangedDefault(role) {
            Button("Restore Default") { model.restoreDefault(role.name) }
        }
        Button("Delete") { model.deleteRole(role.name, picking: role.name == model.pickedRole?.name) }
    }
}

/// The colors to pick for a role, the current one checked, as a project's chip has them.
private struct RoleColorMenu: View {
    let role: RoleItem
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Color") {
            ForEach(LabelColor.allCases) { color in
                Toggle(isOn: Binding(get: { role.color == color }, set: { _ in model.changeRole(role.name, "Change Color") { $0.color = color } })) {
                    Label { Text(color.title) } icon: { Image(nsImage: color.swatch) }
                }
            }
        }
    }
}

/// The role picked, laid out like a File: path and byline, its chip and who has it, its name and line, then its text.
private struct RoleDetail: View {
    let role: RoleItem
    @Environment(AppModel.self) private var model
    @FocusState private var fieldFocused: Bool
    /// The editor's text height, and the rendered text's: the editor opens as tall as what it replaces (T-368).
    @State private var editorHeight: CGFloat = 0
    @State private var renderedHeight: CGFloat = 0

    var body: some View {
        let edit = model.roleEdit?.role == role.name ? model.roleEdit : nil
        let users = model.sessions(withRole: role.name)
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(byLine).kitType(.secondary).foregroundStyle(.secondary)
                FlowLayout(spacing: Space.sm) {
                    RoleChip(role: role)
                        .contextMenu { RoleColorMenu(role: role) }
                        .help("Role: \(role.name). Right-click to change its color")
                        .uiTestAnchor("role-chip")
                    Text(users.isEmpty ? "No open session has it" : "Used by")
                        .kitType(.secondary)
                        .foregroundStyle(.secondary)
                        .padding(.leading, Space.xs)
                        .frame(height: Metric.chipHeight + Space.xs)
                    ForEach(users) { session in UsedBy(session: session) }
                }
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                if edit?.field == .name { field(edit, type: .pageTitle, prompt: "Role name") } else {
                    Text(role.name)
                        .kitType(.pageTitle)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(EditOnDoubleClick { _ in model.beginRoleEdit(.name) })
                        .help("Double-click to rename")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityAction(named: "Rename") { model.beginRoleEdit(.name) }
                        .uiTestAnchor("role-name")
                }
                if edit?.field == .line { field(edit, type: .title, prompt: "What it’s for, in one line") } else {
                    Text(role.line.isEmpty ? "What it’s for, in one line. Double-click to write it." : role.line)
                        .kitType(.title)
                        .foregroundStyle(role.line.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(EditOnDoubleClick { _ in model.beginRoleEdit(.line) })
                        .help("Double-click to edit")
                        .accessibilityLabel("Line")
                        .accessibilityValue(role.line)
                        .accessibilityAction(named: "Edit") { model.beginRoleEdit(.line) }
                        .uiTestAnchor("role-line")
                }
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text("What a session with this role gets").kitType(.groupLabel).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Text("at start, on resume and after a compact").kitType(.secondary).foregroundStyle(.tertiary)
                }
                text(edit)
                limitWarning(edit?.field == .text ? edit?.text ?? role.text : role.text)
            }
            VStack(alignment: .leading, spacing: Space.md) {
                Divider()
                Text("Sessions get it after HQ’s line, which says who started them, and before their task and your first message. A change reaches a session with this role when it next starts, resumes or compacts.")
                    .kitType(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .uiTestAnchor("role-page")
    }

    /// "hq/roles/Leader.md · Ships with HQ · Edited 2 days ago".
    private var byLine: String {
        var parts = ["hq/roles/\(role.name).md"]
        if role.builtin { parts.append("Ships with HQ") }
        if role.modified > .distantPast, !role.builtin || model.isChangedDefault(role) {
            parts.append("Edited " + role.modified.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    /// The name or the line in its field: Return or leaving keeps it, Escape drops it.
    private func field(_ edit: RoleEdit?, type: KitType, prompt: String) -> some View {
        TextField(prompt, text: Binding(get: { model.roleEdit?.text ?? "" }, set: { model.roleEdit?.text = $0 }))
            .textFieldStyle(.plain)
            .kitType(type)
            .focused($fieldFocused)
            // After it shows: a New Role's page and its field appear in the same update.
            .task { fieldFocused = true }
            .onSubmit { model.finishRoleEdit() }
            .onExitCommand { if edit?.fresh == true { model.finishRoleEdit() } else { model.cancelRoleEdit() } }
            .onChange(of: fieldFocused) { if !fieldFocused, model.roleEdit == edit, edit != nil { model.finishRoleEdit() } }
            .uiTestAnchor("role-field")
    }

    /// The text rendered; a double-click or ⌘E turns it into the editor in place, Escape or ⌘Return saves.
    @ViewBuilder
    private func text(_ edit: RoleEdit?) -> some View {
        if edit?.field == .text {
            MarkdownEditor(text: Binding(get: { model.roleEdit?.text ?? "" }, set: { model.roleEdit?.text = $0 }),
                           focusOnAppear: true, caretPoint: model.editorCaret, label: "\(role.name)’s text",
                           onHeight: { editorHeight = $0 },
                           onCommit: { model.finishRoleEdit() }, onCancel: { model.finishRoleEdit() }, onEnd: {})
                .frame(height: max(editorHeight > 0 ? editorHeight : renderedHeight, MarkdownStyle.lineHeight(.body)))
                .onAppear { model.editorCaret = nil }
                .onDisappear { editorHeight = 0 }
                .uiTestAnchor("role-editor")
        } else if role.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("What a session with this role should know and do. Double-click to write it.")
                .kitType(.body)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EditOnDoubleClick { _ in model.beginRoleEdit(.text) })
                .uiTestAnchor("role-text")
        } else {
            MarkdownView(blocks: Markdown.blocks(role.text))
                .background(EditOnDoubleClick { point in
                    model.editorCaret = point
                    model.beginRoleEdit(.text)
                })
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedHeight = $0 }
                .uiTestAnchor("role-text")
        }
    }

    /// Near the editor's limit, a word says so; past it, in red: Claude Code takes so much from a hook, HQ's line included.
    @ViewBuilder
    private func limitWarning(_ text: String) -> some View {
        let count = text.utf16.count
        let limit = AppModel.roleTextLimit
        if count >= limit * 9 / 10 {
            Text(count > limit
                 ? "\(count.formatted()) of \(limit.formatted()) characters: a session may get it cut. Claude Code takes \(AppModel.hookTextLimit.formatted()) from a hook, HQ’s line included."
                 : "\(count.formatted()) of \(limit.formatted()) characters: Claude Code takes \(AppModel.hookTextLimit.formatted()) from a hook, HQ’s line included.")
                .kitType(.secondary)
                .foregroundStyle(count > limit ? AnyShapeStyle(Ink.failedText) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
                .uiTestAnchor("role-limit")
        }
    }
}

/// A session under "Used by": its face and name; a click selects it on the page.
private struct UsedBy: View {
    let session: SessionItem
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.revealSession(session.id) } label: {
            HStack(spacing: Space.xs + 1) {
                SessionFace(session, size: Metric.faceChip, badged: false)
                Text(session.name).lineLimit(1).truncationMode(.tail)
            }
            .kitType(.secondary)
            .foregroundStyle(session.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.leading, Space.xs - 1)
            .padding(.trailing, Space.sm)
            .frame(height: Metric.chipHeight + Space.xs)
            .frame(maxWidth: Metric.linkedTaskMax)
            .background(Ink.labelFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .clickable()
        .help("\(session.name): select it on the page")
        .accessibilityLabel("Used by \(session.name)")
        .uiTestAnchor("role-user:\(session.id)")
    }
}

extension AppModel {
    /// Roles, a role picked: from the Sessions header, or Edit Roles… over the form (Back returns to it).
    func openRoles(_ name: String? = nil, push: Bool = false) {
        selectedRole = role(named: name)?.name ?? pickedRole?.name ?? roles.first?.name
        open(.roles, push: push)
    }

    /// The role picked in the Roles modal.
    var pickedRole: RoleItem? { role(named: selectedRole) }

    func pickRole(_ name: String) {
        guard selectedRole != name else { return }
        saveModalEdits()
        selectedRole = name
        syncMenu()
    }

    /// ↑ ↓ in the list.
    func moveRoleSelection(by step: Int) {
        guard !roles.isEmpty else { return }
        let index = roles.firstIndex { $0.name == pickedRole?.name } ?? (step > 0 ? -1 : roles.count)
        pickRole(roles[min(max(index + step, 0), roles.count - 1)].name)
    }

    /// The picked role's name, line or text in place (a double-click, Edit, ⌘E).
    func beginRoleEdit(_ field: RoleEdit.Field, fresh: Bool = false) {
        guard let role = pickedRole else { return }
        saveModalEdits()
        let value = switch field {
        case .name: role.name
        case .line: role.line
        case .text: role.text
        }
        roleEdit = RoleEdit(role: role.name, field: field, base: value, text: value, fresh: fresh)
    }

    /// The edit kept: by Save, Return, Escape in the text, ⌘Return, or leaving it. A new name follows to the selection.
    func commitRoleEdit() {
        guard let edit = roleEdit else { return }
        roleEdit = nil
        let value = edit.field == .text ? edit.text : edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != edit.base else { return }
        switch edit.field {
        case .name:
            guard !value.isEmpty else { return }
            changeRole(edit.role, "Rename Role") { $0.name = value }
            if let renamed = role(named: value) { selectedRole = renamed.name }
        case .line: changeRole(edit.role, "Edit Role") { $0.line = value }
        case .text: changeRole(edit.role, "Edit Role") { $0.text = value }
        }
    }

    /// Return or Escape in the editor: kept, and a New Role just named goes on to its text.
    func finishRoleEdit() {
        let fresh = roleEdit.map { $0.fresh && $0.field == .name } ?? false
        commitRoleEdit()
        // Once the name's field is gone: the editor takes the keyboard it gave up.
        if fresh, pickedRole?.text.isEmpty == true { DispatchQueue.main.async { [weak self] in self?.beginRoleEdit(.text) } }
    }

    func cancelRoleEdit() { roleEdit = nil }

    /// New Role: at its place in the list, its name edited at once.
    func addRole() {
        saveModalEdits()
        let role = newRole()
        selectedRole = role.name
        // Once the click that made it is done: the list takes the keyboard on a click, and would keep it from the field.
        DispatchQueue.main.async { [weak self] in self?.beginRoleEdit(.name, fresh: true) }
    }

    /// Delete (Undo brings it back); the role after it is picked, else the one before.
    func deleteRole(_ name: String, picking: Bool) {
        guard let index = roles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        if roleEdit?.role == roles[index].name { roleEdit = nil }
        deleteRole(name)
        if picking { selectedRole = roles.indices.contains(index) ? roles[index].name : roles.last?.name }
        syncMenu()
    }

    /// "Role Leader: Leads a story…", for Copy.
    func line(ofRole role: RoleItem) -> String {
        ItemLine.line("Role", role.name, role.line)
    }

    /// A session picked from a modal: the modal closes and the page selects its card, its team open when it's inside one.
    func revealSession(_ id: SessionItem.ID) {
        guard session(id) != nil else { return }
        closeModal()
        let root = sessionTree.root(of: id)
        openTeam = root == id ? nil : root
        selectedSession = id
        selectSection(.sessions)
        scrollTarget = SectionTop.id(.sessions)
    }
}
