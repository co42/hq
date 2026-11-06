import AppKit
import HQKit
import SwiftUI

/// The colors to pick for a tag or a project, the current one checked, and back to the name's own.
struct LabelColorMenu: View {
    let kind: AppModel.LabelKind
    let name: String
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let current = model.labelColor(kind, name)
        Menu("Color") {
            ForEach(LabelColor.allCases) { color in
                Toggle(isOn: Binding(get: { current == color }, set: { _ in model.setLabelColor(color, kind, name) })) {
                    Label { Text(color.title) } icon: { Image(nsImage: color.swatch) }
                }
            }
            Divider()
            Button("Automatic") { model.setLabelColor(nil, kind, name) }
        }
        if kind == .project {
            Button("Folder and GitHub…") {
                model.settingsTab = .projects
                openSettings()
            }
        }
    }
}

/// The project as a colored chip: a click picks another, a right-click recolors it.
struct ProjectPicker: View {
    let project: String?
    var empty = "None"
    /// No project: a quiet project icon, not the word.
    var iconOnly = false
    let set: (String?) -> Void
    @Environment(AppModel.self) private var model
    @State private var naming = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if naming {
            TextField("New project", text: $draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: Metric.searchWidth)
                .focused($focused)
                .onSubmit { finish() }
                .onExitCommand { naming = false }
                .onChange(of: focused) { if !focused { finish() } }
                .onAppear { focused = true }
        } else {
            Menu {
                Button("None") { set(nil) }.disabled(project == nil)
                ForEach(model.projects, id: \.self) { name in
                    Button(name) { set(name) }.disabled(name == project)
                }
                Divider()
                Button("New Project…") { draft = ""; naming = true }
            } label: {
                if let project {
                    LabelChip(text: project, color: model.labelColor(.project, project), icon: .project)
                } else if iconOnly {
                    KitIcon.project.image
                        .imageScale(.small)
                        .foregroundStyle(Ink.quieter)
                        .frame(height: Metric.chipHeight)
                } else {
                    Text(empty).kitType(.callout).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .clickable()
            .contextMenu {
                if let project { LabelColorMenu(kind: .project, name: project) }
            }
            .help(project.map { "\($0): click to change the project, right-click to change its color" } ?? "Pick a project")
            .accessibilityLabel("Project")
            .accessibilityValue(project ?? "None")
        }
    }

    private func finish() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        naming = false
        if !name.isEmpty { set(name) }
    }
}

/// A new project's name, in a popover from a row's project chip: Return sets it, Escape leaves.
struct NewProjectField: View {
    let done: (String?) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("New project", text: $name)
            .textFieldStyle(.roundedBorder)
            .frame(width: Metric.searchWidth)
            .focused($focused)
            .onSubmit {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                done(trimmed.isEmpty ? nil : trimmed)
            }
            .onExitCommand { done(nil) }
            .onAppear { focused = true }
            .padding(Space.md)
    }
}

/// Tags as colored chips: a right-click recolors or removes one; + adds one, completing from the tags in use.
struct TagList: View {
    let tags: [String]
    let set: ([String]) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        FlowLayout(spacing: Space.xs) {
            ForEach(tags, id: \.self) { tag in
                LabelChip(text: tag, color: model.labelColor(.tag, tag), icon: .tag)
                    .contextMenu {
                        LabelColorMenu(kind: .tag, name: tag)
                        Divider()
                        Button("Remove #\(tag)") { set(tags.filter { $0 != tag }) }
                    }
                    .help("Right-click to change the color or remove the tag")
                    .accessibilityAction(named: "Remove #\(tag)") { set(tags.filter { $0 != tag }) }
            }
            TagAdder(tags: tags) { set(tags + [$0]) }
        }
    }
}

