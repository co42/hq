import Foundation

/// Starts the CLI when there is a command after the app's name, else the app.
@main
enum Main {
    static func main() {
        // A write to a socket or pipe whose reader left fails with EPIPE, never stops the app or the CLI (T-686).
        signal(SIGPIPE, SIG_IGN)
        if let code = AgentCLI.runIfRequested() { exit(code) }
        // Tooltips come almost at once, everywhere (2026-11-10): set before AppKit reads it.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": Motion.tooltipMilliseconds])
        // Test and snapshot runs wait on what shows: nothing slides or fades.
        let env = ProcessInfo.processInfo.environment
        Motion.still = (UITest.requested || SelfTest.requested || env["APP_SNAPSHOT"] != nil) && env["HQ_MOTION"] != "1"
        HQApp.main()
    }
}
