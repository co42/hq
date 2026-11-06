import AppKit

/// Ghostty through AppleScript (PLAN.md §2): focus the terminal a session runs in, or open a
/// tab that runs a command. HQ never owns a terminal.
enum Ghostty {
    nonisolated static let bundleID = "com.mitchellh.ghostty"

    enum Failure: Error, Equatable {
        /// Automation for Ghostty is off in System Settings.
        case notPermitted
        case script(String)
    }

    enum Access: Equatable {
        case allowed, denied, notAsked, notRunning
    }

    nonisolated static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
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
    /// AppleScript takes 50 to 100 ms: call it off the main thread.
    nonisolated static func focus(tty: String) throws(Failure) -> Bool {
        guard isRunning else { return false }
        let result = try run("""
        tell application id "\(bundleID)"
            set found to every terminal whose tty is "\(escape(tty))"
            if (count of found) is 0 then return false
            focus (item 1 of found)
            activate
            return true
        end tell
        """)
        return result.booleanValue
    }

    /// A new tab in the front window (or a new window) in `directory`, with `command` typed into
    /// the shell and run, so the shell stays when the command exits. Ghostty pastes `initial
    /// input`, and fish never runs a pasted newline: the command is typed, then Return is pressed.
    /// It waits for the shell to start, so call it off the main thread.
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
        """)
    }

    /// Types text and Return into the terminal on `tty` (Close Session's `/exit`). False when no Ghostty terminal has it.
    nonisolated static func type(_ text: String, tty: String) throws(Failure) -> Bool {
        guard isRunning else { return false }
        return try run("""
        tell application id "\(bundleID)"
            set found to every terminal whose tty is "\(escape(tty))"
            if (count of found) is 0 then return false
            input text "\(escape(text))" to (item 1 of found)
            send key "enter" to (item 1 of found)
            return true
        end tell
        """).booleanValue
    }

    /// Closes the terminal on `tty`: its tab goes with it when it was the tab's only one. False when no Ghostty terminal has it.
    nonisolated static func close(tty: String) throws(Failure) -> Bool {
        guard isRunning else { return false }
        return try run("""
        tell application id "\(bundleID)"
            set found to every terminal whose tty is "\(escape(tty))"
            if (count of found) is 0 then return false
            close (item 1 of found)
            return true
        end tell
        """).booleanValue
    }

    /// The tty of the terminal focused in Ghostty's front window. AppleScript: call it off the main thread when you can.
    nonisolated static func focusedTTY() throws(Failure) -> String? {
        guard isRunning else { return nil }
        return try run("""
        tell application id "\(bundleID)" to get tty of focused terminal of selected tab of front window
        """).stringValue
    }

    /// The Automation prompt, from a harmless call (Setup › Allow, Settings › Ghostty › Test).
    static func requestAccess() async -> Access {
        await Task.detached { access(ask: true) }.value
    }

    @discardableResult
    nonisolated private static func run(_ source: String) throws(Failure) -> NSAppleEventDescriptor {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw .notPermitted }
            throw .script(error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)")
        }
        return result ?? NSAppleEventDescriptor()
    }

    nonisolated private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
