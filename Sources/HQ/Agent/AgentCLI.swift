import Foundation
import HQKit

/// The app binary is also its CLI. With a command after it, it runs that
/// command against the running app and exits; without one, it opens the app.
///   hq help                         every command, with examples
///   hq ls tasks --tag registry      run one command
///   hq status --json                one JSON object on stdout
///   hq hook                         a hook event on stdin; always exits 0, never opens the app
/// Exit codes: 0 ok, 1 error, 2 usage, 3 not found, 4 app not running, 5 a task this session isn't on.
enum AgentCLI {
    /// nil when the app should open normally.
    static func runIfRequested() -> Int32? {
        var words = Array(CommandLine.arguments.dropFirst())
        // macOS and Xcode pass flags like -NSDocumentRevisionsDebugMode. Not ours.
        guard let first = words.first, !first.hasPrefix("-") || ["--help", "-h", "--version"].contains(first) else { return nil }
        let json = words.contains("--json")
        words.removeAll { $0 == "--json" }
        do {
            switch first {
            case "help", "--help", "-h":
                return help(Array(words.dropFirst()), json: json)
            case "--version", "version":
                // Through the ~/.local/bin link, Bundle.main cannot find Info.plist. Follow the link.
                let executable = AgentBinary.url
                let plist = executable.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Info.plist")
                let version = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String ?? "dev"
                print(json ? JSON.string(["version": version]) : "hq \(version)")
                return 0
            case "hook":
                hook()
                return 0
            default:
                return try run(words, json: json)
            }
        } catch let error as AgentError {
            fail(error, json: json)
            return error.exit
        } catch {
            fail(.invalid(error.localizedDescription), json: json)
            return 1
        }
    }

    /// Forwards the event on stdin to HQ with a 1 s timeout, with Claude's pid and terminal.
    /// Hooks never slow Claude: any failure is silent.
    private static func hook() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        var args = ["event": String(decoding: input, as: UTF8.self)]
        if let claude = ClaudeProcess.current() {
            args["pid"] = "\(claude.pid)"
            args["tty"] = claude.tty
            args["ghostty"] = claude.inGhostty ? "true" : "false"
        }
        let reply: Data
        do {
            reply = try AgentSocket.sendOnce(JSON.data(["command": "hook", "args": args]), timeout: 1)
        } catch let error as AgentError where error.message == AgentSocket.notRunning {
            return spool(args)
        } catch {
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? JSONObject,
              let context = (object["result"] as? JSONObject)?["context"] as? String, !context.isEmpty else { return }
        // SessionStart: stdout becomes context for Claude.
        print(context)
    }

