import AppKit
import HQKit
import Synchronization

/// Ghostty through AppleScript (PLAN.md §2): focus the terminal a session runs in, or open a
/// tab that runs a command. HQ never owns a terminal.
/// Every script runs on one serial queue, and Ghostty has a few seconds to answer each call: a busy or hung Ghostty
/// fails the call, it never holds HQ. Call these off the main thread.
enum Ghostty {
    nonisolated static let bundleID = "com.mitchellh.ghostty"
    /// How long Ghostty has to answer an Apple event, in seconds.
    nonisolated static let timeout = 3

    enum Failure: Error, Equatable {
        /// Automation for Ghostty is off in System Settings.
        case notPermitted
        /// Ghostty didn't answer within `timeout`.
        case timedOut
        case script(String)
    }

    enum Access: Equatable {
        case allowed, denied, notAsked, notRunning
    }

    nonisolated static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Ghostty is the app in front.
    static var inFront: Bool {
        faked ? fake.withLock { $0.front } : NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Automation permission. With `ask`, macOS shows its prompt once; that call blocks, so run it off the main thread.
    nonisolated static func access(ask: Bool = false) -> Access {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notAsked
        }
    }

    /// Brings the terminal on `tty` forward. False when no Ghostty terminal has it.
    nonisolated static func focus(tty: String) throws(Failure) -> Bool {
        guard reachable else { return false }
        let result = try run("""
        tell application id "\(bundleID)"
            set found to every terminal whose tty is "\(escape(tty))"
            if (count of found) is 0 then return false
            focus (item 1 of found)
            activate
            return true
        end tell
        """, test: NSAppleEventDescriptor(boolean: true))
        return result.booleanValue
    }

    /// A new tab in the front window (or a new window) in `directory`, with `command` typed into
    /// the shell and run, so the shell stays when the command exits. Ghostty pastes `initial
    /// input`, and fish never runs a pasted newline: the command is typed, then Return is pressed.
    /// It waits for the shell to start: Ghostty gets longer to answer.
    nonisolated static func newTab(in directory: String, command: String) throws(Failure) {
        let path = (directory as NSString).expandingTildeInPath
        try run("""
        tell application id "\(bundleID)"
            set config to {initial working directory:"\(escape(path))"}
            if (count of windows) is 0 then
                set made to new window with configuration config
                set target to selected tab of made
            else
                set target to new tab in front window with configuration config
            end if
            set term to focused terminal of target
            delay 0.4
            input text "\(escape(command))" to term
            send key "enter" to term
            activate
        end tell
        """, timeout: 10)
    }

    /// Types text and Return into the terminal on `tty` (Close Session's `/exit`); with `interrupting`, Escape first and a
    /// moment for Claude to stop its turn. False when no Ghostty terminal has it.
    nonisolated static func type(_ text: String, tty: String, interrupting: Bool = false) throws(Failure) -> Bool {
        guard reachable else { return false }
        let escape = interrupting ? "send key \"escape\" to (item 1 of found)\n    delay 0.5\n" : ""
        return try run("""
        tell application id "\(bundleID)"
            set found to every terminal whose tty is "\(Self.escape(tty))"
            if (count of found) is 0 then return false
            \(escape)input text "\(Self.escape(text))" to (item 1 of found)
            send key "enter" to (item 1 of found)
            return true
        end tell
        """, test: NSAppleEventDescriptor(boolean: true)).booleanValue
    }

    /// Closes the terminal on `tty`: its tab goes with it when it was the tab's only one. False when no Ghostty terminal has it.
    nonisolated static func close(tty: String) throws(Failure) -> Bool {
        guard reachable else { return false }
        return try run("""
        tell application id "\(bundleID)"
            set found to every terminal whose tty is "\(escape(tty))"
            if (count of found) is 0 then return false
            close (item 1 of found)
            return true
        end tell
        """, test: NSAppleEventDescriptor(boolean: true)).booleanValue
    }

    /// Every terminal's tty and title.
    nonisolated static func terminals() throws(Failure) -> [BackgroundSession.Terminal] {
        guard reachable else { return [] }
        let list = try run("""
        tell application id "\(bundleID)"
            set out to {}
            repeat with term in every terminal
                set end of out to (tty of term) & tab & (name of term)
            end repeat
            return out
        end tell
        """, test: NSAppleEventDescriptor.list())
        guard list.numberOfItems > 0 else { return [] }
        return (1...list.numberOfItems).compactMap { index in
            let parts = (list.atIndex(index)?.stringValue ?? "").split(separator: "\t", maxSplits: 1).map(String.init)
            return parts.count == 2 ? BackgroundSession.Terminal(tty: parts[0], title: parts[1]) : nil
        }
    }

    /// The tty of the terminal focused in Ghostty's front window.
    nonisolated static func focusedTTY() throws(Failure) -> String? {
        guard reachable else { return nil }
        return try run("""
        tell application id "\(bundleID)" to get tty of focused terminal of selected tab of front window
        """, test: fake.withLock { $0.focused }.map { NSAppleEventDescriptor(string: $0) } ?? NSAppleEventDescriptor.null()).stringValue
    }

    /// The Automation prompt, from a harmless call (Setup › Allow, Settings › Ghostty › Test).
    static func requestAccess() async -> Access {
        await Task.detached { access(ask: true) }.value
    }

    // MARK: The one way in

    nonisolated private static let queue = DispatchQueue(label: "hq.ghostty", qos: .userInitiated)

    /// A script, on the serial queue, Ghostty given `timeout` seconds per Apple event. A test copy runs none: it records
    /// the script and answers `test`.
    @discardableResult
    nonisolated private static func run(_ body: String, timeout: Int = Ghostty.timeout,
                                        test: @autoclosure () -> NSAppleEventDescriptor = NSAppleEventDescriptor()) throws(Failure) -> NSAppleEventDescriptor {
        let source = "with timeout of \(timeout) seconds\n\(body)\nend timeout"
        if faked { return record(source, answer: test()) }
        let outcome = queue.sync { () -> (NSAppleEventDescriptor?, NSDictionary?) in
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            return (result, error)
        }
        if let error = outcome.1 {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw .notPermitted }
            if code == Int(errAETimeout) { throw .timedOut }
            throw .script(error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)")
        }
        return outcome.0 ?? NSAppleEventDescriptor()
    }

    nonisolated private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated private static var reachable: Bool { faked || isRunning }

    // MARK: The test copy's Ghostty

    /// A test copy (`APP_STORE`) never reaches Ghostty: its scripts go through the same queue and are recorded.
    nonisolated static let faked = !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty

    /// What the test copy's Ghostty says, and how its scripts ran.
    nonisolated struct Fake: Sendable {
        /// In front, and the tty it says is focused.
        var front = false
        var focused: String?
        /// How long each script takes.
        var delay: TimeInterval = 0
        var scripts: [String] = []
        var onMain = 0
        var running = 0
        var mostAtOnce = 0
    }

    nonisolated static let fake = Mutex(Fake())

    nonisolated private static func record(_ source: String, answer: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let main = Thread.isMainThread
        let delay = fake.withLock { fake in
            fake.scripts.append(source)
            if main { fake.onMain += 1 }
            return fake.delay
        }
        queue.sync {
            fake.withLock { fake in
                fake.running += 1
                fake.mostAtOnce = max(fake.mostAtOnce, fake.running)
            }
            Thread.sleep(forTimeInterval: delay)
            fake.withLock { $0.running -= 1 }
        }
        return answer
    }
}
