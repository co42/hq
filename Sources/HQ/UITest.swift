import AppKit
import HQKit
import SwiftUI

/// UI test: drives a test copy of HQ with key and mouse events posted to its own window, as a
/// person would, and checks what happened. Needs no Accessibility permission, and test runs
/// never reach Ghostty. Prints PASS or FAIL per check and quits with 0 or 1.
///   tools/uitest.sh   (APP_STORE and HQ_VAULT in /tmp, then HQ --uitest)
enum UITest {
    static var requested: Bool { CommandLine.arguments.contains("--uitest") }
    /// The views the test clicks.
    /// Every probe by name: a sheet on its way out may still hold one beside the live window's.
    static var anchors: [String: [WeakView]] = [:]

    static func register(_ name: String, _ view: NSView) {
        var probes = anchors[name, default: []].filter { $0.view != nil && $0.view !== view }
        probes.append(WeakView(view: view))
        anchors[name] = probes
    }
    /// UITEST_VERBOSE=1: where each click lands.
    static let verbose = ProcessInfo.processInfo.environment["UITEST_VERBOSE"] == "1"
    private static var failures = 0
    private static var count = 0
    private static var skipped = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        let vault = ProcessInfo.processInfo.environment["HQ_VAULT"] ?? ""
        guard Store.isOverridden, vault.hasPrefix("/tmp/") || vault.hasPrefix("/private/tmp/") else {
            print("UITEST refused: set APP_STORE and HQ_VAULT to paths in /tmp")
            SelfTest.finish(code: 1)
            return
        }
        // No App Nap or timer coalescing while it runs: the timings measure HQ, not a napping app.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "UI test")
        Task {
            defer { ProcessInfo.processInfo.endActivity(activity) }
            // AppDelegate opens the window of a test run that has none.
            for _ in 0..<10 where model.window == nil {
                try? await Task.sleep(for: .seconds(0.5))
            }
            guard let window = model.window else {
                check("the main window opened", false)
                SelfTest.finish(code: 1)
                return
            }
            try? await Task.sleep(for: .seconds(1))
            Driver.front(window)
            try? await Task.sleep(for: .seconds(0.5))
            if verbose { print("  responder: \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"), active: \(NSApp.isActive), key: \(window.isKeyWindow), front: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")") }
            let ui = Driver(window: window, model: model)
            SeedData.fill(model, now: .now)
            // Seed tasks and files have no notes: each check makes its own in the test vault.
            model.tasks = []
            model.files = []
            await ui.settle(0.5)
            check("HQ opens on the cockpit", ui.window.contentView != nil)
            // UITEST_ONLY=a,b runs those groups alone.
            let only = ProcessInfo.processInfo.environment["UITEST_ONLY"].flatMap { $0.isEmpty ? nil : Set($0.split(separator: ",").map(String.init)) }
            let groups: [(String, @MainActor (AppModel, Driver) async -> Void)] = [
                ("idle", idle), ("grid", grid), ("pageSelection", pageSelection), ("outlineKeys", outlineKeys), ("outlineDrops", outlineDrops),
                ("outlineLooks", outlineLooks), ("modal", modal), ("performance", performance), ("lateChecks", lateChecks),
                ("foldedParentOpens", foldedParentOpens), ("disclosures", disclosures), ("singleSessionFace", singleSessionFace), ("prFaces", prFaces), ("notificationCenter", notificationCenter), ("rowControls", rowControls), ("typingKeepsRows", typingKeepsRows), ("menuBar", menuBar), ("copyAndRemind", copyAndRemind),
                ("slackLinks", slackLinks),
            ]
            for (name, run) in groups where only?.contains(name) ?? true {
                await run(model, ui)
                hitSweep(ui, after: name)
            }
            if Store.background { check("the test copy never took the focus", Store.stolenFocus == 0, "activated \(Store.stolenFocus) times") }

