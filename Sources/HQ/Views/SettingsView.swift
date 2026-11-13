import AppKit
import HQKit
import ServiceManagement
import SwiftUI

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, projects, claude, ghostty, github, slack, keys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .projects: "Projects"
        case .claude: "Claude"
        case .ghostty: "Ghostty"
        case .github: "GitHub"
        case .slack: "Slack"
        case .keys: "Keys"
        }
    }

    var icon: KitIcon {
        switch self {
        case .general: .general
        case .projects: .project
        case .claude: .sessions
        case .ghostty: .ghostty
        case .github: .pullRequest
        case .slack: .slack
        case .keys: .keyboard
        }
    }
}

/// The Settings window (⌘,): one tab per topic, one grouped form each, only what works.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // Sizes read `Zoom.factor`, which SwiftUI doesn't observe: each zoom step makes Settings again (T-448).
        let zoom = model.zoom
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, icon: tab.icon) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
        .controlSize(Zoom.controlSize(zoom))
        .id(zoom)
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .projects: ProjectsSettings()
            case .claude: ClaudeSettings()
            case .ghostty: GhosttySettings()
            case .github: GitHubSettings()
            case .slack: SlackSettings()
            case .keys: KeysSettings()
            }
        }
        .formStyle(.grouped)
        .handCursors()
        .fitsContent()
        .frame(width: Metric.settingsWidth)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Section {
            Toggle("Open HQ at login", isOn: $openAtLogin)
                .controlSize(.mini)
                .onChange(of: openAtLogin) { _, on in
                    guard !Store.isOverridden else { return }
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
        }
        Section {
            LabeledContent("Vault") {
                HStack(spacing: Space.sm) {
                    Text(model.setup.vaultPath ?? "Not found")
                        .kitType(.key)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.setup.vaultPath ?? "")
                    Button("Choose…") { model.chooseVault() }
                }
            }
        } header: {
            Text("Obsidian")
        } footer: {
            Text("Tasks live in hq/tasks/ and files in hq/files/. HQ writes only the properties it owns.")
                .foregroundStyle(.secondary)
        }
    }
}

struct ClaudeSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Plugin") {
                HStack(spacing: Space.sm) {
                    StatusText(ok: model.setup.pluginInstalled, yes: "Installed", no: "Not installed")
                    Button(model.pluginInstalling ? "Installing…" : model.setup.pluginInstalled ? "Update" : "Install") { model.installPlugin() }
                        .disabled(model.pluginInstalling)
                        .help("Install the hq plugin for every Claude session, or update it to this version of HQ")
                }
            }
            if let error = model.pluginError {
                Text(error).kitType(.callout).foregroundStyle(Ink.failedText)
            }
            LabeledContent("Last hook event") {
                Text(model.lastHookEvent.map { $0.formatted(.relative(presentation: .named)) } ?? "None since HQ started")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("The hq plugin reports each session’s state to HQ through hooks, and teaches Claude the hq command. Sessions started before it was installed don’t report.")
                .foregroundStyle(.secondary)
        }
    }
}

struct GhosttySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Automation") {
                HStack(spacing: Space.sm) {
                    StatusText(ok: model.setup.ghosttyAllowed, yes: "Allowed", no: "Not allowed")
                    if model.setup.ghosttyAllowed {
                        Button("Open System Settings…") { model.openAutomationSettings() }
                    } else {
                        Button("Allow…") { model.allowGhostty() }
                    }
                }
            }
        } footer: {
            Text("HQ asks Ghostty to focus a session’s terminal, open a tab to start or resume one, and type /exit, then close its terminal, to close one. It never reads what’s on screen.")
                .foregroundStyle(.secondary)
        }
    }
}

