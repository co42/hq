import Foundation

/// Starts the CLI when there is a command after the app's name, else the app.
@main
enum Main {
    static func main() {
        if let code = AgentCLI.runIfRequested() { exit(code) }
        // Tooltips come almost at once, everywhere (2026-11-10): set before AppKit reads it.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": Motion.tooltipMilliseconds])
        HQApp.main()
    }
}
