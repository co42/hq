import Foundation

// The agent interface: one list of commands (AgentCommands.swift) that the
// CLI and its help read. Commands run inside the app, on the main actor,
// so the window updates live.

typealias JSONObject = [String: Any]

/// One thing an agent can do. Names are "<noun> <verb>": "task add".
struct AgentCommand {
    struct Param {
        enum Kind: String { case string, integer, boolean }
        var name: String
        var kind: Kind = .string
        var required = false
        /// Given without its --name, right after the command: `task show T-12`.
        var positional = false
        /// Comma-separated: given twice, the values join.
        var list = false
        var help: String
    }

    var name: String
    var summary: String
    var params: [Param] = []
    var example: String
    /// The shape of its `--json` result, for `hq help <command>`.
    var output = ""
    /// Only reads. Agents may run it without asking.
    var readOnly = false
    /// Removes data or cannot be undone. Without --yes it only reports what it would do.
    var destructive = false
    var run: (Args, AppModel) throws -> Any
}

/// The values a command was called with, checked against its params.
struct Args {
    var values: [String: String]
    /// The params given without their --name, for messages: `<task>`.
    var positional: Set<String> = []
    var example = ""

    func string(_ name: String) -> String? { values[name] }

    func required(_ name: String) throws -> String {
        let shown = positional.contains(name) ? "<\(name)>" : "--\(name)"
        let example = example.isEmpty ? "" : ". Example: \(example)"
        guard let value = values[name] else { throw AgentError.usage("missing \(shown)\(example)") }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.usage("\(shown) is empty: check the variable you passed\(example)")
        }
        return value
    }

    func int(_ name: String, default fallback: Int) throws -> Int {
        guard let raw = values[name] else { return fallback }
        guard let value = Int(raw) else { throw AgentError.usage("--\(name) must be a whole number, not \"\(raw)\"") }
        return value
    }

    func bool(_ name: String) throws -> Bool? {
        guard let raw = values[name] else { return nil }
        switch raw.lowercased() {
        case "", "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: throw AgentError.usage("--\(name) must be true or false, not \"\(raw)\"")
        }
    }

    var confirmed: Bool { (try? bool("yes")) == true }
}

/// An error with a stable code an agent can branch on, a message that says
/// how to fix it, and the exit code the CLI returns.
nonisolated struct AgentError: Error {
    var code: String
    var message: String
    var exit: Int32

    static func usage(_ message: String) -> AgentError { AgentError(code: "usage", message: message, exit: 2) }
    static func notFound(_ message: String) -> AgentError { AgentError(code: "not_found", message: message, exit: 3) }
    /// A task this session isn't on: refused unless --not-mine.
    static func notMine(_ message: String) -> AgentError { AgentError(code: "not_mine", message: message, exit: 5) }
    static func invalid(_ message: String) -> AgentError { AgentError(code: "invalid", message: message, exit: 1) }
    static func unavailable(_ message: String) -> AgentError { AgentError(code: "app_unavailable", message: message, exit: 4) }
    /// A description changed since the session last read it.
    static func stale(_ message: String) -> AgentError { AgentError(code: "stale", message: message, exit: 1) }

    var json: JSONObject { ["ok": false, "error": ["code": code, "message": message]] }
}

/// Runs requests from the socket inside the app.
enum AgentRouter {
    static var model: AppModel?
    /// Lines the CLI prints on stderr while the command still runs: a needless flag.
    private static var warnings: [String] = []

    static func warn(_ line: String) {
        if !warnings.contains(line) { warnings.append(line) }
    }

    /// A request is {"command": "task add", "args": {"title": "Dedup"}}.
    static func handle(_ request: Data) -> Data {
        var reply: JSONObject
        warnings = []
        do {
            guard let object = try JSONSerialization.jsonObject(with: request) as? JSONObject,
                  let name = object["command"] as? String else { throw AgentError.usage("bad request") }
            guard let command = AgentCommands.all.first(where: { $0.name == name }) else {
                throw AgentError.usage("unknown command \"\(name)\". Run `hq help`")
            }
            guard let model else { throw AgentError.unavailable("the app is still starting. Try again") }
            let args = Args(values: object["args"] as? [String: String] ?? [:],
                            positional: Set(command.params.filter(\.positional).map(\.name)), example: command.example)
            // Claude's changes stay out of the user's Edit › Undo: they arrive outside any event, and ⌘Z
            // would undo them along with their own.
            model.undoManager?.disableUndoRegistration()
            // What Claude changes turns blue for the user; reads change nothing.
            model.actor = command.readOnly || name == "hook" ? nil : (args.string(AgentCommands.sessionArg) ?? "claude")
            defer {
                model.actor = nil
                model.undoManager?.enableUndoRegistration()
            }
            let before = command.readOnly || name == "hook" ? nil : model.tasks
            reply = ["ok": true, "result": try command.run(args, model)]
            if let before {
                TaskEditLog.shared.record(command: name, session: args.string(AgentCommands.sessionArg), before: before, after: model.tasks)
            }
        } catch let error as AgentError {
            reply = error.json
        } catch {
            reply = AgentError.invalid(error.localizedDescription).json
        }
        if !warnings.isEmpty { reply["warnings"] = warnings }
        reply["app"] = AgentVersion.atLaunch
        return JSON.data(reply)
    }
}

/// The build a binary is, `0.1 (202611111020)`: the bundle's version and its build stamp.
nonisolated enum AgentVersion {
    /// The running app's, read when it starts listening: a rebuild under it doesn't change it.
    static let atLaunch = onDisk()
    static let launchedAt = Date.now

    /// The bundle's Info.plist beside the binary, the ~/.local/bin link followed.
    static func onDisk() -> String {
        let plist = AgentBinary.url.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Info.plist")
        let info = NSDictionary(contentsOf: plist)
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        return (info?["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
    }

    /// The build stamp in `0.1 (202611111020)`, to order two builds.
    static func build(_ version: String) -> Int? {
        version.split(separator: "(").last.flatMap { Int($0.dropLast()) }
    }
}

nonisolated enum JSON {
    static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    static func string(_ object: Any) -> String {
        String(decoding: data(object), as: UTF8.self)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

nonisolated enum AgentBinary {
    /// The app's binary, with the ~/.local/bin link followed. Run from PATH,
    /// argv[0] is only the CLI's name, so ask the system for the full path.
    static var url: URL {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        let path = _NSGetExecutablePath(&buffer, &size) == 0
            ? String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            : CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }
}
