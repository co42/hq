import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents and review.
///   APP_STORE=/tmp/HQ-test.store APP_SEED=1 APP_SNAPSHOT=/tmp/HQ-shots HQ
/// writes <page>-<width>-<mode>.png for every page at 1504 and 756 pt wide (the two
/// half screens), settings-<tab>-<mode>.png, and a -layout.json next to each, then quits.
/// APP_SNAPSHOT_PAGES=sessions,tasks limits the pages; add "settings" for Settings.
/// APP_KIT_GALLERY=1 captures gallery-<mode>.png instead.
enum Snapshot {
    /// The two half-screen sizes HQ is designed for (DESIGN.md §3).
    static let sizes: [CGSize] = [CGSize(width: 1504, height: 1662), CGSize(width: 756, height: 950)] // grid: ok real half-screen sizes

    struct Page {
        enum Capture { case window, sheet, quickOpen }
        let name: String
        var capture = Capture.window
        /// Extra seconds before the capture: a Mermaid diagram draws once, in the background.
        var settle: Double = 0
        let configure: (AppModel) -> Void
    }

    static func pages(_ model: AppModel) -> [Page] {
        func reset(_ model: AppModel) {
            model.closeModal()
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
            scroll(to: 0)
        }
        let pr = "https://github.com/acme/registry/pull/418"
        return [
            Page(name: "cockpit", settle: 1) { reset($0) },
            Page(name: "cockpit-zoom", settle: 1.5) { model in
                reset(model)
                model.zoom = 1.3
            },
            Page(name: "cockpit-backlog", settle: 1) { model in
                reset(model)
                model.backlogOpen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scrollToBottom(); select(task: 36) }
            },
            Page(name: "cockpit-descriptions", settle: 1.5) { model in
                reset(model)
                model.allDescriptions = [.overview, .backlog]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { scroll(to: 0.45) }
            },
            Page(name: "cockpit-folded", settle: 1) { model in
                reset(model)
                model.folded = [.pullRequests, .files]
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
            Page(name: "modal-task", capture: .sheet, settle: 1.5) { reset($0); $0.open(.task(13)) },
            Page(name: "modal-notifications", capture: .sheet, settle: 1) { reset($0); $0.openCenter() },
            Page(name: "modal-reminder", capture: .sheet, settle: 1) { reset($0); $0.beginReminder() },
            Page(name: "modal-notifications-selected", capture: .sheet, settle: 1) { model in
                reset(model)
                model.openCenter()
                model.noticeSelection = model.notices(in: .updates).max { $0.text.count < $1.text.count }?.id.uuidString
            },
            Page(name: "modal-session-question", capture: .sheet) { reset($0); $0.open(.session("250a8563-5c74-4592-a463-b41398dc5b55")) },
            Page(name: "modal-session-plan", capture: .sheet, settle: 0.5) { reset($0); $0.open(.session("83b6ab7a-8155-40ac-b149-16e2b8313b81")) },
            Page(name: "modal-file", capture: .sheet, settle: 1.5) { model in reset(model); if let file = model.files.first { model.open(.file(file.id)) } },
            Page(name: "modal-file-edit", capture: .sheet, settle: 1.5) { model in
                reset(model)
                if let file = model.files.first { model.open(.file(file.id)); model.beginFileEdit(file.id) }
            },
            Page(name: "modal-artifact", capture: .sheet, settle: 1) { model in reset(model); if let artifact = model.artifacts.first { model.open(.artifact(artifact.id)) } },
            Page(name: "modal-pr", capture: .sheet, settle: 0.5) { reset($0); $0.open(.github(pr)) },
            Page(name: "modal-review", capture: .sheet, settle: 0.5) { reset($0); $0.open(.github("https://github.com/acme/static-cdn/pull/512")) },
            Page(name: "modal-start", capture: .sheet) { reset($0); $0.beginStart(task: 13) },
            Page(name: "modal-closed", capture: .sheet) { reset($0); $0.open(.closedSessions) },
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
            try? await Task.sleep(for: .seconds(1.5))
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
                    try? await Task.sleep(for: .seconds(1))
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
                        page.configure(model)
                        try? await Task.sleep(for: .seconds((page.capture == .window ? 0.8 : 1.2) + page.settle))
                        let path = "\(dir)/\(page.name)-\(Int(size.width))-\(mode).png"
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
                            try? await Task.sleep(for: .seconds(0.6))
                        }
                    }
                }
            }

            if only == nil || only?.contains("settings") == true {
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    appearance(mode)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet && $0.canBecomeKey && !($0 is NSPanel) }
                        if let settings { capture(settings, to: "\(dir)/settings-\(tab.rawValue)-\(mode).png") }
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

    private static func finish(_ dir: String) {
        print("SNAPSHOT done \(dir)")
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
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
            print("SNAPSHOT failed \(path)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