            let skips = skipped == 0 ? "" : ", \(skipped) skipped"
            print(failures == 0 ? "UITEST PASS \(count) checks\(skips)" : "UITEST FAIL \(failures) of \(count) checks\(skips)")
            SelfTest.finish(code: failures == 0 ? 0 : 1)
        }
    }

    // MARK: Checks

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// A click on an AppKit table: macOS hands it over only while HQ is the active app.
    static func tableCheck(_ ui: Driver, _ name: String, _ ok: Bool, _ detail: String = "") {
        if ui.canClickTables { check(name, ok, detail) } else { skip(name) }
    }

    /// Every clickable on screen sits inside each of its containers: one laid out past its container takes no clicks (T-207, T-255).
    static func hitSweep(_ ui: Driver, after group: String) {
        let windows = [ui.window, ui.window.attachedSheet].compactMap { $0 }
        var views: [(String, NSView)] = anchors.flatMap { name, probes in probes.compactMap(\.view).map { (name, $0) } }
        func collect(_ view: NSView) {
            if view is NSTableRowView || view is NSTableCellView || view is NSControl || view is SessionGrid.CardView {
                views.append((String(describing: type(of: view)), view))
            }
            view.subviews.forEach(collect)
        }
        windows.compactMap(\.contentView).forEach(collect)
        var outside: [String] = []
        var checked = 0
        for (name, view) in views where windows.contains(where: { $0 === view.window }) {
            guard !view.isHiddenOrHasHiddenAncestor, view.bounds.width > 1, view.bounds.height > 1 else { continue }
            checked += 1
            let center = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            var parent = view.superview
            while let container = parent, !(container is NSClipView || container is NSScrollView) {
                // SwiftUI's and AppKit's private hosts (`_NSGraphicsView`) may be smaller than what they host.
                let own = !String(describing: type(of: container)).hasPrefix("_")
                if own, !container.bounds.insetBy(dx: -1, dy: -1).contains(view.convert(center, to: container)) {
                    outside.append("\(name) outside its \(type(of: container))")
                    break
                }
                parent = container.superview
            }
        }
        check("after \(group), every clickable on screen sits inside its containers (\(checked))", outside.isEmpty,
              Set(outside).sorted().prefix(6).joined(separator: "; "))
    }

    static func skip(_ name: String) {
        skipped += 1
        print("SKIP \(name): " + (Store.background ? "a background run is never the active app (HQ_FOREGROUND=1 runs it)" : "HQ can't become the active app (is the screen locked?)"))
    }
}

/// Posts events to the window as the system would, and finds what to click.
@MainActor
struct Driver {
    let window: NSWindow
    let model: AppModel
    /// Room kept above and below what a test clicks: the toolbar and the section bar float over the page.
    static let overlayClearance: CGFloat = 160

    /// The window HQ's events go to. In the background it stays behind the user's windows and HQ stays inactive.
    static func front(_ window: NSWindow) {
        if Store.background {
            window.makeKey()
            window.orderBack(nil)
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    enum Key {
        case `return`, escape, up, down, left, right, delete, tab

        var characters: String {
            switch self {
            case .return: "\r"
            case .escape: "\u{1b}"
            case .delete: "\u{7f}"
            case .tab: "\t"
            case .up: String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)
            case .down: String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
            case .left: String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!)
            case .right: String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!)
            }
        }

