import AppKit
import HQKit
import SwiftUI

/// Where a project lives: the folder its sessions start in, and its GitHub repositories (`owner/name`).
struct ProjectLinks: Codable, Equatable {
    var folder: String?
    var repos: [String] = []

    var isEmpty: Bool { folder == nil && repos.isEmpty }
}

extension AppModel {
    /// Every project: the ones in use and the ones with links.
    var allProjects: [String] {
        var names = projects
        for (key, stored) in projectLinks where !names.contains(where: { Self.projectKey($0) == key }) {
            if let name = stored.name { names.append(name) }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func links(of project: String) -> ProjectLinks {
        projectLinks[Self.projectKey(project)]?.links ?? ProjectLinks()
    }

    /// Sets a project's folder and repositories; nil leaves one as it is. A project named here exists even with no task yet.
    func setLinks(_ project: String, folder: String?? = nil, repos: [String]? = nil) {
        let name = project.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var links = links(of: name)
        if let folder { links.folder = folder.map { ($0 as NSString).abbreviatingWithTildeInPath }.flatMap { $0.isEmpty ? nil : $0 } }
        if let repos {
            var seen = Set<String>()
            links.repos = repos.map(Self.repoName).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        }
        projectLinks[Self.projectKey(name)] = StoredProject(name: projects.first { Self.projectKey($0) == Self.projectKey(name) } ?? name, links: links)
    }

    /// `owner/name` from what the user types or pastes: a GitHub URL, `owner/name.git`, spaces.
    static func repoName(_ text: String) -> String {
        var name = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/", "git@github.com:"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        if name.hasSuffix(".git") { name.removeLast(4) }
        let parts = name.split(separator: "/").prefix(2)
        return parts.count == 2 ? parts.joined(separator: "/") : ""
    }

    /// The project a GitHub repository belongs to.
    func project(ofRepo repo: String) -> String? {
        allProjects.first { links(of: $0).repos.contains { $0.caseInsensitiveCompare(repo) == .orderedSame } }
    }

    /// The project a task belongs to: its own, else the nearest parent's.
    func project(ofTask id: Int?) -> String? {
        guard let id else { return nil }
        let tree = taskTree
        for candidate in [id] + tree.ancestors(of: id) {
            if let project = task(candidate)?.project { return project }
        }
        return nil
    }

    /// Where a project's sessions start: its folder, else the folder its sessions ran in most.
    func folder(of project: String) -> String? {
        if let folder = links(of: project).folder { return folder }
        return guessedFolder(of: project)
    }

    /// `hq ls projects`: the name, its folder (or the guess), repositories and open tasks.
    func projectJSON(_ project: String) -> [String: Any] {
        let links = links(of: project)
        let key = Self.projectKey(project)
        var json: [String: Any] = ["name": allProjects.first { Self.projectKey($0) == key } ?? project,
                                   "openTasks": tasks.filter { $0.status != .done && $0.project.map(Self.projectKey) == key }.count]
        if let folder = links.folder { json["folder"] = folder } else if let guess = guessedFolder(of: project) { json["folderGuess"] = guess }
        if !links.repos.isEmpty { json["repos"] = links.repos }
        return json
    }

    /// The folder the sessions on a project's tasks ran in most, the latest first on a tie.
    func guessedFolder(of project: String) -> String? {
        let key = Self.projectKey(project)
        var counts: [String: (count: Int, last: Date)] = [:]
        for session in sessions where !session.cwd.isEmpty
        && tasks(of: session.id).contains(where: { $0.project.map(Self.projectKey) == key }) {
            let entry = counts[session.cwd] ?? (0, .distantPast)
            counts[session.cwd] = (entry.count + 1, max(entry.last, lastActivity(session)))
        }
        return counts.max { ($0.value.count, $0.value.last) < ($1.value.count, $1.value.last) }
            .map { ($0.key as NSString).abbreviatingWithTildeInPath }
    }
}

/// A project's links as stored, with its name as the user wrote it.
struct StoredProject: Codable, Equatable {
    var name: String?
    var links: ProjectLinks
}

// MARK: Settings

/// Settings › Projects: each project's folder and GitHub repositories.
struct ProjectsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let projects = model.allProjects
        if projects.isEmpty {
            Section {
                Text("No project yet. A task's project chip, or `#Name` in its title, makes one.").foregroundStyle(.secondary)
            }
        }
        ForEach(projects, id: \.self) { project in
            ProjectSection(project: project)
        }
    }
}

private struct ProjectSection: View {
    let project: String
    @Environment(AppModel.self) private var model
    @State private var repos = ""

    var body: some View {
        let links = model.links(of: project)
        Section {
            LabeledContent("Folder") {
                HStack(spacing: Space.sm) {
                    if let folder = links.folder {
                        Text(folder).kitType(.key).lineLimit(1).truncationMode(.middle)
                    } else {
                        Text(model.guessedFolder(of: project).map { "\($0) (from its sessions)" } ?? "Not set")
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Button("Choose…") { choose() }
                    if links.folder != nil {
                        Button("Clear", icon: .close) { model.setLinks(project, folder: .some(nil)) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Forget the folder")
                    }
                }
            }
            TextField("GitHub", text: $repos, prompt: Text("owner/name, owner/name"))
                .onSubmit { model.setLinks(project, repos: repos.split(separator: ",").map(String.init)) }
                .help("Its repositories: review sessions on their PRs start in its folder")
        } header: {
            LabelChip(text: project, color: model.labelColor(.project, project), icon: .project)
        }
        .onAppear { repos = links.repos.joined(separator: ", ") }
        .onChange(of: links.repos) { _, next in repos = next.joined(separator: ", ") }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.message = "Where \(project)'s sessions start"
        if let folder = model.folder(of: project) { panel.directoryURL = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath) }
        if panel.runModal() == .OK, let url = panel.url { model.setLinks(project, folder: .some(url.path)) }
    }
}
