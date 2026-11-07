import AppKit
import HQKit
import ServiceManagement
import SwiftUI

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, projects, claude, ghostty, github, keys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .projects: "Projects"
        case .claude: "Claude"
        case .ghostty: "Ghostty"
        case .github: "GitHub"
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
        case .keys: .keyboard
        }
    }
}

/// The Settings window (⌘,): one tab per topic, one grouped form each, only what works.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, icon: tab.icon) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
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

struct KeysSettings: View {
    private let keys: [(String, String)] = [
        ("Next or previous section", "Tab  ⇧Tab"),
        ("Select in a section, open", "↑  ↓, Return or Space"),
        ("Notifications", "⌘J"),
        ("Mark all notifications read", "⇧⌘J"),
        ("New Reminder…", "⌃⌘R"),
        ("New Task", "⌘N"),
        ("New Backlog Task", "⌥⌘N"),
        ("New File…", "⌃⌘N"),
        ("New Session…", "⇧⌘N"),
        ("Quick Open", "⌘K  ⌘P"),
        ("Show or hide the Backlog", "⌃⌘B"),
        ("Show the HQ window", "⌘0"),
        ("Zoom in, zoom out", "⌘+  ⌘−"),
        ("Back, in the modal", "⌘["),
        ("Focus the session's terminal", "⌘O"),
        ("Open the item outside HQ", "⇧⌘O"),
        ("Edit the file", "⌘E"),
        ("Reload the page", "⌘R"),
        ("Find, next, previous", "⌘F  ⌘G  ⇧⌘G"),
        ("Search", "⌥⌘F"),
    ]
    private let rowKeys: [(String, String)] = [
        ("Next or previous task", "↓  ↑"),
        ("Edit the title", "Return, or double-click"),
        ("Show or hide the description", "⇧Return"),
        ("Edit the description", "Double-click it"),
        ("New task below, new subtask", "N  ⇧N"),
        ("Indent, outdent", "⇧→  ⇧←"),
        ("Move up or down", "⇧↑  ⇧↓"),
        ("Fold, unfold", "←  →"),
        ("Next status", "⌘Return, or click the status"),
        ("Status menu", "⌥-click the status"),
        ("Open the task", "Space  ⌘I, or double-click the row"),
        ("To the Backlog or to Tasks", "⇧⌘B"),
        ("Start Session…", "⌥⌘Return, or click the empty face"),
        ("Delete", "⌫  ⌘⌫"),
    ]
    private let titleKeys: [(String, String)] = [
        ("New task below", "Return"),
        ("Edit the description", "Tab  ⇧Return"),
        ("Edit the previous title", "⇧Tab"),
        ("Back to the rows", "Escape  ↑  ↓"),
        ("Next status", "⌘Return"),
        ("Delete", "⌘⌫"),
    ]
    private let descriptionKeys: [(String, String)] = [
        ("Save, back to the row", "Escape  ⌘Return"),
        ("Edit the next title, this title", "Tab  ⇧Tab"),
    ]
    private let noticeKeys: [(String, String)] = [
        ("Next or previous", "↓  ↑"),
        ("Open what it links, edit a reminder", "Return, or double-click"),
        ("Read or unread, done or not", "E"),
        ("Later", "L"),
        ("Copy its text", "⌘C"),
        ("Delete", "⌫"),
    ]

    var body: some View {
        Section("Everywhere") { rows(keys) }
        Section("On a selected task") { rows(rowKeys) }
        Section {
            rows(titleKeys)
        } header: {
            Text("In a task’s title")
        } footer: {
            Text("A task left with no title and no description is deleted; Undo brings it back.").foregroundStyle(.secondary)
        }
        Section("In a task’s description") { rows(descriptionKeys) }
        Section("In the notifications") { rows(noticeKeys) }
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