struct GitHubSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("GitHub CLI") {
                StatusText(ok: model.setup.ghPath != nil, yes: model.setup.ghPath ?? "Found", no: "Not found")
            }
            LabeledContent("Account") {
                HStack(spacing: Space.sm) {
                    StatusText(ok: model.setup.githubAccount != nil, yes: model.setup.githubAccount ?? "", no: "Signed out")
                    if model.setup.githubAccount == nil {
                        Button("Copy Command") { Pasteboard.copy("gh auth login") }
                            .help("Copy gh auth login, to run in a terminal")
                    }
                }
            }
            LabeledContent("Last update") {
                Text(model.githubUpdated.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("HQ reads your pull requests, the reviews asked of you, and the PRs and issues your tasks link, with the token of gh auth token. It never writes to GitHub.")
                .foregroundStyle(.secondary)
        }
        Section {
            @Bindable var model = model
            Picker("Notify about the last", selection: $model.githubLookback) {
                ForEach(AppModel.lookbackChoices, id: \.self) { Text("\($0) days").tag($0) }
            }
            .uiTestAnchor("github-lookback")
        } header: {
            Text("Notifications")
        } footer: {
            Text("Reviews, comments, mentions and review requests from this far back notify once, so HQ catches up after it was off.")
                .foregroundStyle(.secondary)
        }
    }
}

/// The Slack user token, in the Keychain (T-312): it names a linked message by who wrote it, where, and its first line.
struct SlackSettings: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""

    var body: some View {
        Section {
            LabeledContent("Account") {
                HStack(spacing: Space.sm) {
                    StatusText(ok: model.slackAccount != nil, yes: model.slackAccount.map { "\($0.user) · \($0.team)" } ?? "",
                               no: model.slackError ?? "No token")
                    if model.slackAccount != nil || model.slackError != nil {
                        Button("Remove") { model.setSlackToken(nil) }
                            .help("Forget the token: Slack links show as links")
                            .uiTestAnchor("slack-remove")
                    }
                }
            }
            LabeledContent("User token") {
                HStack(spacing: Space.sm) {
                    SecureField("User token", text: $token, prompt: Text("xoxp-…"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Metric.settingsField)
                        .labelsHidden()
                        .onSubmit(save)
                        .uiTestAnchor("slack-token")
                    Button("Save", action: save)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .uiTestAnchor("slack-save")
                }
            }
        } footer: {
            Text("HQ reads a Slack message once, when it’s linked to a task or a reminder, to show who wrote it, where, and its first line. It never writes to Slack. The token needs these scopes: channels:history, groups:history, im:history, mpim:history, channels:read, groups:read, im:read, mpim:read, users:read.")
                .foregroundStyle(.secondary)
        }
        Section {
            Text("Copy a message’s link in Slack, then New Task or New Reminder…: it comes with the link, named after the message.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Links")
        }
    }

    private func save() {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.setSlackToken(value)
        token = ""
    }
}

