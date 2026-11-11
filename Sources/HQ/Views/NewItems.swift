import AppKit
import HQKit
import SwiftUI

// New Task…, New Reminder…, New File… and Import Artifact…: small sheets laid out as Start a Session (DESIGN.md §6, §7,
// §11), labels on the left, the keyboard in the first field. What a task or a reminder links is a Links row: a Slack link
// on the clipboard comes on its own, Link… finds anything else.

/// A sheet's label, on the left of its field.
struct FormLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).kitType(.callout).foregroundStyle(.secondary).fixedSize()
    }
}

/// A sheet's buttons: Cancel (Escape) goes back to what was under it; the prominent one adds (⌘Return).
struct FormButtons: View {
    let title: String
    let ready: Bool
    let anchor: String
    let add: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel") { model.back() }
                .keyboardShortcut(.cancelAction)
                .clickable()
                .uiTestAnchor("\(anchor)-cancel")
            Button(title, action: add)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .clickable()
                .disabled(!ready)
                .uiTestAnchor(anchor)
        }
        .preference(key: OwnsEscape.self, value: true)
    }
}

/// What a sheet being written links: its chips, × on each, and Link… to search or paste an address (T-333). A Slack
/// link on the clipboard comes on its own, unless the sheet is about an item already (Remind Me…, T-343).
struct LinksField: View {
    @Binding var links: [ModalRoute]
    var autofill = true
    /// The item the sheet is about: its chip is short, the words already say its title.
    var subject: ModalRoute? = nil
    /// The sheet's name in UI test anchors: `new-task`, `new-reminder`.
    let anchor: String
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(links, id: \.self) { route in
                HStack(spacing: Space.xs) {
                    // Short where the sheet's words say the rest: a Slack message, the item it's about, or many links.
                    OutputChip(route: route, short: route.isSlack || route == subject || links.count > 2, plain: true)
                    Button { remove(route) } label: { Label("Don’t Link It", icon: .close).labelStyle(.iconOnly) }
                        .buttonStyle(.borderless)
                        .clickable()
                        .help("Don’t link \(model.title(of: route))")
                        .uiTestAnchor("\(anchor)-unlink:\(route.selectionKey)")
                }
                .uiTestAnchor("\(anchor)-link:\(route.selectionKey)")
            }
            Button { picking = true } label: { Label("Link…", icon: .link) }
                .help("Link a task, a file, an artifact, a pull request, or paste any address")
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    LinkPicker(linked: links, pick: add) { picking = false }
                }
                .uiTestAnchor("\(anchor)-link-button")
        }
        .task {
            guard autofill, let copied = await model.copiedSlackLink() else { return }
            add(.slack(copied))
        }
    }

    private func add(_ route: ModalRoute) {
        if case .slack(let url) = route { model.resolveSlack(url) }
        if !links.contains(route) { links.append(route) }
    }

    private func remove(_ route: ModalRoute) {
        links.removeAll { $0 == route }
        if case .slack(let url) = route { model.dropCopiedLink(url) }
    }
}

/// The words of a sheet being written: a Slack link pasted in them becomes a link, and while the user hasn't typed
/// their own, they are the linked message's first line.
@MainActor
struct DraftWords {
    /// The words the message gave, replaced when it arrives, kept once the user types.
    var named: String?

    /// A pasted Slack link leaves the words for the links.
    static func takeLink(from text: inout String, into links: inout [ModalRoute]) {
        guard let found = SlackLink.find(in: text) else { return }
        text.removeSubrange(found.range)
        text = text.trimmingCharacters(in: .whitespaces)
        let route = ModalRoute.slack(found.url)
        if !links.contains(route) { links.append(route) }
    }

    /// The first Slack link's message names the draft while its words are empty or still the last ones it gave.
    mutating func name(_ text: inout String, after links: [ModalRoute], in model: AppModel) {
        guard let url = links.lazy.compactMap(\.slackURL).first, let line = model.slackMessages[url]?.firstLine, !line.isEmpty,
              text.isEmpty || text == named else { return }
        text = line
        named = line
    }

    /// What the draft is called: its words, else its Slack message's first line.
    static func words(_ text: String, links: [ModalRoute], in model: AppModel) -> String {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.isEmpty, let url = links.lazy.compactMap(\.slackURL).first else { return typed }
        return model.name(fromSlack: url)
    }
}

extension ModalRoute {
    var isSlack: Bool { slackURL != nil }
    var slackURL: String? { if case .slack(let url) = self { url } else { nil } }
}

