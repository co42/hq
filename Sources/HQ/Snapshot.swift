import AppKit
import IOKit.pwr_mgt
import SwiftUI
import WebKit

/// Screenshot mode for agents and review.
///   APP_STORE=/tmp/HQ-test.store APP_SEED=1 APP_SNAPSHOT=/tmp/HQ-shots HQ
/// writes <page>-<width>-<mode>.png for every page at 1504 and 756 pt wide (the two
/// half screens), settings-<tab>-<mode>.png, and a -layout.json next to each, then quits.
/// APP_SNAPSHOT_PAGES=sessions,tasks limits the pages; add "settings" for Settings.
/// APP_KIT_GALLERY=1 captures gallery-<mode>.png instead.
enum Snapshot {
    /// The two half-screen sizes HQ is designed for (DESIGN.md §3).
    static let sizes: [CGSize] = [CGSize(width: 1504, height: 1662), CGSize(width: 756, height: 950)] // grid: ok real half-screen sizes
        .filter { size in widths.map { $0.contains(Int(size.width)) } ?? true } + (widths ?? []).filter { $0 != 1504 && $0 != 756 }.map { CGSize(width: $0, height: 950) } // grid: ok the 756 snapshot's height
    /// APP_SNAPSHOT_WIDTHS=1200,756: other widths, such as the user's own half screen.
    private static var widths: [Int]? {
        ProcessInfo.processInfo.environment["APP_SNAPSHOT_WIDTHS"].map { $0.split(separator: ",").compactMap { Int($0) } }
    }

    struct Page {
        enum Capture { case window, sheet, quickOpen }
        let name: String
        var capture = Capture.window
        let configure: (AppModel) async -> Void
    }

    /// The seed's clock, the same for every page of a run.
    private static let seeded = Date.now