struct KeysSettings: View {
    static let keys: [(String, String)] = [
        ("Next or previous section", "Tab  ⇧Tab"),
        ("Select in a section, open", "↑  ↓, Return or Space"),
        ("Copy the selected item’s line", "⌘C"),
        ("Notifications", "⌘J"),
        ("New Reminder…", "⌃⌘R"),
        ("New Task…", "⌘N"),
        ("New Backlog Task…", "⌥⌘N"),
        ("New File…", "⌃⌘N"),
        ("New Session…", "⇧⌘N"),
        ("Quick Open", "⌘K  ⌘P"),
        ("Show or hide the Backlog", "⌃⌘B"),
        ("Show the HQ window", "⌘0"),
        ("Zoom in, zoom out", "⌘+  ⌘−"),
        ("Back, in the modal", "⌘["),
        ("Focus the session's terminal", "⌘O"),
        ("Open the item outside HQ", "⇧⌘O"),
        ("Copy the item’s link", "⇧⌘C"),
        ("Edit the file, or the role picked in Roles", "⌘E"),
        ("Reload the page", "⌘R"),
        ("Find, next, previous", "⌘F  ⌘G  ⇧⌘G"),
        ("Search", "⌥⌘F"),
    ]
    static let rowKeys: [(String, String)] = [
        ("Next or previous task; past the last, the new task", "↓  ↑"),
        ("Edit the title", "Return, or double-click"),
        ("Show or hide the description", "⇧Return"),
        ("Edit the description", "Double-click where to type"),
        ("New task below, new subtask", "N  ⇧N"),
        ("Indent, outdent", "⇧→  ⇧←"),
        ("Move up or down", "⇧↑  ⇧↓"),
        ("Hide or show the subtasks", "←  →, or click the chevron"),
        ("Hide or show the subtasks of every task under it", "⌥←  ⌥→"),
        ("Next status", "⌘Return, or click the status"),
        ("Status menu", "⌥-click the status"),
        ("Unselect: nothing dimmed", "Escape"),
        ("Open the task", "Space  ⌘I, or double-click the row"),
        ("Block or unblock, blocked by, after", "B  ⇧B  A"),
        ("To the Backlog or to Tasks", "⇧⌘B"),
        ("Start Session…", "⌥⌘Return"),
        ("Delete", "⌫  ⌘⌫"),
    ]
    static let cardKeys: [(String, String)] = [
        ("Its terminal, its details", "Return  Space"),
        ("Walk the cards, an open team's rows", "←  →  ↑  ↓"),
        ("Show or hide a team's sessions", "⌘↓  ⌘↑, or click its toggle"),
        ("Move up or down, indent, outdent; on two columns, a card left or right", "⇧↑  ⇧↓  ⇧→  ⇧←"),
        ("Hide them", "Escape, or click outside"),
    ]
    static let titleKeys: [(String, String)] = [
        ("New task below", "Return"),
        ("Edit the description", "Tab  ⇧Return"),
        ("Edit the previous title", "⇧Tab"),
        ("Back to the rows", "Escape  ↑  ↓"),
        ("Outdent at its start, indent at its end", "⇧←  ⇧→"),
        ("Next status", "⌘Return"),
        ("Open, to the Backlog or Tasks, Start Session…", "⌘I  ⇧⌘B  ⌥⌘Return"),
        ("Delete", "⌘⌫"),
    ]
    static let descriptionKeys: [(String, String)] = [
        ("Save, back to the row", "Escape  ⌘Return"),
        ("Next list item, or end the list on an empty one", "Return"),
        ("Nest a list item, take it out", "Tab  ⇧Tab"),
        ("Edit the next title, this title, off a list", "Tab  ⇧Tab"),
        ("Bold, italic, link", "⌘B  ⌘I  ⌘K"),
        ("Link words to a copied address", "⌘V over them"),
        ("Tick a checkbox", "Click it"),
    ]
    static let noticeKeys: [(String, String)] = [
        ("Next or previous", "↓  ↑"),
        ("Open what it links, edit a reminder", "Return, or double-click"),
        ("Read or unread, done or not", "E"),
        ("Later", "L"),
        ("Copy its text", "⌘C"),
        ("Delete", "⌫"),
    ]
    /// Every list, for the self-test that holds them to the menus.
    static var all: [(String, String)] { keys + rowKeys + cardKeys + titleKeys + descriptionKeys + noticeKeys }

    var body: some View {
        Section("Everywhere") { rows(Self.keys) }
        Section("On a selected task") { rows(Self.rowKeys) }
        Section("On a session card") { rows(Self.cardKeys) }
        Section {
            rows(Self.titleKeys)
        } header: {
            Text("In a task’s title")
        } footer: {
            Text("A task left with no title and no description is deleted; Undo brings it back.").foregroundStyle(.secondary)
        }
        Section {
            rows(Self.descriptionKeys)
        } header: {
            Text("In a task’s description")
        } footer: {
            Text("A note’s editor has the same keys; a double-click on a description or a note edits it where you clicked.").foregroundStyle(.secondary)
        }
        Section("In the notifications") { rows(Self.noticeKeys) }
    }

    private func rows(_ list: [(String, String)]) -> some View {
        ForEach(list, id: \.0) { title, key in
            LabeledContent(title) {
                Text(key).kitType(.key).foregroundStyle(.secondary)
            }
        }
    }
}

/// A status word with a symbol, so color never carries it alone. The word stays primary.
private struct StatusText: View {
    let ok: Bool
    let yes: String
    let no: String

    var body: some View {
        HStack(spacing: Space.xs) {
            (ok ? KitIcon.checkPassed : KitIcon.pending).image.accessibilityHidden(true)
                .foregroundStyle(ok ? AnyShapeStyle(Ink.done) : AnyShapeStyle(.secondary))
            Text(ok ? yes : no)
                .foregroundStyle(ok ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