/// New Task… (⌘N, ⌥⌘N for the Backlog, +, the menu bar and Dock menus; T-332): the title, a description, Tasks or the
/// Backlog, the project, what it links. Return in the title or ⌘Return adds it. The lists' New Task lines still add in place.
struct NewTaskForm: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var notes = ""
    @State private var list: TaskList
    @State private var project: String?
    @State private var links: [ModalRoute] = []
    @State private var words = DraftWords()
    @FocusState private var typing: Bool

    init(list: TaskList) {
        _list = State(initialValue: list)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                GridRow {
                    FormLabel("Task")
                    TextField("Retry budget for blob uploads", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($typing)
                        .onSubmit(add)
                        .uiTestAnchor("new-task-title")
                }
                GridRow {
                    FormLabel("Description")
                    TextField("Optional, in markdown", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .uiTestAnchor("new-task-notes")
                }
                GridRow {
                    FormLabel("In")
                    Picker("In", selection: $list) {
                        Text("Tasks").tag(TaskList.overview)
                        Text("Backlog").tag(TaskList.backlog)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .uiTestAnchor("new-task-list")
                }
                GridRow {
                    FormLabel("Project")
                    Picker("Project", selection: $project) {
                        Text("None").tag(String?.none)
                        if !model.allProjects.isEmpty { Divider() }
                        ForEach(model.allProjects, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .uiTestAnchor("new-task-project")
                }
                GridRow {
                    FormLabel("Links")
                    LinksField(links: $links, anchor: "new-task")
                }
            }
            Spacer(minLength: 0)
            FormButtons(title: "Add Task", ready: !DraftWords.words(title, links: links, in: model).isEmpty, anchor: "new-task-add", add: add)
        }
        .padding(Space.xl)
        .onAppear { DispatchQueue.main.async { typing = true } }
        .onChange(of: title) { DraftWords.takeLink(from: &title, into: &links) }
        .onChange(of: links) { words.name(&title, after: links, in: model) }
        .onChange(of: links.lazy.compactMap(\.slackURL).first.flatMap { model.slackMessages[$0] }) { words.name(&title, after: links, in: model) }
    }

    private func add() {
        let name = DraftWords.words(title, links: links, in: model)
        guard !name.isEmpty else { return }
        // Addresses go in the task's note with it; tasks, files and artifacts link once it exists. One Undo either way.
        guard let task = model.addTask(to: list, title: name, body: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                       project: project, links: links.compactMap(\.address).compactMap(URL.init(string:))) else { return }
        for route in links where route.address == nil { model.link(route, to: task.id) }
        model.back()
        model.show(newTask: task.id, in: list)
    }
}

extension ModalRoute {
    /// A PR's, an issue's, a Slack message's or a web page's address: what a task's note keeps in its links.
    var address: String? {
        switch self {
        case .github(let url), .web(let url), .slack(let url): url
        default: nil
        }
    }
}

/// New Reminder… (⌃⌘R, +, the menu bar and Dock menus): what, its links, when, important; the keyboard in the text. A
/// Slack link copied before it, or pasted in its text, comes with it and names it (T-313). Remind Me… on an item opens it
/// about that item: linked, its title the words until the user types (T-343).
struct NewReminderForm: View {
    @Environment(AppModel.self) private var model
    /// The task, PR, file or artifact it's about.
    let about: ModalRoute?
    @State private var text = ""
    @State private var due = ReminderTime.date(.tomorrow)
    @State private var important = true
    @State private var picking = false
    @State private var links: [ModalRoute]
    @State private var words = DraftWords()
    @FocusState private var typing: Bool

    init(about: ModalRoute? = nil) {
        self.about = about
        _links = State(initialValue: about.map { [$0] } ?? [])
    }

    /// The item it's about, while it's still linked.
    private var subject: ModalRoute? { about.flatMap { links.contains($0) ? $0 : nil } }

    /// What it reminds of: the typed words, a Slack message's first line, else the item's title.
    private var reminder: String {
        let words = DraftWords.words(text, links: links, in: model)
        return words.isEmpty ? subject.map { model.title(of: $0) } ?? "" : words
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                GridRow {
                    FormLabel("Remind me to")
                    TextField(subject.map { model.title(of: $0) } ?? "Call noor about the GPU quota", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused($typing)
                        .onSubmit(add)
                        .uiTestAnchor("new-reminder-text")
                }
                GridRow {
                    FormLabel("Links")
                    LinksField(links: $links, autofill: about == nil, subject: about, anchor: "new-reminder")
                }
                GridRow {
                    FormLabel("When")
                    Button { picking = true } label: { Label(ReminderTime.describe(due, now: model.now), icon: .later) }
                        .clickable()
                        .fixedSize()
                        .help("When it comes back")
                        .popover(isPresented: $picking, arrowEdge: .bottom) {
                            WhenPicker(now: model.now, current: due) { date in
                                due = date
                                picking = false
                                typing = true
                            }
                        }
                        .uiTestAnchor("new-reminder-when")
                }
                GridRow {
                    FormLabel("Important")
                    Toggle(isOn: $important) { Text("It needs you when it comes back, with a banner") }
                        .clickable()
                        .uiTestAnchor("new-reminder-important")
                }
            }
            Spacer(minLength: 0)
            FormButtons(title: "Add Reminder", ready: !reminder.isEmpty, anchor: "new-reminder-add", add: add)
        }
        .padding(Space.xl)
        // The sheet may come up as HQ comes forward from another app: the keyboard goes in once it has the window.
        .onAppear { DispatchQueue.main.async { typing = true } }
        .onChange(of: text) { DraftWords.takeLink(from: &text, into: &links) }
        .onChange(of: links) { words.name(&text, after: links, in: model) }
        .onChange(of: links.lazy.compactMap(\.slackURL).first.flatMap { model.slackMessages[$0] }) { words.name(&text, after: links, in: model) }
    }

    private func add() {
        let reminder = reminder
        guard !reminder.isEmpty else { return }
        model.remind(reminder, at: due, level: important ? .important : .update, links: links.map(\.selectionKey))
        model.back()
    }
}

/// New File… (⌃⌘N, + › New File…, the Files header's +): a note in the vault by its title, opened in its editor.
struct NewFileForm: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @FocusState private var typing: Bool

    private var name: String { title.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                GridRow {
                    FormLabel("Title")
                    TextField("Jobs network", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($typing)
                        .onSubmit(add)
                        .uiTestAnchor("new-file-title")
                }
            }
            Spacer(minLength: 0)
            FormButtons(title: "Create", ready: !name.isEmpty, anchor: "new-file-create", add: add)
        }
        .padding(Space.xl)
        .onAppear { DispatchQueue.main.async { typing = true } }
    }

    private func add() {
        guard !name.isEmpty else { return }
        model.back()
        model.newFile(title: name)
    }
}

