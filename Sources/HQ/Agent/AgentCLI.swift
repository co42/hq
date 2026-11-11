import Foundation
import HQKit

/// The app binary is also its CLI. With a command after it, it runs that
/// command against the running app and exits; without one, it opens the app.
///   hq help                         every command, with examples
///   hq ls tasks --tag registry      run one command
///   hq status --json                one JSON object on stdout
///   hq task add "Title" -q          the new item's key alone
///   hq hook                         a hook event on stdin; always exits 0, never opens the app
/// Exit codes: 0 ok, 1 error, 2 usage, 3 not found, 4 app not running, 5 a task this session isn't on.
enum AgentCLI {
    /// nil when the app should open normally.
    static func runIfRequested() -> Int32? {
        var words = Array(CommandLine.arguments.dropFirst())
        // macOS and Xcode pass flags like -NSDocumentRevisionsDebugMode. Not ours.
        guard let first = words.first, !first.hasPrefix("-") || ["--help", "-h", "--version"].contains(first) else { return nil }
        let json = words.contains("--json")
        let quiet = words.contains("-q") || words.contains("--quiet")
        words.removeAll { $0 == "--json" || $0 == "-q" || $0 == "--quiet" }
        do {
            switch first {
            case "help", "--help", "-h":
                return help(Array(words.dropFirst()), json: json)
            case "--version", "version":
                let version = AgentVersion.onDisk()
                print(json ? JSON.string(["version": version]) : "hq \(version)")
                return 0
            case "hook":
                hook()
                return 0
            default:
                return try run(words, json: json, quiet: quiet)
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

    private static func run(_ typed: [String], json: Bool, quiet: Bool) throws -> Int32 {
        let words = try retired(typed)
        // The longest command name that matches the first words: "task add".
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
        var values = try parse(retired(rest, for: command), for: command)
        // "-" reads a text from stdin: `hq task add "Title" --body - < notes.md`.
        for name in ["body", "message"] where values[name] == "-" {
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
        for line in object["warnings"] as? [String] ?? [] { note(line) }
        checkBuild(running: object["app"] as? String)
        if object["ok"] as? Bool == true {
            let result = object["result"] ?? [:]
            if quiet, let keys = keys(result) {
                print(keys)
            } else {
                print(json ? JSON.string(result) : human(result))
            }
            return 0
        }
        let error = object["error"] as? JSONObject ?? [:]
        let code = error["code"] as? String ?? "error"
        throw AgentError(code: code, message: error["message"] as? String ?? "unknown error",
                         exit: ["usage": 2, "not_found": 3, "app_unavailable": 4, "not_mine": 5][code] ?? 1)
    }

    /// --name value, --name=value, --flag, and positional values, checked against the params.
    static func parse(_ words: [String], for command: AgentCommand) throws -> [String: String] {
        var values: [String: String] = [:]
        var positional = command.params.filter(\.positional)
        // A list option given twice keeps both; any other, twice with two values, is a mistake.
        func set(_ param: AgentCommand.Param, _ value: String) throws {
            guard let old = values[param.name] else { values[param.name] = value; return }
            if param.list {
                values[param.name] = old + "," + value
            } else if old != value {
                throw AgentError.usage("--\(param.name) is given twice (\"\(old)\" and \"\(value)\"): give it once")
            }
        }
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
            if !optionsDone, let (name, inline) = option(word) {
                if name == "yes", command.destructive { values["yes"] = "true"; index += 1; continue }
                guard let param = command.params.first(where: { $0.name == name }) else {
                    throw AgentError.usage("\(command.name) has no option --\(name). Run `hq \(command.name) --help`")
                }
                if let inline {
                    try set(param, param.kind == .boolean && inline.isEmpty ? "true" : inline)
                    index += 1
                    continue
                }
                let next = index + 1 < words.count ? words[index + 1] : nil
                if param.kind == .boolean, next == nil || next!.hasPrefix("--") || !["true", "false", "yes", "no"].contains(next!.lowercased()) {
                    try set(param, "true")
                    index += 1
                } else {
                    guard let next else { throw AgentError.usage("--\(name) needs a value") }
                    try set(param, next)
                    index += 2
                }
            } else {
                guard let param = positional.first else { throw AgentError.usage("unexpected \"\(word)\". Run `hq \(command.name) --help`") }
                // A list takes every word left: `task show T-12 T-13`.
                if param.list, let old = values[param.name] { values[param.name] = old + "," + word } else { values[param.name] = word }
                if !param.list { positional.removeFirst() }
                index += 1
            }
        }
        for param in command.params where param.required {
            let shown = param.positional ? "<\(param.name)>" : "--\(param.name)"
            guard let value = values[param.name] else { throw AgentError.usage("missing \(shown). Example: \(command.example)") }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AgentError.usage("\(shown) is empty: check the variable you passed. Example: \(command.example)")
            }
        }
        return values
    }

    /// `--project=HQ` → ("project", "HQ"); `--all` → ("all", nil); anything else isn't an option.
    private static func option(_ word: String) -> (String, String?)? {
        guard word.hasPrefix("--"), word.count > 2 else { return nil }
        let body = word.dropFirst(2)
        let name = body.prefix { $0 != "=" }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
        return (String(name), name.count < body.count ? String(body.dropFirst(name.count + 1)) : nil)
    }

    // MARK: Retired names

    /// Commands that are gone or never were, for a session on older skills: one line on stderr, then the command it meant,
    /// or an error that names what replaced it.
    static func retired(_ words: [String]) throws -> [String] {
        let first = words.first ?? "", second = words.count > 1 ? words[1] : ""
        switch (first, second) {
        case ("link", _) where words.count >= 3 && !second.hasPrefix("-") && !words[2].hasPrefix("-"):
            note("hq link is gone: this ran hq task link \(words[2]) \(second)")
            return ["task", "link", words[2], second] + words.dropFirst(3)
        case ("task", "ls"), ("task", "list"):
            note("hq task \(second) is hq ls tasks")
            return ["ls", "tasks"] + words.dropFirst(2)
        case ("show", _) where second.uppercased().hasPrefix("T-"):
            note("hq show is hq task show")
            return ["task"] + words
        case ("ls", "folders"):
            note("hq ls folders is gone: a project has the folder, hq ls projects")
            return ["ls", "projects"] + words.dropFirst(2)
        case ("tag", _):
            throw AgentError.usage("hq tag is gone: tags are on tasks only, hq task edit T-12 --add-tag perf")
        case ("task", "note"):
            throw AgentError.usage("hq task note is gone: change one part of the description with hq task edit T-12 --section Status --body -, "
                                   + "or tick an item with hq task tick T-12 \"its text\"")
        default:
            return words
        }
    }

    /// Flags that are gone: each answers one line on stderr and is dropped, with its value, so the command runs.
    private static let retiredFlags: [(flag: String, commands: Set<String>, value: Bool, note: String)] = [
        ("type", ["task add", "task edit", "ls"], true, "--type is gone: tasks have no type; ignored"),
        ("now", ["task add"], false, "--now is gone: a new task goes to the end of Tasks anyway; ignored"),
        ("reason", ["task move"], true, "--reason is gone: tell the user what to check with hq notify; ignored"),
    ]

    static func retired(_ words: [String], for command: AgentCommand) -> [String] {
        var kept: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            if word == "--" { kept += words[index...]; break }
            if let flag = retiredFlags.first(where: { $0.commands.contains(command.name) && (word == "--" + $0.flag || word.hasPrefix("--\($0.flag)=")) }) {
                note(flag.note)
                let takesNext = flag.value && word == "--" + flag.flag && index + 1 < words.count && !words[index + 1].hasPrefix("--")
                index += takesNext ? 2 : 1
                continue
            }
            kept.append(word)
            index += 1
        }
        return kept
    }

    // MARK: The running build

    /// Once per session: HQ runs an older build than this hq, so what hq knows may not be there yet.
    private static func checkBuild(running app: String?) {
        let mine = AgentVersion.onDisk()
        guard let build = AgentVersion.build(mine) else { return }
        if let app, let running = AgentVersion.build(app), running >= build { return }
        if let app, AgentVersion.build(app) == nil { return }
        guard once("build \(app ?? "old") \(build)") else { return }
        note("HQ runs \(app ?? "an older build"), hq is \(mine): ask the user to restart HQ. Until then, what is new in hq may not work")
    }

    /// True the first time this session (or this terminal) asks with `key`.
    private static func once(_ key: String) -> Bool {
        let session = ProcessInfo.processInfo.environment["CLAUDE_CODE_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? "terminal"
        let line = "\(session) \(key)"
        let url = Store.directory.appending(path: "hq-warned")
        let seen = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        guard !seen.contains(line) else { return false }
        try? ((seen.suffix(200) + [line]).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    // MARK: Help

    private static func help(_ words: [String], json: Bool) -> Int32 {
        if json {
            print(JSON.string(["commands": AgentCommands.all.map(schema)]))
            return 0
        }
        let name = words.filter { !$0.hasPrefix("-") }.joined(separator: " ")
        if let command = AgentCommands.all.first(where: { $0.name == name }) {
            print(usage(command))
            return 0
        }
        if !name.isEmpty, case let commands = group(name), !commands.isEmpty {
            print(groupHelp(commands))
            return 0
        }
        var lines = ["hq: drive the app from the shell. Every command takes --json; -q prints the key of what it made or listed.", ""]
        let width = (AgentCommands.all.map(\.name.count).max() ?? 0) + 2
        for command in AgentCommands.all {
            lines.append("  " + command.name.padding(toLength: width, withPad: " ", startingAt: 0) + command.summary)
        }
        lines += ["", "More: hq help <command> (its options, an example, its JSON), hq help --json (every command as a schema).",
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
        if !command.output.isEmpty { lines.append("JSON: \(command.output)") }
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
                "readOnly": command.readOnly, "destructive": command.destructive, "output": command.output,
                "inputSchema": ["type": "object", "properties": properties,
                                "required": command.params.filter(\.required).map(\.name)]]
    }

    // MARK: Output

    /// Short plain lines: what sessions read most. --json has every field. A result's `note` and `next` follow on their own lines.
    static func human(_ result: Any) -> String {
        var text = plain(result)
        if let note = (result as? JSONObject)?["note"] as? String { text += "\n" + note }
        if let next = (result as? JSONObject)?["next"] as? String { text += "\n" + next }
        return text
    }

    /// `-q`: the key of what a command made or showed, one per line for a list.
    static func keys(_ result: Any) -> String? {
        func key(_ object: JSONObject) -> String? { object["id"] as? String ?? object["name"] as? String ?? object["url"] as? String }
        guard let object = result as? JSONObject else { return nil }
        if object["total"] != nil, let items = object.values.first(where: { $0 is [JSONObject] }) as? [JSONObject] {
            return items.compactMap(key).joined(separator: "\n")
        }
        if let shown = object["shown"] as? [JSONObject] { return shown.compactMap(key).joined(separator: "\n") }
        return key(object)
    }

    private static func plain(_ result: Any) -> String {
        guard let object = result as? JSONObject else { return "\(result)" }
        if let line = notice(object) { return line }
        // A command with a text form (`ctx`) prints that.
        if let text = object["text"] as? String { return text }
        // A list (`ls`) carries its total, and says when it's cut.
        if let total = object["total"] as? Int, let items = object.values.first(where: { $0 is [JSONObject] }) as? [JSONObject] {
            var text = items.isEmpty ? "(none)" : items.map(line).joined(separator: "\n")
            if let next = object["nextOffset"] as? Int {
                text += "\n\(items.count) of \(total): --limit \(max(100, (total + 99) / 100 * 100)), or --offset \(next) for the next"
            }
            return text
        }
        if let shown = object["shown"] as? [JSONObject] {
            return shown.map { show($0, several: true) }.joined(separator: "\n\n-----\n")
        }
        if object["subtasks"] is [JSONObject] || object["view"] != nil || object["body"] is String { return show(object, several: false) }
        return line(object)
    }

    /// `task show`: its line, the tasks it's part of, its reminders, its text, the tree under it, what's linked. No paths.
    private static func show(_ object: JSONObject, several: Bool) -> String {
        var rest = object
        for key in ["body", "parents", "subtasks", "linked", "progress", "ready", "blockedTasks", "reminders", "view"] { rest[key] = nil }
        let body = object["body"] as? String ?? ""
        if object["view"] as? String == "body" { return several ? line(rest) + "\n" + body : body }
        var text = line(rest)
        for parent in object["parents"] as? [JSONObject] ?? [] { text += "\nPart of: " + brief(parent) }
        for reminder in object["reminders"] as? [JSONObject] ?? [] { text += "\nReminder: " + (notice(reminder) ?? "") }
        if !body.isEmpty { text += "\n\n" + body }
        let subtasks = object["subtasks"] as? [JSONObject] ?? []
        if !subtasks.isEmpty {
            // The tree under it, indented, with each block's progress and what holds each task; --deep adds open ones' text.
            text += "\n\nSubtasks" + ((object["progress"] as? String).map { " (\($0))" } ?? "") + ":\n"
            text += subtasks.map { sub in
                let indent = String(repeating: "  ", count: max(1, sub["depth"] as? Int ?? 1))
                let marks = [sub["progress"] as? String, sub["flow"] as? String].compactMap { $0 }
                var line = indent + brief(sub) + (marks.isEmpty ? "" : " · " + marks.joined(separator: " · "))
                if let body = sub["body"] as? String, !body.isEmpty {
                    line += "\n" + body.components(separatedBy: "\n").map { $0.isEmpty ? "" : indent + "    " + $0 }.joined(separator: "\n") + "\n"
                }
                return line
            }.joined(separator: "\n")
            if let ready = object["ready"] as? [String], !ready.isEmpty { text += "\n\nReady: " + ready.joined(separator: ", ") }
            if let blocked = object["blockedTasks"] as? [JSONObject], !blocked.isEmpty {
                text += "\nBlocked: " + blocked.map { "\($0["id"] as? String ?? "") (\($0["why"] as? String ?? ""))" }.joined(separator: "; ")
            }
        }
        let linked = object["linked"] as? [JSONObject] ?? []
        if !linked.isEmpty { text += "\n\nLinked:\n" + linked.map { "  " + link($0) }.joined(separator: "\n") }
        return text
    }

    /// `T-62 [todo] Registry Release`.
    private static func brief(_ task: JSONObject) -> String {
        "\(task["id"] as? String ?? "") [\(task["status"] as? String ?? "")] \(task["title"] as? String ?? "")"
    }

    /// `pr: Retry budget [open] · https://github.com/…`, `task: T-34 [todo] Title`, `file: 2026-11-04 - Push plan`: the
    /// name or URL each command takes.
    private static func link(_ item: JSONObject) -> String {
        let kind = item["kind"] as? String ?? "link"
        if kind == "task" { return "task: " + brief(item) }
        if kind == "file" { return "file: " + (item["name"] as? String ?? item["title"] as? String ?? "") }
        let state = (item["state"] as? String).map { " [\($0)]" } ?? ""
        let place = (item["url"] as? String).flatMap { $0 == item["title"] as? String ? nil : " · \($0)" } ?? (kind == "session" ? (item["id"] as? String).map { " · \($0.prefix(8))" } : nil) ?? ""
        return "\(kind): \(item["title"] as? String ?? "")\(state)\(place)"
    }

    /// `3F2A9C1B [later] Check the canary · due Saturday 7 November, 18:00`: a notification, with the id its commands take;
    /// a session or a review that waits has no id.
    private static func notice(_ object: JSONObject) -> String? {
        guard let section = object["section"] as? String, let text = object["text"] as? String else { return nil }
        let id = (object["id"] as? String).map { "\($0.prefix(8)) " } ?? ""
        let due = (object["when"] as? String ?? object["due"] as? String).map { " · due \($0)" } ?? ""
        let read = object["read"] != nil ? " · read" : ""
        let place = (object["url"] as? String).map { " · \($0)" } ?? (object["session"] as? String).map { " · session \($0.prefix(8))" } ?? ""
        return "\(id)[\(section)] \(text)\(due)\(read)\(place)"
    }

    /// One line per item, short enough for a card: `T-4 [doing] Title #ui · HQ`. `--json` has every field.
    private static func line(_ object: JSONObject) -> String {
        if let notice = notice(object) { return notice }
        let tags = (object["tags"] as? [String]).flatMap { $0.isEmpty ? nil : " " + $0.map { "#\($0)" }.joined(separator: " ") } ?? ""
        let title = object["title"] as? String ?? object["name"] as? String ?? ""
        if let id = object["id"] as? String, id.hasPrefix("T-"), let status = object["status"] as? String {
            let list = (object["list"] as? String) == "backlog" ? " · Backlog" : ""
            let project = (object["project"] as? String).map { " · \($0)" } ?? ""
            let flow = (object["flow"] as? String).map { " · \($0)" } ?? ""
            return "\(id) [\(status)] \(title)\(tags)\(project)\(flow)\(list)"
        }
        if let id = object["id"] as? String, let state = object["state"] as? String {
            // A session: its state, name, why it waits, and its folder.
            let reason = (object["reason"] as? String).map { " · \($0)" } ?? ""
            let folder = (object["cwd"] as? String).flatMap { $0.isEmpty ? nil : " · " + ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
            let me = object["thisSession"] as? Bool == true ? " · this session" : ""
            return "\(id.prefix(8)) [\(state)] \(title)\(reason)\(folder)\(me)"
        }
        if let url = object["url"] as? String, let state = object["state"] as? String, let number = object["number"] as? Int {
            // "Reviews: Waiting for you", "Yours: Approved by noor".
            let card = (object["card"] as? String).map { " · \($0 == "reviews" ? "Reviews" : "Yours"): \(object["status"] as? String ?? "")" } ?? ""
            return "#\(number) [\(state)] \(title)\(card) · \(url)"
        }
        if object["status"] == nil, object["url"] == nil, let path = object["path"] as? String {
            return "\(object["name"] as? String ?? (path as NSString).lastPathComponent)\(tags)"
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

    /// One line on stderr that doesn't stop the command.
    private static func note(_ line: String) {
        FileHandle.standardError.write(Data("hq: \(line)\n".utf8))
    }

    private static func fail(_ error: AgentError, json: Bool) {
        if json {
            print(JSON.string(error.json))
        } else {
            FileHandle.standardError.write(Data("hq: \(error.message)\n".utf8))
        }
    }
}
