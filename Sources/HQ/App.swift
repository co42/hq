import AppKit
import SwiftUI
import ServiceManagement

// HQ
//   HQ                       the app
//   hq <command>             the CLI (Agent/), talking to the running app
//   APP_STORE=<file> HQ      use another store and socket (tests, experiments)
//   APP_SNAPSHOT=<dir> HQ    save PNGs of every screen in light and dark, at 1504 and 756 pt wide, then quit
//   APP_SEED=1 HQ            fill a /tmp store with sample data (tools/snap.sh)
//   APP_KIT_GALLERY=1 HQ     show the parts gallery instead of the app
//   HQ --selftest            run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_GRID=1 HQ            draw the 8 pt grid and the layout probes over the window
//   APP_DEBUG_TOOLBAR=1      with APP_SNAPSHOT: print which toolbar items show and which went to the overflow menu

struct HQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var menu = MenuState.shared

    var body: some Scene {
        Window("HQ", id: "main") {
            RootView()
            .environment(delegate.model)
            .overlay { if GridOverlay.enabled { GridOverlay() } }
            .frame(minWidth: Metric.windowMin.width, minHeight: Metric.windowMin.height)
            .noInitialFocus()
            .background(WindowAccessor { delegate.adopt($0) })
        }
        .defaultWindowPlacement { _, context in
            // First launch: the right half of the main display, full height.
            let screen = context.defaultDisplay.visibleRect
            return WindowPlacement(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)
        }
        .windowToolbarStyle(.unified)
        .commands {
            HQCommands(model: delegate.model, menu: menu) { delegate.toggleQuickOpen() }
        }

        Settings {
            SettingsView()
                .environment(delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    /// SwiftUI owns NSApp.delegate, so reach this one here.
    private(set) static weak var shared: AppDelegate?
    private weak var mainWindow: NSWindow?
    private lazy var quickOpen = QuickOpenPanel(model: model)
    private var keyMonitor: Any?
    private var editorObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLog.mark("launched")
        Self.shared = self
        SessionFace.doubleClick = { [weak model] id in model?.openFace(id) }
        SessionFace.click = { [weak model] id, view in if let menu = model?.faceMenu(id) { FaceMenu.showUnder(view, menu, id) } }
        // The socket lives with the app, not the window: hooks reach HQ even while its window is closed.
        AgentRouter.model = model
        AgentSocket.listen { AgentRouter.handle($0) }
        // What sessions did while HQ was off; again a moment later for a hook that just missed the socket.
        model.replayPendingHooks()
        Task { [weak model] in
            try? await Task.sleep(for: .seconds(3))
            model?.replayPendingHooks()
        }
        // The plugin, Ghostty access and the vault: the setup sheet until all three are ready.
        if !Store.isOverridden {
            model.checkSetup()
            model.showSetup = !model.setup.isComplete
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.checkSetup() }
            }
            MenuBarIcon.shared.show(menu: NSHostingMenu(rootView: MenuBarMenu().environment(model)))
            // HQ opens at login, once set; Settings › General turns it off for good.
            if !Prefs.defaults.bool(forKey: "login.registered") {
                Prefs.defaults.set(true, forKey: "login.registered")
                if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
            }
        }
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(Store.background ? .accessory : .regular)
        openTestWindowIfMissing()
        UITest.runIfRequested(model: model)
        if Store.background {
            Store.keepInBackground()
        } else {
            NSApp.activate()
        }
        model.syncMenu()
        editorObserver = NotificationCenter.default.addObserver(forName: .editorKeyboard, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.syncMenu() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "p": self?.toggleQuickOpen()
            case "=": self?.model.zoom(by: 1)
            default: return event
            }
            return nil
        }
    }

    /// Beside a running HQ, SwiftUI doesn't open a test run's window at launch: Window › HQ does,
    /// so snapshots and tests run while the user's HQ stays open.
    private func openTestWindowIfMissing() {
        guard Store.isOverridden else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard model.window == nil else { return }
            let items = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
            if let item = items.first(where: { $0.title == "HQ" && $0.action != nil }), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
        }
    }

    /// HQ stays alive when its window closes: the hook socket keeps listening.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Quit and Restart HQ write what an editor holds and what the last second changed first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.saveForQuit()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.bringForward()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let newTask = NSMenuItem(title: "New Task…", action: #selector(dockNewTask), keyEquivalent: "")
        newTask.target = self
        menu.addItem(newTask)
        let reminder = NSMenuItem(title: "New Reminder…", action: #selector(dockNewReminder), keyEquivalent: "")
        reminder.target = self
        menu.addItem(reminder)
        let center = NSMenuItem(title: "Notifications", action: #selector(dockNotifications), keyEquivalent: "")
        center.target = self
        menu.addItem(center)
        return menu
    }

    @objc private func dockNewTask() {
        model.bringForward()
        model.beginTask(.overview)
    }

    @objc private func dockNewReminder() {
        model.bringForward()
        model.beginReminder()
    }

    @objc private func dockNotifications() {
        model.bringForward()
        model.openCenter()
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        model.settleActivity()
        model.saveSessionsNow()
        Prefs.forget()
        if SelfTest.requested || UITest.requested { exit(SelfTest.exitCode) }
    }

    func toggleQuickOpen() {
        quickOpen.toggle(over: mainWindow)
    }

    var quickOpenPanel: QuickOpenPanel { quickOpen }

    /// Hide the main window instead of closing it: closing and reopening a SwiftUI Window crashes AppKit on macOS 26.
    func adopt(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        LaunchLog.mark("window")
        model.window = window
        window.delegate = self
        if Store.isOverridden { Store.moveToTestScreen(window) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

/// Hands the hosting NSWindow to a closure once the view is in it.
struct WindowAccessor: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Probe()
        view.found = found
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        var found: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { self.found?(window) } }
        }
    }
}