    static func pages(_ model: AppModel) -> [Page] {
        func copySlackLink() {
            SlackClipboard.testText = SlackService.fixtureLink
            SlackClipboard.testChange += 1
        }
        func reset(_ model: AppModel) {
            model.closeModal()
            // Each page on the same seed: a page that empties Needs You leaves it full for the next ones.
            SeedData.fill(model, now: seeded)
            if SeedData.large { SeedData.fillLarge(model, now: seeded) }
            model.pendingTaskLink = nil
            model.zoom = 1
            model.search = ""
            model.problem = nil
            model.showSetup = false
            model.backlogOpen = false
            model.folded = []
            model.backlogFilter = BacklogFilter()
            model.hideDone = []
            model.pinnedOnly = false
            model.allDescriptions = []
            model.editingDescription = nil
            model.shownDescriptions = [44]
            (mainWindow?.firstResponder as? NSTextView)?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            mainWindow?.makeFirstResponder(nil)
            // A page's selected task would dim the next pages' cards.
            if let root = mainWindow?.contentView { views(TaskOutlineView.self, in: root).first?.deselectAll(nil) }
            // A page's drag over the sessions ends.
            if let root = mainWindow?.contentView {
                views(SessionGrid.CardCollection.self, in: root).first?.draggingExited(nil)
                for team in views(TeamCardView.self, in: root) { team.draggingExited(nil) }
            }
            model.openTeam = nil
            scroll(to: 0)
        }
        let pr = "https://github.com/acme/registry/pull/418"
        return [
            Page(name: "cockpit") { reset($0) },
            Page(name: "cockpit-zoom") { model in
                reset(model)
                model.zoom = 1.3
            },
            Page(name: "cockpit-backlog") { model in
                reset(model)
                model.backlogOpen = true
                await ready()
                scrollToBottom()
                select(task: 36)
            },
            // A selected task with every kind of link, one a Slack message too long for a line (T-377, T-429).
            Page(name: "cockpit-links") { model in
                reset(model)
                SeedData.linkEveryKind(model)
                await ready()
                if let root = mainWindow?.contentView, let outline = views(TaskOutlineView.self, in: root).first {
                    scroll(toTopOf: outline, below: Metric.skyHeight / 4)
                }
                select(task: 13)
            },
            Page(name: "cockpit-descriptions") { model in
                reset(model)
                model.allDescriptions = [.overview, .backlog]
                await ready()
                scroll(to: 0.45)
            },
            Page(name: "cockpit-description-edit") { model in
                reset(model)
                model.allDescriptions = [.overview, .backlog]
                model.editDescription(13)
                await ready()
                scroll(to: 0.45)
            },
            Page(name: "cockpit-folded") { model in
                reset(model)
                model.folded = [.pullRequests, .files]
            },
            Page(name: "cockpit-nested") { model in
                // A block inside a story, with a block of its own: every tray's edges (T-445).
                reset(model)
                if let inner = model.addSubtask(to: 51, title: "Token exchange in the init container") {
                    _ = model.addSubtask(to: inner.id, title: "Read the token from the projected volume")
                    _ = model.addSubtask(to: inner.id, title: "Refresh it before it expires")
                }
                _ = model.addSubtask(to: 51, title: "Retry while the identity isn't ready")
                await ready()
                if let root = mainWindow?.contentView, let outline = views(TaskOutlineView.self, in: root).first {
                    scroll(toTopOf: outline, below: Metric.skyHeight / 4)
                }
            },
            Page(name: "cockpit-search") { model in
                reset(model)
                model.search = "cdn"
            },
            Page(name: "cockpit-banner") { model in
                reset(model)
                model.problem = .ghosttyAccess
            },
            Page(name: "cockpit-empty") { model in
                reset(model)
                model.search = "zzzz"
            },
            // The seed's biggest team open over the cards under it and Files, one of its rows selected.
            Page(name: "cockpit-team") { model in
                reset(model)
                model.openTeam = seedTeam(model)
                if let lead = model.openTeam, let row = model.team(of: lead).first {
                    model.selectSection(.sessions)
                    model.selectedSession = row.session.id
                }
                await ready()
                if let root = mainWindow?.contentView, let grid = views(SessionGrid.GridView.self, in: root).first { scroll(toTopOf: grid, below: Metric.skyHeight / 4) }
            },
            // Two drags at once, through AppKit's own drop path, to see both: a session over the second card (its ring) and
            // over the top of the open team's third row (the line among its rows).
            Page(name: "cockpit-drop") { model in
                reset(model)
                await dragScene(model) { grid, team, rows, loose in
                    if let row = team.rowFrame(rows[2]) { hover(team, loose, from: grid, at: NSPoint(x: row.midX, y: row.minY + 2)) }
                    if let card = grid.item(at: IndexPath(item: 1, section: 0))?.view.frame { hover(grid, loose, from: grid, at: NSPoint(x: card.midX, y: card.midY)) }
                }
            },
            // At the user's zoom: its first row's ring, and the line where it lands before the first card, past the grid's edge.
            Page(name: "cockpit-drop-team") { model in
                reset(model)
                model.zoom = 1.15
                await dragScene(model) { grid, team, rows, loose in
                    if let row = team.rowFrame(rows[0]) { hover(team, loose, from: grid, at: NSPoint(x: row.midX, y: row.midY)) }
                    if let card = grid.item(at: IndexPath(item: 0, section: 0))?.view.frame {
                        let twoColumns = SessionGrid.columns(for: grid.frame.width) > 1
                        hover(grid, loose, from: grid, at: twoColumns ? NSPoint(x: card.minX + 4, y: card.midY) : NSPoint(x: card.midX, y: card.minY + 3))
                    }
                }
            },
            Page(name: "modal-task", capture: .sheet) { reset($0); $0.open(.task(13)) },
            // Its relations, then its subtasks as the list's cards (2026-11-10).
            Page(name: "modal-task-subtasks", capture: .sheet) { model in
                reset(model)
                model.open(.task(16))
                await ready()
                guard let sheet = mainWindow?.attachedSheet?.contentView,
                      let scroll = views(NSScrollView.self, in: sheet).max(by: { $0.documentView?.frame.height ?? 0 < $1.documentView?.frame.height ?? 0 }),
                      let document = scroll.documentView else { return }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(document.frame.height - scroll.contentView.bounds.height, 0)))
                scroll.reflectScrolledClipView(scroll.contentView)
            },
            // Its links at the window's end: a long Slack message cut at the end, a web address in the middle (T-429).
            Page(name: "modal-task-links", capture: .sheet) { model in
                reset(model)
                SeedData.linkEveryKind(model)
                model.open(.task(13))
                await ready()
                guard let sheet = mainWindow?.attachedSheet?.contentView,
                      let scroll = views(NSScrollView.self, in: sheet).max(by: { $0.documentView?.frame.height ?? 0 < $1.documentView?.frame.height ?? 0 }),
                      let document = scroll.documentView else { return }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(document.frame.height - scroll.contentView.bounds.height, 0)))
                scroll.reflectScrolledClipView(scroll.contentView)
            },
            Page(name: "modal-task-edit", capture: .sheet) { model in
                reset(model)
                model.open(.task(13))
                model.editDescription(13)
            },
            Page(name: "modal-notifications", capture: .sheet) { reset($0); $0.openCenter() },
            Page(name: "modal-reminder", capture: .sheet) { model in
                reset(model)
                SlackClipboard.testText = nil
                SlackClipboard.testChange += 1
                model.beginReminder()
            },
            Page(name: "modal-new-task", capture: .sheet) { model in
                reset(model)
                SlackClipboard.testText = nil
                SlackClipboard.testChange += 1
                model.beginTask(.overview)
            },
            Page(name: "modal-new-file", capture: .sheet) { reset($0); $0.beginNewFile() },
            Page(name: "modal-import-artifact", capture: .sheet) { reset($0); $0.beginImport() },
            // A Slack link copied before New Reminder… and New Task… (T-313).
            Page(name: "modal-reminder-slack", capture: .sheet) { model in
                reset(model)
                copySlackLink()
                model.beginReminder()
            },
            // Remind Me… on a task (T-343): linked, named after it; the copied Slack link stays out.
            Page(name: "modal-remind-task", capture: .sheet) { model in
                reset(model)
                copySlackLink()
                model.beginReminder(about: .task(13))
            },
            Page(name: "modal-new-task-slack", capture: .sheet) { model in
                reset(model)
                copySlackLink()
                model.beginTask(.overview)
            },
            Page(name: "modal-caught-up", capture: .sheet) { model in
                reset(model)
                model.sessions = model.sessions.filter { !$0.status.needsYou }
                model.notices = model.notices.filter { $0.dueAt != nil }
                model.beginReminder()
            },
            Page(name: "modal-notifications-selected", capture: .sheet) { model in
                reset(model)
                model.openCenter()
                model.noticeSelection = model.notices(in: .updates).max { $0.text.count < $1.text.count }?.id.uuidString
            },
            // Cards (T-458): a long one cut at three lines with its toggle and links on one line, another shown in full.
            Page(name: "modal-notifications-long", capture: .sheet) { model in
                reset(model)
                let text = "The retry budget lands in #418: one budget per upload, shared by its parts, so a slow part can't starve the others. "
                    + "The canary ran for 30 minutes on eu-west with no 503 storm, p99 complete time down from 41 s to 6 s. Three things to check "
                    + "before merging: the jitter on small uploads, the metrics names, and whether the budget should be per tenant."
                let links = ["task:13", "task:44", "task:53", "file:2026-11-04 - Retry budget plan.md", "github:https://github.com/acme/registry/pull/418"]
                let cut = model.notify(text, level: .important, source: "250a8563-5c74-4592-a463-b41398dc5b55", links: links)
                let full = model.notify(text, level: .update, source: "83b6ab7a-8155-40ac-b149-16e2b8313b81", links: Array(links.prefix(2)))
                model.expandedNotices = [full.id.uuidString]
                model.noticeSelection = cut.id.uuidString
                model.openCenter()
            },
            Page(name: "modal-session-question", capture: .sheet) { reset($0); $0.open(.session("250a8563-5c74-4592-a463-b41398dc5b55")) },
            Page(name: "modal-session-plan", capture: .sheet) { reset($0); $0.open(.session("83b6ab7a-8155-40ac-b149-16e2b8313b81")) },
            Page(name: "modal-file", capture: .sheet) { model in reset(model); if let file = model.files.first { model.open(.file(file.id)) } },
            Page(name: "modal-file-edit", capture: .sheet) { model in
                reset(model)
                if let file = model.files.first { model.open(.file(file.id)); model.beginFileEdit(file.id) }
            },
            Page(name: "modal-artifact", capture: .sheet) { model in reset(model); if let artifact = model.artifacts.first { model.open(.artifact(artifact.id)) } },
            Page(name: "modal-pr", capture: .sheet) { reset($0); $0.open(.github(pr)) },
            Page(name: "modal-review", capture: .sheet) { reset($0); $0.open(.github("https://github.com/acme/static-cdn/pull/512")) },
            Page(name: "modal-start", capture: .sheet) { reset($0); $0.beginStart(task: 13) },
            Page(name: "modal-closed", capture: .sheet) { reset($0); $0.open(.closedSessions) },
            // Teams and roles (T-408, T-415, T-411): the form from a team's lead, Roles, a role's text edited, a lead's window,
            // a team closed together.
            Page(name: "modal-start-child", capture: .sheet) { model in
                reset(model)
                if let lead = seedTeam(model) { model.beginStart(parent: lead) }
            },
            Page(name: "modal-start-history", capture: .sheet) { model in
                reset(model)
                if let lead = seedTeam(model), let worker = model.team(of: lead).last?.session.id { model.beginStart(history: worker) }
            },
            Page(name: "modal-roles", capture: .sheet) { reset($0); $0.openRoles("Leader") },
            // At the user's zoom, used by every seed session: its Used by wraps onto three lines (T-451).
            Page(name: "modal-roles-zoom", capture: .sheet) { model in
                reset(model)
                model.zoom = 1.15
                let names = ["T-201 Map region filter", "T-302 Retry loop", "T-304/305 Pooled buffers", "T-363 Token only to registry",
                             "T-310 Logs everywhere", "T-467 HQ v15"]
                for (var session, name) in zip(model.sessions.filter(\.isRunning), names) {
                    session.role = "Worker"
                    session.customName = name
                    model.put(session)
                }
                model.openRoles("Worker")
            },
            Page(name: "modal-roles-edit", capture: .sheet) { model in
                reset(model)
                model.openRoles("Worker")
                model.beginRoleEdit(.text)
            },
            Page(name: "modal-session-team", capture: .sheet) { model in
                reset(model)
                if let lead = seedTeam(model) { model.open(.session(lead)) }
            },
            Page(name: "modal-closed-team", capture: .sheet) { model in
                reset(model)
                if let lead = seedTeam(model) {
                    for id in [lead] + model.team(of: lead).map(\.session.id) {
                        guard var item = model.session(id) else { continue }
                        var live = item.live
                        live.end(.now)
                        item.live = live
                        item.pid = nil
                        item.closedAt = .now
                        model.put(item)
                    }
                }
                model.open(.closedSessions)
            },
            Page(name: "modal-back", capture: .sheet) { model in
                reset(model)
                model.open(.task(13))
                model.open(.session("ef032aac-66d1-4b82-b6e1-03b8ee32dc93"), push: true)
            },
            Page(name: "quickopen", capture: .quickOpen) { model in
                reset(model)
                AppDelegate.shared?.toggleQuickOpen()
                model.quickOpenQuery = "retry"
            },
            Page(name: "setup", capture: .sheet) { reset($0); $0.showSetup = true },
        ]
    }

    /// The page's scroll view, scrolled to a share of its height.
    private static func scroll(to share: CGFloat) {
        guard let root = mainWindow?.contentView,
              let scroll = views(NSScrollView.self, in: root).max(by: { $0.documentView?.frame.height ?? 0 < $1.documentView?.frame.height ?? 0 }),
              let document = scroll.documentView else { return }
        let top = -scroll.contentView.contentInsets.top
        let y = top + max(0, (document.frame.height - scroll.contentView.bounds.height - top) * share)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private static func scrollToBottom() { scroll(to: 1) }

    /// The page scrolled so a view's top sits `below` points under the window's content top.
    private static func scroll(toTopOf view: NSView, below: CGFloat) {
        guard let root = mainWindow?.contentView,
              let scroll = views(NSScrollView.self, in: root).max(by: { $0.documentView?.frame.height ?? 0 < $1.documentView?.frame.height ?? 0 }),
              let document = scroll.documentView else { return }
        let frame = view.convert(view.bounds, to: document)
        let top = -scroll.contentView.contentInsets.top
        let y = (document.isFlipped ? frame.minY : document.frame.height - frame.maxY) + top - below
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(top, y), document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// The seed's biggest team: its top session.
    private static func seedTeam(_ model: AppModel) -> String? {
        model.gridRoots.max { model.team(of: $0.id).count < model.team(of: $1.id).count }.flatMap { model.team(of: $0.id).isEmpty ? nil : $0.id }
    }

    /// The seed's biggest team open, its card in view, and a session with no team to drag over the grid and its rows.
    private static func dragScene(_ model: AppModel, _ hovers: (SessionGrid.CardCollection, TeamCardView, [String], String) -> Void) async {
        model.openTeam = seedTeam(model)
        await ready()
        await until { mainWindow?.contentView.map { views(TeamCardView.self, in: $0).contains { $0.content?.open == true } } ?? false }
        guard let lead = model.openTeam, let root = mainWindow?.contentView, let grid = views(SessionGrid.CardCollection.self, in: root).first,
              let team = views(TeamCardView.self, in: root).first, case let rows = model.team(of: lead).map(\.session.id), rows.count > 2,
              let loose = model.gridRoots.last(where: { $0.isRunning && $0.id != lead && model.team(of: $0.id).isEmpty })?.id else {
            return fail("a drag page: no open team and loose session")
        }
        if let page = views(SessionGrid.GridView.self, in: root).first { scroll(toTopOf: page, below: Metric.skyHeight / 4) }
        hovers(grid, team, rows, loose)
    }

    /// A dragged session held over a point of a view, as AppKit hands a drag to it.
    private static func hover(_ view: NSView, _ id: String, from source: NSView, at point: NSPoint) {
        let drag = FakeDrag(session: id, source: source, at: view.convert(point, to: nil))
        _ = (view as NSDraggingDestination).draggingEntered?(drag)
        _ = (view as NSDraggingDestination).draggingUpdated?(drag)
    }

    /// A selected outline row, to see its fill.
    private static func select(task id: Int) {
        guard let root = mainWindow?.contentView, let outline = views(TaskOutlineView.self, in: root).first,
              let coordinator = outline.coordinator else { return }
        let row = outline.row(forItem: coordinator.node(.task(id)))
        if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
    }

    private static func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Each line reaches the log at once: the watchdog judges a pass by it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            await until(5) { mainWindow != nil }
            await ready()
            guard let main = mainWindow else {
                print("SNAPSHOT no window")
                NSApp.terminate(nil)
                return
            }

            if KitGallery.enabled {
                resize(main, to: CGSize(width: 1504, height: 1662)) // grid: ok real half-screen size
                let name = KitGallery.mode == "faces" ? "faces" : "gallery"
                for mode in ["light", "dark"] {
                    appearance(mode)
                    await ready()
                    capture(main, to: "\(dir)/\(name)-\(mode).png")
                }
                finish(dir)
                return
            }

            let modes = env["APP_SNAPSHOT_MODES"].map { $0.split(separator: ",").map(String.init) } ?? ["light", "dark"]
            for size in sizes {
                resize(main, to: size)
                for mode in modes {
                    appearance(mode)
                    for page in pages(model) where only?.contains(page.name) ?? true {
                        // A page that showed the sidebar in a narrow window grew it: back to this size.
                        if main.frame.width != size.width { resize(main, to: size) }
                        let gone = goneShown
                        await page.configure(model)
                        if page.capture == .sheet { await until { main.attachedSheet != nil } }
                        await ready()
                        let path = "\(dir)/\(page.name)-\(Int(size.width))-\(mode).png"
                        if page.capture == .sheet, main.attachedSheet == nil { fail("\(path): its sheet never opened") }
                        if goneShown != gone { fail("\(path): its sheet shows This Item Is Gone") }
                        switch page.capture {
                        case .window:
                            if env["APP_DEBUG_TOOLBAR"] == "1" { debugToolbar(main, "\(page.name) \(Int(size.width))") }
                            capture(main, to: path)
                        case .sheet, .quickOpen: captureRegion(of: main, to: path)
                        }
                        if page.capture == .quickOpen { AppDelegate.shared?.quickOpenPanel.dismiss() }
                        if page.capture == .sheet {
                            model.showSetup = false
                            model.closeModal()
                            await until { main.attachedSheet == nil }
                        }
                    }
                }
            }

            // APP_SNAPSHOT_SETTINGS=0: a pass that leaves Settings to another.
            if only == nil && env["APP_SNAPSHOT_SETTINGS"] != "0" || only?.contains("settings") == true {
                openSettings()
                await until { settingsWindow(besides: main) != nil }
                for mode in ["light", "dark"] {
                    appearance(mode)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        await ready()
                        let path = "\(dir)/settings-\(tab.rawValue)-\(mode).png"
                        if let settings = settingsWindow(besides: main) { capture(settings, to: path) } else { fail("\(path): no Settings window") }
                    }
                }
            }
            finish(dir)
        }
    }

    /// APP_DEBUG_TOOLBAR=1: which toolbar items show, and which went to the overflow menu.
    private static func debugToolbar(_ window: NSWindow, _ name: String) {
        guard let toolbar = window.toolbar else { return }
        let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier))
        let items = toolbar.items.map { item in
            "\(item.itemIdentifier.rawValue) \(item.label)\(visible.contains(item.itemIdentifier) ? "" : " [hidden]")"
        }
        FileHandle.standardError.write(Data("TOOLBAR \(name): \(items.joined(separator: " | "))\n".utf8))
        // What's really drawn: every button in the title bar, left to right.
        func buttons(_ view: NSView) -> [NSView] {
            let name = String(describing: Swift.type(of: view))
            return (name.contains("ItemViewer") || name.contains("Overflow") || view is NSButton ? [view] : []) + view.subviews.flatMap(buttons)
        }
        let frame = window.contentView?.superview
        let drawn = frame.map(buttons)?.filter { !$0.isHiddenOrHasHiddenAncestor && $0.frame.height < 60 }
            .map { ($0.convert($0.bounds, to: nil).minX, "\(Swift.type(of: $0)) \($0.accessibilityLabel() ?? $0.accessibilityIdentifier())") }
            .sorted { $0.0 < $1.0 }
            .map { "\(Int($0.0)): \($0.1)" } ?? []
        FileHandle.standardError.write(Data("DRAWN \(name): \(drawn.joined(separator: " | "))\n".utf8))
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && !$0.isSheet && !($0 is NSPanel) }
    }

    /// Pages that showed This Item Is Gone: a page that names an item the seed doesn't have.
    static var goneShown = 0
    private static var failures = 0

    /// A page that isn't what it says: the run ends with exit code 1.
    private static func fail(_ why: String) {
        failures += 1
        print("SNAPSHOT FAIL \(why)")
    }

    /// Waits until a page is ready to capture: no diagram drawing, no web view loading, and every window held still.
    private static func ready() async {
        await until(4) { MermaidRenderer.shared.drawing == 0 && !NSApp.windows.contains { $0.isVisible && webLoading($0.contentView) } }
        await Driver.holdStill(2)
    }

    private static func until(_ seconds: Double = 2, _ done: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(seconds)
        while !done(), Date.now < deadline { try? await Task.sleep(for: .milliseconds(16)) }
    }

    private static func webLoading(_ view: NSView?) -> Bool {
        guard let view else { return false }
        if let web = view as? WKWebView { return web.isLoading }
        return view.subviews.contains { webLoading($0) }
    }

    private static func settingsWindow(besides main: NSWindow) -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.canBecomeKey && !($0 is NSPanel) }
    }

    private static func finish(_ dir: String) {
        print(failures == 0 ? "SNAPSHOT done \(dir)" : "SNAPSHOT FAIL \(failures) pages in \(dir)")
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        if failures > 0 { Prefs.forget(); exit(1) }
        NSApp.terminate(nil)
    }

    private static func appearance(_ mode: String) {
        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
    }

    /// Puts the window at the given size on the top right of the second screen when there is one, no taller than it.
    private static func resize(_ window: NSWindow, to size: CGSize) {
        let screen = (Store.testScreen ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let height = min(size.height, screen.height)
        window.setFrame(NSRect(x: screen.maxX - size.width, y: screen.maxY - height, width: size.width, height: height), display: true)
    }

    /// Captures one window with screencapture, so glass and sidebars look as on screen.
    /// Needs Screen Recording permission for the app that started this one.
    /// In the background (the default) the window stays behind the user's and looks inactive; HQ_FOREGROUND=1 captures it as the key window.
    private static func capture(_ window: NSWindow, to path: String) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        if Store.background {
            window.orderBack(nil)
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        writeLayout(window, path)
        run(["-x", "-o", "-l", String(window.windowNumber), path], path: path, fallback: window)
    }

    /// Captures the window's area of the screen, to include a sheet or Quick Open over it.
    /// In the background that area shows the user's windows, so it captures the sheet, panel or popover alone.
    private static func captureRegion(of window: NSWindow, to path: String) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        if Store.background {
            let overlay = window.attachedSheet ?? NSApp.windows
                .filter { $0 !== window && $0.isVisible && $0.frame.intersects(window.frame) }
                .max { $0.level.rawValue < $1.level.rawValue }
            writeLayout(window, path)
            run(["-x", "-o", "-l", String((overlay ?? window).windowNumber), path], path: path, fallback: overlay ?? window)
            return
        }
        writeLayout(window, path)
        let top = NSScreen.screens.first?.frame.height ?? 0
        let frame = window.frame
        let rect = "\(Int(frame.minX)),\(Int(top - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
        run(["-x", "-R", rect, path], path: path, fallback: nil)
    }

    /// The grid's probes, at 100% only: zoomed sizes leave the 4 pt grid on purpose.
    private static func writeLayout(_ window: NSWindow, _ path: String) {
        let layout = path.replacingOccurrences(of: ".png", with: "-layout.json")
        guard Zoom.factor == 1 else { try? FileManager.default.removeItem(atPath: layout); return }
        GridProbes.shared.write(to: layout, window: window.contentView?.bounds.size ?? .zero)
    }

    private static func run(_ arguments: [String], path: String, fallback: NSWindow?) {
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = arguments
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let window = fallback, let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fail("\(path): the capture failed")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