/// Import Artifact… (File menu, the Files header): a claude.ai artifact HQ didn't capture, by its link and a title. A link on
/// the clipboard fills the link.
struct ImportArtifactForm: View {
    @Environment(AppModel.self) private var model
    @State private var link = ""
    @State private var title = ""
    @FocusState private var focus: Field?

    private enum Field { case link, title }

    private var url: URL? { AppModel.artifactURL(link) }
    private var name: String { title.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                GridRow {
                    FormLabel("Link")
                    VStack(alignment: .leading, spacing: Space.xs) {
                        // Verbatim: a localized key would turn the address into a link.
                        TextField("Link", text: $link, prompt: Text(verbatim: "https://claude.ai/artifact/…"))
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .link)
                            .uiTestAnchor("import-link")
                        if !link.isEmpty, url == nil {
                            Text("Not a claude.ai artifact link.").kitType(.meta).foregroundStyle(Ink.failedText)
                        } else if let url, model.artifacts.contains(where: { $0.id == url }) {
                            Text("Already in HQ: importing renames it.").kitType(.meta).foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    FormLabel("Title")
                    TextField("Title", text: $title, prompt: Text("HQ Notification Center"))
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .title)
                        .onSubmit(add)
                        .uiTestAnchor("import-title")
                }
            }
            Spacer(minLength: 0)
            FormButtons(title: "Import", ready: url != nil && !name.isEmpty, anchor: "import-add", add: add)
        }
        .padding(Space.xl)
        .onAppear { DispatchQueue.main.async { focus = .link } }
        .task { await fill() }
    }

    /// The link on the clipboard when it's an artifact's, and its title when HQ has it; then the keyboard in the title.
    private func fill() async {
        let copied = await Self.copiedLink()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard link.isEmpty, let url = AppModel.artifactURL(copied) else { return }
        link = copied
        title = model.artifacts.first { $0.id == url }?.title ?? ""
        focus = .title
    }

    /// The clipboard's text, read only when it holds a link, so macOS asks about pasting only then; a test run's own.
    private static func copiedLink() async -> String? {
        if Store.isOverridden { return SlackClipboard.testText }
        let pasteboard = NSPasteboard.general
        guard let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]), !patterns.isEmpty else { return nil }
        return pasteboard.string(forType: .string)
    }

    private func add() {
        guard let url, !name.isEmpty else { return }
        let artifact = model.importArtifact(url, title: name)
        model.back()
        model.show(imported: artifact)
    }
}