/// Where HQ keeps its data: ~/Library/Application Support/HQ/. APP_STORE moves it (tests, snapshots).
/// HQ's preferences. A test, snapshot or preview run keeps its own, emptied at launch: it never reads or writes the
/// user's, nor another run's. HQ_PREFS=copy starts it from a copy of the user's (tools/preview.sh).
enum Prefs {
    static let defaults: UserDefaults = {
        guard Store.isOverridden else { return .standard }
        let suite = "io.github.co42.hq.test." + Store.url.deletingPathExtension().lastPathComponent
        guard let defaults = UserDefaults(suiteName: suite) else { return .standard }
        defaults.removePersistentDomain(forName: suite)
        if ProcessInfo.processInfo.environment["HQ_PREFS"] == "copy", let user = UserDefaults.standard.persistentDomain(forName: "io.github.co42.hq") {
            defaults.setPersistentDomain(user, forName: suite)
        }
        return defaults
    }()

    /// Removes a test run's preferences file as it quits.
    static func forget() {
        guard Store.isOverridden else { return }
        defaults.removePersistentDomain(forName: "io.github.co42.hq.test." + Store.url.deletingPathExtension().lastPathComponent)
    }
}

enum Store {
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    /// Test runs stay behind the user's windows, never take focus and have no Dock icon, unless HQ_FOREGROUND=1.
    static var background: Bool {
        isOverridden && ProcessInfo.processInfo.environment["HQ_FOREGROUND"] != "1"
    }

    /// How often a background run was activated anyway; each time it handed the focus straight back.
    static var stolenFocus = 0

    /// Where test runs put their window: the user's second screen when there is one, else nil.
    static var testScreen: NSScreen? { NSScreen.screens.dropFirst().first }

    /// A test run's window moves to the second screen when there is one, at its right edge, narrowed to fit it.
    static func moveToTestScreen(_ window: NSWindow) {
        guard let screen = NSScreen.screens.dropFirst().first?.visibleFrame else { return }
        let width = min(window.frame.width, screen.width)
        let height = min(window.frame.height, screen.height)
        window.setFrame(NSRect(x: screen.maxX - width, y: screen.maxY - height, width: width, height: height), display: false)
    }

    /// Windows go behind everyone else's as they appear and let clicks through, and an activation is undone at once.
    static func keepInBackground() {
        // The user's clicks go through a test window to their own, wherever it shows; the tests' events are posted in-process.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows where !window.ignoresMouseEvents { window.ignoresMouseEvents = true }
            }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                stolenFocus += 1
                NSApp.hide(nil)
                NSApp.unhideWithoutActivation()
                for window in NSApp.windows where window.isVisible { window.orderBack(nil) }
            }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { window?.orderBack(nil) }
        }
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return directory.appending(path: "HQ.store")
    }

    /// Where HQ keeps its files: Application Support, or beside a test store in /tmp.
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            let dir = URL(fileURLWithPath: path + ".d", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let dir = URL.applicationSupportDirectory.appending(path: "HQ", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The tasks' backup before the vault migration.
    static var backups: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }

    /// A file HQ can't read, renamed beside itself (`notifications.unreadable-20261111-0930.json`) so nothing writes
    /// over it; with its SQLite companions for the store. Nil when it couldn't be moved.
    static func moveAside(_ url: URL) -> URL? {
        let stamp = Date.now.formatted(.verbatim("\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
                                                 timeZone: .current, calendar: .current))
        let ext = url.pathExtension
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp)").appendingPathExtension(ext)
        guard (try? FileManager.default.moveItem(at: url, to: aside)) != nil else { return nil }
        for suffix in ["-shm", "-wal"] {
            try? FileManager.default.moveItem(atPath: url.path + suffix, toPath: aside.path + suffix)
        }
        AppLog.write("moved \(url.lastPathComponent) aside to \(aside.lastPathComponent): HQ couldn't read it", to: "store.log")
        return aside
    }
}

/// The main window's root: the app, or the parts gallery. Starts the socket, seed data, self-test and snapshots.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if KitGallery.enabled {
                KitGallery()
            } else {
                CockpitView()
            }
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }
}
