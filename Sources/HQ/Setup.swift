import AppKit

/// The things HQ needs (DESIGN.md §15): the Claude plugin, Ghostty access, the vault.
extension AppModel {
    /// Checks all three without asking anything: at launch, when HQ becomes active, and every
    /// 2 s while the setup sheet is open.
    func checkSetup() {
        setup.pluginInstalled = Self.pluginInstalled()
        switch Ghostty.access() {
        case .allowed: setup.ghosttyAllowed = true
        case .denied, .notAsked: setup.ghosttyAllowed = false
        case .notRunning: break
        }
        setup.vaultPath = vault?.root.deletingLastPathComponent().path
        guard !Store.isOverridden else { return }
        if !setup.pluginInstalled {
            problem = .pluginMissing
        } else if Ghostty.access() == .denied {
            problem = .ghosttyAccess
        } else if problem == .pluginMissing || problem == .ghosttyAccess {
            problem = nil
        }
    }

    /// True when Claude Code has hq@hq installed and not disabled.
    nonisolated static func pluginInstalled() -> Bool {
        let claude = URL.homeDirectory.appending(path: ".claude")
        func json(_ path: String) -> [String: Any]? {
            (try? Data(contentsOf: claude.appending(path: path))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        guard let plugins = json("plugins/installed_plugins.json")?["plugins"] as? [String: Any], plugins["hq@hq"] != nil else { return false }
        return (json("settings.json")?["enabledPlugins"] as? [String: Any])?["hq@hq"] as? Bool != false
    }

    /// Setup › Install and the banner's Install Plugin: runs the installer bundled in HQ.app.
    func installPlugin() {
        guard !pluginInstalling else { return }
        pluginInstalling = true
        pluginError = nil
        let script = Bundle.main.resourceURL?.appending(path: "Plugin/install.sh").path ?? ""
        Task {
            let result = await Task.detached { Self.run("/bin/zsh", [script]) }.value
            pluginInstalling = false
            if result.status != 0 {
                pluginError = result.output.split(separator: "\n").last.map(String.init) ?? "The installer failed"
            }
            checkSetup()
        }
    }

    /// Setup › Allow: macOS asks once for Automation of Ghostty. Ghostty has to run for the question.
    func allowGhostty() {
        Task {
            if !Ghostty.isRunning {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Ghostty.bundleID) {
                    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
                try? await Task.sleep(for: .seconds(1))
            }
            let access = await Ghostty.requestAccess()
            if access == .denied, let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(pane)
            }
            checkSetup()
        }
    }

    /// Settings › Ghostty: the Automation pane, to change the answer.
    func openAutomationSettings() {
        if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(pane)
        }
    }

    /// Setup › Choose…: another vault, saved for the next launches.
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use This Vault"
        panel.message = "Choose your Obsidian vault. HQ keeps its tasks and files in its hq folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !Store.isOverridden { UserDefaults.standard.set(url.path, forKey: "vault.path") }
        vault = Vault(vault: url)
        vaultCache = Vault.Cache()
        startVault()
        checkSetup()
    }

    /// The banner's Fix button.
    func fix(_ problem: Problem) {
        switch problem {
        case .pluginMissing: installPlugin()
        case .ghosttyAccess: openAutomationSettings()
        case .ghosttyUnreachable:
            self.problem = nil
            if modal == .start { startFromDraft() }
        case .githubSignedOut: Pasteboard.copy("gh auth login")
        case .githubMissing: Pasteboard.copy("brew install gh && gh auth login")
        case .githubFailing:
            self.problem = nil
            gitHubService?.poll()
        }
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let home = URL.homeDirectory.path
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
