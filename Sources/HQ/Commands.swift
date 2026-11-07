import HQKit
import SwiftUI

/// The menu bar (DESIGN.md §13). Task items whose keys are also text keys carry their shortcut
/// only while the outline has the keyboard, so editors keep ⌘Return, ⇧Return, ⌘⌫ and ⇧ with arrows.
struct HQCommands: Commands {
    let model: AppModel
    @ObservedObject var menu: MenuState
    let quickOpen: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {

        // Closing the window hides it; Window › HQ brings it back.
        CommandGroup(before: .windowList) {
            Button("HQ") {
                if let window = model.window { window.makeKeyAndOrderFront(nil) } else { openWindow(id: "main") }
            }
            .keyboardShortcut("0")
            Divider()
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close") {
                // The modal's sheet, or the window under it, has the keyboard: the modal closes first.
                let key = NSApp.keyWindow
                if model.modal != nil, key == nil || key === model.window || key?.sheetParent === model.window {
                    model.closeModal()
                } else {
                    key?.performClose(nil)
                }
            }
                .keyboardShortcut("w")
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                model.settingsTab = .keys
                openSettings()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Task") { model.focusQuickAdd(.overview) }
                .keyboardShortcut("n")
            Button("New Backlog Task") { model.focusQuickAdd(.backlog) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New File…") { model.beginNewFile() }
                .keyboardShortcut("n", modifiers: [.command, .control])
            Button("New Session…") { model.beginStart() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Reminder…") { model.beginReminder() }
                .keyboardShortcut("r", modifiers: [.command, .control])
            Divider()
            // ⌘P opens it too (AppDelegate), as in Zed: HQ prints nothing.
            Button("Quick Open…", action: quickOpen)
                .keyboardShortcut("k")
            Divider()
            Button(menu.outside ?? "Open Outside HQ") { model.openOutside(model.menuRoute) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(menu.outside == nil)
            Button("Copy Link") { if let link = menu.link { Pasteboard.copy(link) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(menu.link == nil)
            Divider()
            Button("Import Artifact…") { model.beginImport() }
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") { model.focusSearch() }
                .keyboardShortcut("f")
            Button("Find Next") { model.findInEditor(.nextMatch) }
                .keyboardShortcut("g")
                .disabled(!menu.editorFind)
            Button("Find Previous") { model.findInEditor(.previousMatch) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!menu.editorFind)
            Button("Jump to Search Field") { model.focusToolbarSearch() }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandGroup(before: .toolbar) {
            ForEach(TaskList.allCases) { list in
                let place = list == .overview ? "in Tasks" : "in the Backlog"
                Button(menu.descriptions.contains(list) ? "Hide Descriptions \(place)" : "Show Descriptions \(place)") {
                    model.allDescriptions.formSymmetricDifference([list])
                }
                if list == .overview {
                    Button(menu.hideDone.contains(list) ? "Show Done \(place)" : "Hide Done \(place)") { model.hideDone.formSymmetricDifference([list]) }
                }
            }
            Divider()
            ForEach(PageSection.allCases, id: \.self) { section in
                Button(menu.folded.contains(section) ? "Show \(section.title)" : "Hide \(section.title)") {
                    model.folded.formSymmetricDifference([section])
                }
            }
            Button(menu.backlogOpen ? "Hide Backlog" : "Show Backlog") { model.backlogOpen.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .control])
            Divider()
            Button("Refresh Pull Requests") { model.refreshGitHub() }
                .disabled(!menu.github)
            Picker("Reviews", selection: Binding(get: { menu.reviewFilter }, set: { model.reviewFilter = $0 })) {
                ForEach(ReviewFilter.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Pinned Files and Artifacts Only", isOn: Binding(get: { menu.pinnedOnly }, set: { model.pinnedOnly = $0 }))
            Divider()
            Button("Zoom In") { model.zoom(by: 1) }
                .keyboardShortcut("+")
                .disabled(menu.zoom >= (Zoom.steps.last ?? 1))
            Button("Zoom Out") { model.zoom(by: -1) }
                .keyboardShortcut("-")
                .disabled(menu.zoom <= (Zoom.steps.first ?? 1))
            Button("Actual Size") { model.zoom = 1 }
                .disabled(menu.zoom == 1)
            Divider()
            Button("Reload Page") { model.artifactReloads += 1 }
                .keyboardShortcut("r")
                .disabled(!menu.artifact)
            Divider()
        }

        CommandMenu("Go") {
            Button("Notifications") { model.openCenter() }
                .keyboardShortcut("j")
                .disabled(menu.inCenter)
            Button("Back") { model.back() }
                .keyboardShortcut("[")
                .disabled(!menu.canGoBack)
            Divider()
            Button("Mark Reviewed") { if case .github(let url) = model.menuRoute { model.markReviewed(url) } }
                .disabled(!menu.reviewable)
        }

        CommandMenu("Task") {
            let task = menu.task
            // Keys that are also text keys bind only while the outline has the keyboard: ⌘Return and ⌘⌫ on
            // rows and titles, the others on rows. The outline takes the same keys itself first.
            let keys = menu.outlineKeyboard != .none
            let rows = menu.outlineKeyboard == .rows
            Button("Open") { if let task { model.open(.task(task)) } }
                .keyboardShortcut("i")
                .disabled(task == nil || menu.inModal)
            let several = menu.tasks.count > 1
            Button("Next Status") { model.nextStatus(menu.tasks) }
                .keyboardShortcut(keys ? KeyboardShortcut(.return, modifiers: .command) : nil)
                .disabled(task == nil)
            Button(several ? (menu.allDone ? "Mark \(menu.tasks.count) Not Done" : "Mark \(menu.tasks.count) Done")
                   : menu.taskIsDone ? "Mark Not Done" : "Mark Done") { model.markDone(menu.tasks) }
                .disabled(task == nil)
            Menu("Status") {
                ForEach(TaskStatus.allCases) { status in
                    Toggle(status.title, isOn: Binding(get: { menu.taskStatus == status },
                                                       set: { _ in for id in menu.tasks { model.setStatus(id, status) } }))
                }
            }
            .disabled(menu.tasks.isEmpty)
            Divider()
            Button(menu.taskDescriptionShown ? "Hide Description" : "Show Description") { model.toggleDescriptions(menu.tasks) }
                .keyboardShortcut(rows ? KeyboardShortcut(.return, modifiers: .shift) : nil)
                .disabled(task == nil || menu.inModal)
            Button("Edit Description") { if let task { model.editDescription(task) } }
                .keyboardShortcut(menu.outlineKeyboard == .title ? KeyboardShortcut(.return, modifiers: .shift) : nil)
                .disabled(task == nil)
            Button("Add Subtask") {
                guard let task, let added = model.addSubtask(to: task) else { return }
                // In the task's modal, its list shows the new subtask; on the page, its title edits.
                if !menu.inModal { model.outlineFocus = .title(added.id, by: 0) }
            }
                .disabled(task == nil)
            Button("Start Session…") { if let task { model.beginStart(task: task) } }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(task == nil)
            Button("Link…") { if let task { model.showLinkPicker(task) } }
                .disabled(task == nil || menu.inModal)
            Divider()
            Button(menu.tasksToBacklog ? (several ? "Move \(menu.tasks.count) to Backlog" : "Move to Backlog")
                   : (several ? "Move \(menu.tasks.count) to Tasks" : "Move to Tasks")) {
                model.moveTasks(menu.tasks, toBacklog: menu.tasksToBacklog)
            }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(task == nil)
            Button("Move Up") { model.shiftTasks(menu.tasks, by: -1) }
                .keyboardShortcut(rows ? KeyboardShortcut(.upArrow, modifiers: .shift) : nil)
                .disabled(task == nil)
            Button("Move Down") { model.shiftTasks(menu.tasks, by: 1) }
                .keyboardShortcut(rows ? KeyboardShortcut(.downArrow, modifiers: .shift) : nil)
                .disabled(task == nil)
            Button("Indent") { model.indentTasks(menu.tasks) }
                .keyboardShortcut(rows ? KeyboardShortcut(.rightArrow, modifiers: .shift) : nil)
                .disabled(task == nil)
            Button("Outdent") { model.outdentTasks(menu.tasks) }
                .keyboardShortcut(rows ? KeyboardShortcut(.leftArrow, modifiers: .shift) : nil)
                .disabled(task == nil)
            Divider()
            Button("Copy Key and Title") {
                Pasteboard.copy(menu.tasks.compactMap { model.task($0) }.map { "\($0.key) \($0.title)" }.joined(separator: "\n"))
            }
            .disabled(task == nil)
            Button(several ? "Delete \(menu.tasks.count) Tasks" : "Delete") { model.deleteTasks(menu.tasks) }
                .keyboardShortcut(keys ? KeyboardShortcut(.delete, modifiers: .command) : nil)
                .disabled(task == nil)
        }

        CommandMenu("Session") {
            let session = menu.session
            Button(menu.sessionRunning || session == nil ? "Focus" : "Resume") { if let session { model.open(session) } }
                .keyboardShortcut("o")
                .disabled(session == nil || !menu.sessionCanFocus)
            Button("Show Details") { if let session { model.open(.session(session)) } }
                .disabled(session == nil)
            Divider()
            Button("Close Session") { if let session { model.closeSession(session) } }
                .disabled(session == nil || !menu.sessionClosable)
            Divider()
            Button("Copy Resume Command") { if let item = model.session(session) { Pasteboard.copy(item.resumeCommand) } }
                .disabled(session == nil)
            Button("Copy Session ID") { if let session { Pasteboard.copy(session) } }
                .disabled(session == nil)
            Divider()
            Button("Start Review Session…") {
                if case .github(let url) = model.menuRoute, let item = model.githubItem(url) { model.beginStart(pullRequest: item, push: model.modal != nil) }
            }
            .disabled(!menu.pullRequest)
            Divider()
            Button("Closed Sessions") { model.open(.closedSessions) }
                .disabled(!menu.hasClosed)
        }

        CommandGroup(after: .pasteboard) {
            Button("Edit File") { if case .file(let id) = model.modal { model.beginFileEdit(id) } }
                .keyboardShortcut("e")
                .disabled(!menu.canEditFile)
        }
    }
}

extension AppModel {
    /// What the menu bar acts on: the open modal's item, else a PR, file or artifact selected on the page.
    var menuRoute: ModalRoute? {
        if let modal { return modal }
        guard let key = selectedItem, !key.hasPrefix(ModalRoute.chipPrefix), let route = ModalRoute(itemKey: key) else { return nil }
        switch route {
        case .github, .file, .artifact: return route
        default: return nil
        }
    }

    /// Where an item opens outside HQ: Ghostty, Obsidian, the browser or GitHub.
    func outsideTitle(_ route: ModalRoute?) -> String? {
        switch route {
        case .session(let id): session(id).flatMap { $0.isRunning ? ($0.tty == nil ? nil : "Focus") : "Resume" }
        case .task(let id): task(id)?.path == nil ? nil : "Open in Obsidian"
        case .file(let id): file(id)?.path == nil ? nil : "Open in Obsidian"
        case .artifact: "Open in Browser"
        case .github: "Open on GitHub"
        default: nil
        }
    }

    func openOutside(_ route: ModalRoute?) {
        switch route {
        case .session(let id): open(id)
        case .task(let id): openInObsidian(task(id)?.path)
        case .file(let id): openInObsidian(file(id)?.path)
        case .artifact(let url): NSWorkspace.shared.open(url)
        case .github(let url): if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        default: break
        }
    }

    /// The open item's web address, for Copy Link.
    func link(of route: ModalRoute?) -> String? {
        switch route {
        case .artifact(let url): url.absoluteString
        case .github(let url): url
        default: nil
        }
    }

    /// The markdown editor that has the keyboard, itself or through its find bar.
    func findEditor() -> NSTextView? {
        guard let responder = (NSApp.keyWindow ?? window)?.firstResponder as? NSView else { return nil }
        if let editor = responder as? NSTextView, editor.usesFindBar { return editor }
        if let editor = responder.enclosingScrollView?.documentView as? NSTextView, editor.usesFindBar,
           responder.enclosingScrollView?.isFindBarVisible == true { return editor }
        return nil
    }

    /// Find Next and Previous (⌘G, ⇧⌘G) in an editor's find bar.
    func findInEditor(_ action: NSTextFinder.Action) {
        guard let editor = findEditor() else { return }
        let item = NSMenuItem()
        item.tag = action.rawValue
        editor.performTextFinderAction(item)
    }

    /// Find (⌘F): an editor's find bar while one has the keyboard, else the toolbar's search field.
    func focusSearch() {
        if let editor = findEditor() {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            editor.performTextFinderAction(item)
            return
        }
        focusToolbarSearch()
    }

    /// Jump to Search Field (⌥⌘F): the toolbar's search field, wherever the keyboard is.
    func focusToolbarSearch() {
        showWindow()
        guard let toolbar = window?.toolbar,
              let item = toolbar.items.first(where: { $0 is NSSearchToolbarItem }) as? NSSearchToolbarItem else { return }
        item.beginSearchInteraction()
    }
}