        var code: UInt16 {
            switch self {
            case .return: 36
            case .escape: 53
            case .delete: 51
            case .tab: 48
            case .up: 126
            case .down: 125
            case .left: 123
            case .right: 124
            }
        }
    }

    func settle(_ seconds: Double = 0.2) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Waits until `done` holds, at most `seconds`, then a moment more for what follows it.
    func until(_ seconds: Double = 2, _ done: () -> Bool) async {
        var waited = 0.0
        while !done() && waited < seconds {
            await settle(0.1)
            waited += 0.1
        }
        await settle(0.2)
    }

    /// The middle of an anchored view, in its window's coordinates (the main window's or its sheet's).
    func anchor(_ name: String) -> NSPoint? {
        let probes = UITest.anchors[name, default: []].compactMap(\.view)
        guard let view = probes.last(where: { $0.window === window.attachedSheet && $0.window != nil }) ?? probes.last(where: { $0.window === window }) else {
            print("  (no anchor \(name))")
            return nil
        }
        // Clear of the toolbar and the section bar that float over the page, as the page lays out after a scroll.
        view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
        (view.window ?? window).layoutIfNeeded()
        let frame = view.convert(view.bounds, to: nil)
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    /// An anchor once it stops moving: a sheet that just opened still slides in.
    func steadyAnchor(_ name: String, within seconds: Double = 1.5) async -> NSPoint? {
        var last = anchor(name)
        var waited = 0.0
        while waited < seconds {
            await settle(0.1)
            waited += 0.1
            let next = anchor(name)
            if next == last { return next }
            last = next
        }
        return last
    }

    /// An anchored view's frame in its window.
    func anchorFrame(_ name: String) -> NSRect? {
        guard let view = UITest.anchors[name, default: []].compactMap(\.view).last(where: { $0.window != nil }) else { return nil }
        view.window?.layoutIfNeeded()
        return view.convert(view.bounds, to: nil)
    }

    /// A click on an anchor in a popover's own window, as that window gets it. Nil when no popover shows it.
    /// The window of the popover that shows `name`.
    func popoverWindow(_ name: String) -> NSWindow? {
        UITest.anchors[name, default: []].compactMap(\.view)
            .last(where: { $0.window != nil && $0.window !== window && $0.window !== window.attachedSheet })?.window
    }

    /// A key typed in the popover that shows `name`, as its text field gets it.
    func key(_ key: Key, inPopover name: String) async {
        guard let popover = popoverWindow(name) else { return }
        let arrows: NSEvent.ModifierFlags = [.up, .down, .left, .right].contains(key) ? [.numericPad, .function] : []
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: arrows, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: popover.windowNumber, context: nil, characters: key.characters,
                                               charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.code) else { continue }
            popover.sendEvent(event)
        }
        await settle(0.2)
    }

    func clickInPopover(_ name: String) async -> Bool {
        guard let view = UITest.anchors[name, default: []].compactMap(\.view)
            .last(where: { $0.window != nil && $0.window !== window && $0.window !== window.attachedSheet }),
            let popover = view.window else { return false }
        popover.layoutIfNeeded()
        let frame = view.convert(view.bounds, to: nil)
        let point = NSPoint(x: frame.midX, y: frame.midY)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: popover.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                               pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return false }
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
        await settle(0.4)
        return true
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for child in view.subviews { if let match = find(type, in: child) { return match } }
        return nil
    }

    /// The mouse-up waits in the queue while the window handles the mouse-down, as AppKit's
    /// tracking loops (tables, outlines) expect.
    func click(_ point: NSPoint?, count: Int = 1, flags: NSEvent.ModifierFlags = [], inSheet: Bool = false) async {
        guard let point else { return }
        let target = inSheet ? window.attachedSheet ?? window : window
        if UITest.verbose {
            let hit = hitView(point, in: target)
            let probe = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: target.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            print("  click at \(Int(point.x)),\(Int(point.y)) on \(hit.map { String(describing: Swift.type(of: $0)) } ?? "nothing"), first mouse: \(hit?.acceptsFirstMouse(for: probe) ?? false), key: \(window.isKeyWindow)")
        }
        for click in 1...count {
            func event(_ type: NSEvent.EventType) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: target.windowNumber, context: nil, eventNumber: 0, clickCount: click,
                                   pressure: type == .leftMouseDown ? 1 : 0)
            }
            guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { continue }
            // Active, the press and the release go through the queue as a real click does: views read it as the current event.
            // A real click activates HQ before AppKit delivers it to a view that accepts the first
            // mouse. While HQ can't be active (a locked screen), a table gets the click directly.
            if NSApp.isActive {
                NSApp.postEvent(down, atStart: false)
                NSApp.postEvent(up, atStart: false)
            } else if let hit = hitView(point, in: target), hit.acceptsFirstMouse(for: down),
                      let table = sequence(first: hit, next: \.superview).first(where: { $0 is NSTableView }) {
                NSApp.postEvent(up, atStart: false)
                table.mouseDown(with: down)
            } else {
                NSApp.postEvent(up, atStart: false)
                NSApp.sendEvent(down)
            }
            await settle(0.05)
        }
        await settle(0.3)
    }

    /// A right-click, as the window gets it.
    func rightClick(_ point: NSPoint?) async {
        guard let point else { return }
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                               pressure: type == .rightMouseDown ? 1 : 0)
        }
        guard let down = event(.rightMouseDown), let up = event(.rightMouseUp) else { return }
        if NSApp.isActive {
            NSApp.postEvent(down, atStart: false)
            NSApp.postEvent(up, atStart: false)
        } else {
            NSApp.postEvent(up, atStart: false)
            NSApp.sendEvent(down)
        }
        await settle(0.3)
    }

    /// `held`: a repeat, as a key held down sends.
    func key(_ key: Key, _ flags: NSEvent.ModifierFlags = [], held: Bool = false) async {
        let arrows: NSEvent.ModifierFlags = [.up, .down, .left, .right].contains(key) ? [.numericPad, .function] : []
        // Shift-Tab types the backtab character.
        let characters = key == .tab && flags.contains(.shift) ? String(UnicodeScalar(UInt8(0x19))) : key.characters
        await self.key(characters, flags.union(arrows), code: key.code, held: held)
    }

    func key(_ characters: String, _ flags: NSEvent.ModifierFlags = [], code: UInt16? = nil, held: Bool = false) async {
        let codes: [String: UInt16] = ["\r": 36, " ": 49, "n": 45, "[": 33]
        let code = code ?? codes[characters] ?? 0
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            post(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: held, keyCode: code))
        }
        await settle(0.05)
    }

    func type(_ text: String) async {
        for character in text { await key(String(character)) }
    }

    /// Go › Back: ⌘[ in the key window; a background run's window is never key, so its menus are
    /// off, and the modal's Back button stands in.
    func back() async {
        if window.isKeyWindow {
            await key("[", .command)
        } else {
            await click(anchor("modal-back"), inSheet: true)
        }
    }

    /// A click into a text view; a text view in a window that isn't key ignores it, so a background
    /// run gives it the keyboard directly.
    func focusText(_ point: NSPoint?) async {
        guard let point else { return }
        if window.isKeyWindow && NSApp.isActive {
            await click(point)
        } else if let text = hitView(point) as? NSTextView {
            window.makeFirstResponder(text)
            await settle()
        } else if let field = hitView(point) as? NSTextField {
            window.makeFirstResponder(field)
            await settle()
        }
    }

    private func post(_ event: NSEvent?) {
        if let event { NSApp.postEvent(event, atStart: false) }
    }

    /// A text field or text view is taking the keys.
    /// The view a click at `point` (window coordinates) lands on.
    /// The view under a point of `target` (the window by default): a click meant for a sheet tests the sheet, never the
    /// window under it.
    func hitView(_ point: NSPoint, in target: NSWindow? = nil) -> NSView? {
        (target ?? window).contentView?.superview?.hitTest(point)
    }

    /// True when the view under the anchor takes the click that activates the window.
    func takesFirstClick(_ point: NSPoint?) -> Bool {
        guard let point, let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                        clickCount: 1, pressure: 1) else { return false }
        return hitView(point)?.acceptsFirstMouse(for: event) ?? false
    }

    /// AppKit tables take synthetic clicks only in the active app.
    var canClickTables: Bool { NSApp.isActive }

    var isTyping: Bool { window.firstResponder is NSText }
    var responder: String { window.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "none" }
}

extension View {
    /// Where the UI test clicks: the view's frame, recorded only in a --uitest run.
    func uiTestAnchor(_ name: String) -> some View {
        modifier(UITestAnchor(name: name))
    }
}

private struct UITestAnchor: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        if UITest.requested {
            content.background(AnchorView(name: name))
        } else {
            content
        }
    }
}

/// An AppKit view behind the anchored one, measured when the test clicks: it works in rows that
/// an AppKit table hosts, and after scrolling.
private struct AnchorView: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.name = name
        UITest.register(name, view)
    }

    final class Probe: NSView {
        var name = ""
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { UITest.register(name, self) }
        }
    }
}

struct WeakView {
    weak var view: NSView?
}