/// The + after the tags, and the field it opens.
struct TagAdder: View {
    let tags: [String]
    let add: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if adding {
            TextField("Tag", text: $draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: Metric.tagField)
                .focused($focused)
                .textInputSuggestions {
                    ForEach(suggestions, id: \.self) { tag in
                        Text("#\(tag)").textInputCompletion(tag)
                    }
                }
                .onSubmit { commit(again: true) }
                .onExitCommand { draft = ""; adding = false }
                .onChange(of: focused) { if !focused { commit(again: false) } }
                .onAppear { focused = true }
                .uiTestAnchor("tag-adder-field")
        } else {
            Button { adding = true } label: {
                KitIcon.new.image
                    .imageScale(.small)
                    .frame(width: Metric.chipHeight, height: Metric.chipHeight)
                    .background(Ink.chipFill, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .clickable()
            .help("Add a tag")
            .accessibilityLabel("Add a tag")
            .uiTestAnchor("tag-adder")
        }
    }

    private var suggestions: [String] {
        let typed = draft.replacingOccurrences(of: "#", with: "").lowercased()
        return model.allTags.filter { !tags.contains($0) && (typed.isEmpty || $0.lowercased().hasPrefix(typed)) }.prefix(8).map { $0 }
    }

    /// Return adds and keeps the field for the next tag; leaving adds what's typed and closes it.
    private func commit(again: Bool) {
        let tag = draft.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        draft = ""
        if !tag.isEmpty, !tags.contains(tag) { add(tag) }
        if !again || tag.isEmpty { adding = false }
    }
}

/// A file's or an artifact's project, tags and pin, on one line.
struct ItemLabels: View {
    let project: String?
    let tags: [String]
    let pinned: Bool
    let setProject: (String?) -> Void
    let setTags: ([String]) -> Void
    let setPinned: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            Button { setPinned(!pinned) } label: {
                Label(pinned ? "Pinned" : "Pin", icon: pinned ? .pinned : .pin)
            }
            .buttonStyle(.borderless)
            .clickable()
            .help(pinned ? "Unpin it" : "Pin it to the top of Files and Artifacts")
            ProjectPicker(project: project, empty: "No project", set: setProject)
            TagList(tags: tags, set: setTags)
        }
        .kitType(.callout)
    }
}

extension AppModel {
    func setFileLabels(_ id: FileItem.ID, project: String?? = nil, tags: [String]? = nil, pinned: Bool? = nil) {
        changeFile(id, pinned != nil ? (pinned! ? "Pin" : "Unpin") : tags != nil ? "Change Tags" : "Set Project") { file in
            if let project { file.project = project.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
            if let tags { file.tags = Self.cleanTags(tags) }
            if let pinned { file.pinned = pinned }
        }
    }

    func setArtifactLabels(_ id: URL, project: String?? = nil, tags: [String]? = nil, pinned: Bool? = nil) {
        guard let index = artifacts.firstIndex(where: { $0.id == id }) else { return }
        let old = artifacts[index]
        var new = old
        if let project { new.project = project.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        if let tags { new.tags = Self.cleanTags(tags) }
        if let pinned { new.pinned = pinned }
        guard new != old else { return }
        artifacts[index] = new
        registerUndo(pinned != nil ? (pinned! ? "Pin" : "Unpin") : tags != nil ? "Change Tags" : "Set Project") { model in
            if let index = model.artifacts.firstIndex(where: { $0.id == id }) { model.artifacts[index] = old }
        }
    }

    /// Tags without `#`, blanks or repeats.
    static func cleanTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Link to Task…: the tasks whose title or number has what the user types, open ones first; ↑ ↓ move, Return or a click links.
struct TaskFinder: View {
    let pick: (Int) -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let found = Self.matches(model, query: query)
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Find a task by title or number", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: query) { index = 0 }
                .onKeyPress(.downArrow) { index = min(index + 1, max(found.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .onSubmit { if found.indices.contains(index) { pick(found[index].id) } }
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(found.enumerated()), id: \.element.id) { position, task in
                            Button { pick(task.id) } label: {
                                HStack(spacing: Space.sm) {
                                    TaskGlyph(status: task.status)
                                    Text(task.key).kitType(.key).foregroundStyle(.secondary)
                                    Text(task.title).kitType(.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, Space.sm)
                                .frame(height: Metric.boxRow)
                                .background(position == index ? Ink.rowSelection : Color.clear,
                                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .clickable()
                            .accessibilityAddTraits(position == index ? .isSelected : [])
                            .id(task.id)
                        }
                        if found.isEmpty {
                            Text("No task matches “\(query)”.").kitType(.callout).foregroundStyle(.secondary).padding(Space.sm)
                        }
                    }
                }
                .onChange(of: index) {
                    guard found.indices.contains(index) else { return }
                    scroller.scrollTo(found[index].id)
                    AccessibilityNotification.Announcement("\(found[index].key) \(found[index].title)").post()
                }
            }
            .frame(height: Metric.linkPicker)
        }
        .padding(Space.md)
        .frame(width: Metric.sheetWidth)
        .onAppear { focused = true }
    }

    /// Open tasks before done ones, newest first; a number finds its task by key.
    static func matches(_ model: AppModel, query: String) -> [TaskItem] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let number = Int(text.uppercased().replacingOccurrences(of: "T-", with: ""))
        let hits = model.tasks.filter { task in
            text.isEmpty || task.id == number || "\(task.key) \(task.title)".localizedStandardContains(text)
        }
        return hits.sorted { ($0.id == number ? 0 : 1, $0.status == .done ? 1 : 0, -$0.id) < ($1.id == number ? 0 : 1, $1.status == .done ? 1 : 0, -$1.id) }
            .prefix(Self.shown).map { $0 }
    }

    static let shown = 40
}