    /// HQ is off: the event waits in `pending-hooks.jsonl` for its next launch, under a size cap.
    private static func spool(_ args: [String: String]) {
        guard let event = args["event"],
              let line = HookSpool.line(.init(event: event, pid: args["pid"], tty: args["tty"], ghostty: args["ghostty"], at: .now)) else { return }
        let descriptor = open(Store.directory.appending(path: HookSpool.fileName).path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size < HookSpool.maxBytes else { return }
        _ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    private static func run(_ words: [String], json: Bool) throws -> Int32 {
        // The longest command name that matches the first words: "items add".
        guard let command = AgentCommands.all
            .filter({ words.starts(with: $0.name.split(separator: " ").map(String.init)) })
            .max(by: { $0.name.count < $1.name.count }) else {
            // `hq task` or `hq task --help`: the group's commands.
            let members = group(words.first ?? "")
            if !members.isEmpty, words.dropFirst().allSatisfy({ $0 == "--help" || $0 == "-h" }) {
                print(groupHelp(members))
                return 0
            }
            throw AgentError.usage("unknown command \"\(words.prefix(2).joined(separator: " "))\". Run `hq help\(members.isEmpty ? "" : " \(words[0])")`")
        }
        var rest = Array(words.dropFirst(command.name.split(separator: " ").count))
        if rest.contains("--help") || rest.contains("-h") {
            print(usage(command))
            return 0
        }
        let launch = !rest.contains("--no-launch")
        rest.removeAll { $0 == "--no-launch" }
        var values = try parse(rest, for: command)
        // "-" reads the value from stdin: `hq task add "Title" --body - < notes.md`.
        for (name, value) in values where value == "-" {
            values[name] = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        // Run inside Claude Code, a command knows its session: what it creates lands in that session's folders.
        if let session = ProcessInfo.processInfo.environment["CLAUDE_CODE_SESSION_ID"], !session.isEmpty {
            values[AgentCommands.sessionArg] = session
        }
        values[AgentCommands.cwdArg] = FileManager.default.currentDirectoryPath
        let request = JSON.data(["command": command.name, "args": values])
        let reply = try AgentSocket.send(request, launch: launch)
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? JSONObject else {
            throw AgentError.invalid("the app sent no answer")
        }
        if object["ok"] as? Bool == true {
            let result = object["result"] ?? [:]
            print(json ? JSON.string(result) : human(result))
            return 0
        }
        let error = object["error"] as? JSONObject ?? [:]
        let code = error["code"] as? String ?? "error"
        throw AgentError(code: code, message: error["message"] as? String ?? "unknown error",
                         exit: ["usage": 2, "not_found": 3, "app_unavailable": 4, "not_mine": 5][code] ?? 1)
    }

    /// --name value, --flag, and positional values, checked against the params.
    static func parse(_ words: [String], for command: AgentCommand) throws -> [String: String] {
        var values: [String: String] = [:]
        var positional = command.params.filter(\.positional)
        var index = 0
        // After a bare --, every word is a value: a title may start with --.
        var optionsDone = false
        while index < words.count {
            let word = words[index]
            if word == "--", !optionsDone {
                optionsDone = true
                index += 1
                continue
            }
            if !optionsDone, word.hasPrefix("--"), word.count > 2, word.dropFirst(2).allSatisfy({ $0.isLetter || $0 == "-" }) {
                let name = String(word.dropFirst(2))
                if name == "yes", command.destructive { values["yes"] = "true"; index += 1; continue }
                guard let param = command.params.first(where: { $0.name == name }) else {
                    throw AgentError.usage("\(command.name) has no option --\(name). Run `hq \(command.name) --help`")
                }
                let next = index + 1 < words.count ? words[index + 1] : nil
                if param.kind == .boolean, next == nil || next!.hasPrefix("--") || !["true", "false", "yes", "no"].contains(next!.lowercased()) {
                    values[name] = "true"
                    index += 1
                } else {
                    guard let next else { throw AgentError.usage("--\(name) needs a value") }
                    values[name] = next
                    index += 2
                }
            } else {
                guard !positional.isEmpty else { throw AgentError.usage("unexpected \"\(word)\". Run `hq \(command.name) --help`") }
                values[positional.removeFirst().name] = word
                index += 1
            }
        }
        for param in command.params where param.required && values[param.name] == nil {
            throw AgentError.usage("missing \(param.positional ? "<\(param.name)>" : "--\(param.name)"). Example: \(command.example)")
        }
        return values
    }

    // MARK: Help

    private static func help(_ words: [String], json: Bool) -> Int32 {
        if json {
            print(JSON.string(["commands": AgentCommands.all.map(schema)]))
            return 0
        }
        let name = words.joined(separator: " ")
        if let command = AgentCommands.all.first(where: { $0.name == name }) {
            print(usage(command))
            return 0
        }
        if !name.isEmpty, case let commands = group(name), !commands.isEmpty {
            print(groupHelp(commands))
            return 0
        }
        var lines = ["hq: drive the app from the shell. Every command takes --json.", ""]
        let width = (AgentCommands.all.map(\.name.count).max() ?? 0) + 2
        for command in AgentCommands.all {
            lines.append("  " + command.name.padding(toLength: width, withPad: " ", startingAt: 0) + command.summary)
        }
        lines += ["", "More: hq help <command>, hq help --json (every command as a schema).",
                  "Exit codes: 0 ok, 1 error, 2 usage, 3 not found, 4 app not running, 5 a task this session isn't on (--not-mine)."]
        print(lines.joined(separator: "\n"))
        return 0
    }

    /// The commands under one word: `task` → task add, task move, …
    private static func group(_ word: String) -> [AgentCommand] {
        AgentCommands.all.filter { $0.name.hasPrefix(word + " ") }
    }

    private static func groupHelp(_ commands: [AgentCommand]) -> String {
        let width = (commands.map(\.name.count).max() ?? 0) + 2
        return (commands.map { "  hq " + $0.name.padding(toLength: width, withPad: " ", startingAt: 0) + $0.summary }
                + ["", "Options and an example: hq help \(commands[0].name)"]).joined(separator: "\n")
    }

    static func usage(_ command: AgentCommand) -> String {
        var lines = ["\(command.summary)", "", "  hq \(command.name)" + command.params.map { param in
            let shown = param.positional ? "<\(param.name)>" : param.kind == .boolean ? "--\(param.name)" : "--\(param.name) <\(param.kind.rawValue)>"
            return " " + (param.required ? shown : "[\(shown)]")
        }.joined() + (command.destructive ? " [--yes]" : "")]
        if !command.params.isEmpty { lines.append("") }
        for param in command.params {
            lines.append("  " + (param.positional ? param.name : "--" + param.name).padding(toLength: 14, withPad: " ", startingAt: 0) + param.help)
        }
        if command.destructive { lines.append("  --yes         do it. Without --yes it only shows what it would change") }
        lines += ["", "Example: \(command.example)"]
        return lines.joined(separator: "\n")
    }

    static func schema(_ command: AgentCommand) -> JSONObject {
        var properties: JSONObject = [:]
        for param in command.params {
            properties[param.name] = ["type": param.kind.rawValue, "description": param.help]
        }
        if command.destructive {
            properties["yes"] = ["type": "boolean", "description": "Do it. Without yes it only shows what it would change."]
        }
        return ["name": command.name, "description": command.summary + " Example: " + command.example,
                "readOnly": command.readOnly, "destructive": command.destructive,
                "inputSchema": ["type": "object", "properties": properties,
                                "required": command.params.filter(\.required).map(\.name)]]
    }

    // MARK: Output

    /// Short plain lines for people. Agents use --json. A result's `next` says what to do now, on its own line.
    static func human(_ result: Any) -> String {
        let text = plain(result)
        guard let next = (result as? JSONObject)?["next"] as? String else { return text }
        return text + "\n" + next
    }

    private static func plain(_ result: Any) -> String {
        if let object = result as? JSONObject, let line = notice(object) { return line }
        // A command with a text form (`ctx`) prints that.
        if let text = (result as? JSONObject)?["text"] as? String { return text }
        // A list (`ls`) carries its total; anything else is one item.
        if let object = result as? JSONObject, object["total"] != nil,
           let items = object.values.first(where: { $0 is [JSONObject] }) as? [JSONObject] {
            return items.isEmpty ? "(none)" : items.map(line).joined(separator: "\n")
        }
        if let object = result as? JSONObject, let body = object["body"] as? String {
            // `show`: the item's line, its note's path and the tasks it's part of, then its text, its subtasks and what's linked.
            var rest = object
            for key in ["body", "parents", "subtasks", "linked"] { rest[key] = nil }
            var text = line(rest) + ((object["path"] as? String).map { "\n" + $0 } ?? "")
            for parent in object["parents"] as? [JSONObject] ?? [] { text += "\nPart of: " + brief(parent) }
            if !body.isEmpty { text += "\n\n" + body }
            let subtasks = object["subtasks"] as? [JSONObject] ?? []
            if !subtasks.isEmpty { text += "\n\nSubtasks:\n" + subtasks.map { "  " + brief($0) }.joined(separator: "\n") }
            let linked = object["linked"] as? [JSONObject] ?? []
            if !linked.isEmpty { text += "\n\nLinked:\n" + linked.map { "  " + link($0) }.joined(separator: "\n") }
            return text
        }
        if let object = result as? JSONObject { return line(object) }
        return "\(result)"
    }

    /// `T-62 [todo] Registry Release`.
    private static func brief(_ task: JSONObject) -> String {
        "\(task["id"] as? String ?? "") [\(task["status"] as? String ?? "")] \(task["title"] as? String ?? "")"
    }

    /// `artifact: registry data paths · https://claude.ai/artifact/…`, `task: T-34 [todo] Title`.
    private static func link(_ item: JSONObject) -> String {
        let kind = item["kind"] as? String ?? "link"
        if kind == "task" { return "task: " + brief(item) }
        let state = (item["state"] as? String).map { " [\($0)]" } ?? ""
        let place = (item["url"] as? String ?? item["path"] as? String).map { " · \($0)" } ?? ""
        return "\(kind): \(item["title"] as? String ?? "")\(state)\(place)"
    }

    /// `3F2A9C1B [later] Check the canary · due 2026-11-07T18:00:00Z`: a notification, with the id its commands take.
    private static func notice(_ object: JSONObject) -> String? {
        guard let id = object["id"] as? String, let section = object["section"] as? String, object["level"] != nil else { return nil }
        let due = (object["due"] as? String).map { " · due \($0)" } ?? ""
        let read = object["read"] != nil ? " · read" : ""
        return "\(id.prefix(8)) [\(section)] \(object["text"] as? String ?? "")\(due)\(read)"
    }

    /// One line per item, short enough for a card: `T-4 [doing] Title #ui · bug · HQ`. `--json` has every field.
    private static func line(_ object: JSONObject) -> String {
        if let notice = notice(object) { return notice }
        let tags = (object["tags"] as? [String]).flatMap { $0.isEmpty ? nil : " " + $0.map { "#\($0)" }.joined(separator: " ") } ?? ""
        let title = object["title"] as? String ?? object["name"] as? String ?? ""
        if let id = object["id"] as? String, id.hasPrefix("T-"), let status = object["status"] as? String {
            let list = (object["list"] as? String) == "backlog" ? " · Backlog" : ""
            let review = (object["review"] as? String).map { " · Review: \($0)" } ?? ""
            let kind = (object["type"] as? String).map { " · \($0)" } ?? " · no type"
            let project = (object["project"] as? String).map { " · \($0)" } ?? ""
            return "\(id) [\(status)] \(title)\(tags)\(kind)\(project)\(review)\(list)"
        }
        if let id = object["id"] as? String, let state = object["state"] as? String {
            let reason = (object["reason"] as? String).map { " · \($0)" } ?? ""
            return "\(id.prefix(8)) [\(state)] \(title)\(reason)"
        }
        if let url = object["url"] as? String, let state = object["state"] as? String, let number = object["number"] as? Int {
            // "Reviews: Waiting for you", "Yours: Approved by noor".
            let card = (object["card"] as? String).map { " · \($0 == "reviews" ? "Reviews" : "Yours"): \(object["status"] as? String ?? "")" } ?? ""
            return "#\(number) [\(state)] \(title)\(card) · \(url)"
        }
        if object["status"] == nil, object["url"] == nil, let path = object["path"] as? String {
            return "\((path as NSString).lastPathComponent)\(tags)"
        }
        if let url = object["url"] as? String { return "\(title)\(tags) · \(url)" }
        return fields(object)
    }

    private static func fields(_ object: JSONObject) -> String {
        let first = ["id", "title", "name"]
        return object.keys.sorted { a, b in
            (first.firstIndex(of: a) ?? 9, a) < (first.firstIndex(of: b) ?? 9, b)
        }
        .map { key in
            let value = object[key]
            // JSON booleans arrive as NSNumber; show them as yes and no.
            if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "\(key): \(number.boolValue ? "yes" : "no")"
            }
            if let list = value as? [Any] { return "\(key): " + list.map { "\($0)" }.joined(separator: ", ") }
            return "\(key): \(value.map { "\($0)" } ?? "")"
        }
        .joined(separator: "  ")
    }

    private static func fail(_ error: AgentError, json: Bool) {
        if json {
            print(JSON.string(error.json))
        } else {
            FileHandle.standardError.write(Data("hq: \(error.message)\n".utf8))
        }
    }
}
