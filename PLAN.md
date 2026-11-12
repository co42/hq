# hq — plan

hq is the user's cockpit for a day of work with Claude Code: a native macOS app docked on the right half of the screen, with Ghostty on the left. One page shows their Claude sessions with their faces and live state, the pull requests that wait on them, and their tasks with their Backlog as one outline; anything bigger, the notification center included, opens in a sheet over it. hq indexes and links; other apps do the work: Ghostty runs sessions, Obsidian holds the notes, the browser shows artifacts, GitHub holds PRs and issues.

How it looks and behaves: [DESIGN.md](DESIGN.md). The build plan this was rebuilt from: the HQ file "2026-11-04 - HQ cockpit build plan" (T-46).

Legend: ✅ verified on this Mac or in source · 🔍 to check during the build.

## 1. Principles

- **Tailored to the user.** Built from their workflow (Ghostty, Obsidian, worktrees, GitHub), not from another tool. Never look at, copy or model anything on claude-run: not its code, UI, data model, words or skills.
- **One page.** The cockpit is the only view; everything else is a sheet over it. No folders, sidebar, view picker, inspector or comments (2026-11-04).
- **hq never owns a terminal.** The user arranges Ghostty as they like. hq finds a session's terminal and focuses it, or opens a tab to start or resume one.
- **Files are the truth where they exist.** Tasks and files are Obsidian notes; hq writes only the front matter keys it owns. hq's store holds only what has no file: sessions, artifacts, notifications, what the user acknowledged.
- **Hooks never slow Claude.** Fast, always exit 0; the next event repairs a missed one.

## 2. Decisions

| Topic | Decision |
|---|---|
| App | SwiftUI on macOS 27 only (2026-11-05), AppKit where SwiftUI falls short (the outline, the session grid, the Ghostty bridge, text editors). Swift 6.4, a Swift package, no Xcode project |
| Names | App `HQ`, bundle id `io.github.co42.hq`, CLI `hq` |
| Process | One process, the app: store, vault index, hook socket, Ghostty bridge, GitHub poller. Stays alive when its window closes |
| CLI | The app binary is the CLI (bama `agent-cli`): `~/.local/bin/hq` links into the bundle and talks to the running app over a Unix socket. If the app is closed, `hq` opens it in the background; `hq hook` never does: it keeps the event in `pending-hooks.jsonl` (compact, 4 MB cap), which the app replays at launch with the events' own times |
| Store | SwiftData in `~/Library/Application Support/HQ/`: sessions, artifacts and seen records. Beside it as JSON: GitHub's last answer, and `notifications.json` (the rows, when the user last opened the center, GitHub event keys). Live session state stays in memory |
| Vault | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes`; hq's folder is `hq/` with `tasks/` and `files/`. Front matter read and written line by line (`HQKit.FrontMatter`), so other keys keep their text |
| Claude plugin | `plugin/` in this repo, installed globally through a local marketplace: hooks and skills. `Bash(hq:*)` allowed in `~/.claude/settings.json` |
| Ghostty | AppleScript in-process (`NSAppleScript`), every script on one serial queue off the main thread, each Apple event given 3 s (a new tab 10 s): a busy or hung Ghostty fails the call and never holds HQ. Automation permission |
| GitHub | GraphQL with the token from `gh auth token`, a few aliased queries per poll sent together, read-only |
| Artifacts | claude.ai links captured from hooks, shown live in a web view with HQ's own claude.ai sign-in |
| Signing | Apple Development certificate, installed to `/Applications/HQ.app` |
| Notifications | Events go to a notification center, a sheet, and are read once; the page shows state only. macOS banners, the Dock badge and HQ's mark in the menu bar for what needs the user (2026-11-06) |
| Look | Native chrome (toolbar, sheets, menus); raised cards on a canvas under a sky that follows the day; Liquid Glass for everything that floats (toolbar, section bar, section controls, hover controls, the modal's header); the Mac's accent and system colors for meaning. All of it in DESIGN.md |

## 3. Verified facts

| Topic | Finding |
|---|---|
| Machine ✅ | `actool` needs `sudo xcodebuild -runFirstLaunch` once. Design widths: half of a 3008×1692 pt display (1504 pt) and half of a 1512×982 pt laptop screen (756 pt). An Apple Development certificate needs the WWDR G3 intermediate, and `security set-key-partition-list -S apple-tool:,apple:,codesign: -s` so `codesign` stops asking for the login password on every build. With Screen Recording for the terminal, snapshots are real window captures |
| Ghostty ✅ | 1.4.0, dictionary in `/Applications/Ghostty.app/Contents/Resources/Ghostty.sdef`. Terminals have a stable `id`, `name`, `working directory`, `pid`, `tty` and a writable `name override`. Commands: `new window`, `new tab`, `split`, `focus` (brings the window front, selects tab and split), `input text` (pasted), `send key`, `close`. Surface configuration: `command`, `initial working directory`, `initial input`, `environment variables`, `wait after command`. No screen contents, no window frame. Automation prompt on first use |
| Hooks ✅ (S4, Claude Code 2.1.317) | Command hooks get the event JSON on stdin; SessionStart stdout reaches the model as context. Common fields: `session_id`, `transcript_path`, `cwd`, `hook_event_name`. `/clear` = SessionEnd(`clear`) then SessionStart(`clear`) with a new `session_id`. AskUserQuestion and ExitPlanMode also raise PermissionRequest and a `permission_prompt` Notification. Nothing fires on Esc, rejection or interrupt. `idle_prompt` 60 s after activity. Stop carries `last_assistant_message`; PermissionRequest carries `tool_name` and `tool_input`; PreToolUse ExitPlanMode carries `planFilePath`. An event fired inside a subagent or teammate carries `agent_id` and `agent_type` (hooks reference, 2026-11-11). Plugin `bin/` is last on the Bash PATH and absent from the hook PATH. A skill with `allowed-tools` needs approval to load: don't use it |
| Claude CLI ✅ | `--resume <id>` works from any cwd; `--session-id`, `-n/--name`, `--fork-session`, `--permission-mode` |
| Transcripts ✅ | `~/.claude/projects/<cwd with non-alphanumerics → '-'>/<session_id>.jsonl`, with `custom-title` and `ai-title` entries. The format is internal: best effort |
| Vault ✅ | Bases and the tag pane are on. Claude-written notes already live in `work/claude/` as `YYYY-MM-DD - Title.md` with front matter `title, date, tags, status`, Mermaid in the body. hq follows that convention |
| bama ✅ | Template: Swift package (app, Kit, tests), `build.sh` → signed `.app`, snapshot mode (PNG per page, light and dark), `--selftest`, `Space` 4 pt grid with a lint and layout probes. `agent-cli` adds the socket CLI linked to `~/.local/bin` |
| Artifact tool ✅ | Named `Artifact`; its PostToolUse response holds the page's `https://claude.ai/artifact/<id>` URL |
| Test runs ✅ | Beside a running HQ, SwiftUI doesn't open a second copy's `Window` at launch: test runs open it through Window › HQ, with `-ApplePersistenceIgnoreState YES`. macOS hands synthetic clicks to an `NSTableView` only in the active app, so a background UI test reports those checks as SKIP |
| AppKit in a SwiftUI page ✅ | An `NSTableView` with no scroll view of its own, inside SwiftUI's `ScrollView`, draws only the rows on screen and takes the click that activates the window. SwiftUI's `List` refused that click. Rows it keeps outside the visible rect must be refreshed too, or they show stale content when scrolled back |
| GitHub ✅ | `gh auth token` works; the real query returns review requests, the user's PRs and linked items. The API rejects a query with an unused fragment |
| Performance ✅ | 500 tasks and 30 sessions (`APP_SEED=large`, the UI test's last group), App Nap off: scrolling at trackpad speed 8 ms median per frame, a search keystroke about 25 ms (55 worst), a fold 5 ms, a move about 25 ms, Show Descriptions about 50 ms once. With the screen locked, App Nap's timer coalescing triples every measured stall: measure with it off. At rest on a copy of the user's data (`tools/perf.sh`, 2026-11-06): 0.2% CPU, about 90 MB, 3 MB of GPU memory; tool calls coming in at 7 a second, 2% CPU; launch flat at about 70 MB (`tools/launch.sh`) |

## 4. Architecture

```
 Ghostty ◄──── AppleScript: focus, new tab, input ───────┐
                                                          │
 Claude Code + hq plugin                                  │
   hooks ─── hq hook ──┐                                  │
   skills ── hq …  ────┤ Unix socket                      │
                       ▼                                  │
             ┌───────────────── HQ.app ───────────────────┴─┐
             │ sessions: hook events (memory) + store       │
             │ store: sessions, artifacts, notifications    │◄── GraphQL ── api.github.com
             │ vault index: tasks, files (memory)           │◄── FSEvents ── <vault>/hq/
             └──────────────────────────────────────────────┘
```

- `HQKit` (its own package, so its tests build in seconds without the app): no UI. Task statuses, the task tree and its operations, the vault migration planner, front matter, markdown blocks and checkbox toggling, face specs and their palette, GitHub parsing and link rules, hook events and the session state machine.
- `Sources/HQ`: the app. `CockpitView` (the page), `SessionGrid` (`NSCollectionView`), `TaskOutline` (`NSOutlineView`), `ModalHost` (the sheet and its kinds), `Notices` and `NotificationCenterView` (the notification center, reminders, banners), `DesignKit/` (tokens and parts), `Agent/` (CLI and socket).

## 5. Model

### Task: `<vault>/hq/tasks/T-<n>.md`

```yaml
---
title: Retry budget for blob uploads
status: doing           # todo | doing | done
type: feature           # optional, older notes: kept as written, never set or shown (T-220)
project: Registry       # optional
tags: [perf]
parent: T-9             # optional: subtasks are their own notes
list: overview          # overview | backlog (top-level tasks only)
order: 3.5              # among siblings
done: 2026-11-04T16:20  # when it was done
links: [https://github.com/acme/registry/pull/418]
related: [T-34]          # tasks linked to it: "see also"
blocked: true            # Blocked: it can't be done now (T-372)
blocked_reason: Waiting on the CPU decision   # optional
blocked_by: [T-268]      # blocked until each is done
after: [T-270]           # the order the user means; nothing moves for it
sessions: [2f1c9e0a-…]
created: 2026-11-03
---
The description, in markdown. Older dated notes stay here as paragraphs.
```

- `n` is the highest existing plus one. All other keys and the body keep their exact text.
- `HQKit.TaskTree`: built from (parent, list, order); a missing parent or a cycle puts a task at the top level. Operations return the notes that change: insert after, insert first child, indent, outdent, move among siblings, move to a list, drop (on a row: last child; between rows: sibling at that index; on a list header: last top-level task), delete with the subtree. Never into its own subtree. Order is fractional: the midpoint between neighbors, the siblings renumbered when a gap falls under 1e-6.
- **Migration** (once, then idempotent; `HQKit.TaskMigration` plans it, the app applies it after zipping `<vault>/hq/tasks` to `~/Library/Application Support/HQ/Backups/tasks-<date>.zip`): `status: backlog` → `todo` + `list: backlog`; `todo` → `list: backlog`; `doing`, `review` → `list: overview`; `done` → `list: backlog` with `done:` from the file's modification date. A missing type stays missing.
- **Blocked, blocked by, after** (2026-11-10, T-372): `HQKit.TaskFlow` works out each task's state from the tree and these keys, never stored: done; Blocked; blocked by a task not done; doing; held (under a task that's Blocked or blocked by one not done: a Blocked task holds what's under it, 2026-11-11); waiting (after a task not done); ready. A story's tally counts its leaves, held ones as blocked. A held row looks as it did: its holder shows the red edge or the chips; `hq` says "held by T-n" and leaves it out of Ready. A link to a task that's gone or done holds nothing; a link the tree already says (to a subtask) or that would go in a circle is refused. Marking a task done clears its Blocked. `hq task block`, `unblock`, `link --blocked-by | --after`; `task show` prints the tree with them.
- **Nothing moves on its own** (2026-11-09, T-345): a task changes list or place only when the user moves it, or a session through `hq`. A done task stays where it is.
- **Review** is no status (2026-11-06): a note whose front matter says `status: review` reads as doing. On the first vault scan each overview task still in Review gets an Updates row, "T-12 was in Review: <reason>", linked to it; its `review`, `review_by` and `review_at` keys go the next time HQ writes the note.

### Session (SwiftData `SessionRecord`)

A Claude `session_id` with its name (the latest of the user's rename in HQ, the name HQ gave a session it started, and a /rename in Claude Code (`custom-title`, kept as `renamed` so an old one never comes back over a later rename in HQ); else Claude's `ai-title`, else the first prompt), state, cwd, repo, branch, origin, pid and tty, and the cockpit's fields: `order`, `closedAt`, `faceSalt`, `faceID` (the session whose face it wears, after /clear), `links` (PR URLs it printed). Ended (SessionEnd, or the pid exits) sets `closedAt`; Resume clears it and appends the session to the grid.

Teams (v14, 2026-11-11): `parentID`, the session that started it (`hq session new` from a session, Start a Session with a Parent, Move Under), and `role`, the name of the role note it started with. HQKit's `SessionTree` reads the teams: a parent that isn't there, or a loop, reads as top level; the grid shows the top-level sessions, and a closed one stays, faded, while a session under it is open, then leaves with the last one for Closed Sessions. After /clear the new conversation keeps its parent and role and leads the sessions the old one started. Move Under and Make Root take Undo; a session never goes under its own team. The grid orders the top-level sessions by their `order`; a team's sessions keep theirs among their siblings. A drop between cards or rows, Move Above, Move Below and ⇧ with the arrows place a session under a parent (none: the grid) before or after a sibling, renumbering that parent's sessions 1, 2, 3…: one Undo step that puts back every parent and order it touched (`placeSession`). The team shown open (`openTeam`, one at a time) isn't stored.

Task ↔ session links live in the task notes (`sessions:`), many to many. They are made by `hq` commands from a session, Start Session on a task, a task dropped on a card, and Link to… in a modal.

### Role: `<vault>/hq/roles/<Name>.md`

```yaml
---
color: indigo           # a label color; HQ writes it, as `line`
line: Leads a story and keeps its task tree small and current. Never writes the code.
---
You lead a story: the task you were given and everything under it. …
```

(v14, 2026-11-11.) The note's name is the role's, unique with case ignored, and its body is the text a session started with it gets (§7). Read at each vault scan like files, so an edit in Obsidian reaches HQ; every change in HQ or `hq` writes the note (a rename renames it and the `role` of the sessions that have it; Delete sends it to the Trash, with Undo; other keys keep their text). Leader and Worker ship with HQ: each is written once, when its note is missing (`roles.shipped` in the preferences remembers it, per vault), so one the user deletes stays deleted; Restore Default brings back a shipped role's color, line and text. A session whose role is gone keeps the text it started with and loses the chip.

### File and artifact

Files are notes under `<vault>/hq/files/` with `sessions:` and `tasks:` in their front matter. Artifacts (`ArtifactRecord`) hold the URL, title, session and `tasks`. A file written or an artifact published by a session is linked to the session, and to its task when it works on exactly one.

### Notifications and seen

`notifications.json`, beside the store, written by the app only: the rows (`Notice`: kind session, GitHub or reminder; level important or update; its source, a session id or a PR's URL; the text; how many events merged into it; its links as selection keys; when; when read; when due, while in Later; a PR's or an issue's title as it notified, T-360), when the user last opened the center (the bell breathes for what needs them after it), the GitHub event keys already turned into rows (kept 30 days, longer than the longest lookback, so nothing notifies twice). Read rows go after two weeks. Needs You = the sessions that wait on the user plus the unread important rows; Updates = the unread update rows; `hq status` reports both as `needsYou` and `updates`.

`SeenRecord(key, seenAt)` keeps what the user acknowledged: `review:<url>` (Mark Reviewed, until the PR's next commit or the next time the user's review is asked) and `blink:<session id>` (a card stops breathing until its next state). Sessions keep their own unread flag (done after Stop, until the user opens them, or looks at their terminal: while Ghostty is in front, HQ reads its focused tty every 2.5 s and a done session on it is read). Nothing else is new or seen.

### GitHub

`gh auth token`, kept in memory, fetched again on a 401. A poll asks for PRs that request the user's review directly (`user-review-requested:@me`, not team requests), the open PRs they reviewed, their own open PRs, and the PRs and issues linked to a task, a session, an unread notification or the open modal (`resource(url:)`, up to 60 a poll, 2026-11-11: first the ones never read and those of the modal, open tasks, live sessions and unread notifications, up to 40; then the others, done tasks' newest first, least recently asked first, so every link comes in turn; a merged or closed one is asked again once a day; what a poll doesn't ask keeps its last answer); with each PR, its last 5 comments and its reviews' text, each author with its type, to tell bots apart. GitHub stops a query at 10 s, and all of it in one ran past that (2026-11-10). So a poll is several GraphQL queries sent together: each search alone, then the linked items 20 at a time. If one fails, the poll fails and keeps its last answer, and the log says why. Every 2 minutes while HQ's window is on screen (in front or not: the user keeps it beside Ghostty, T-366; every 60 s until 2026-11-10, when a poll took GitHub several seconds of the 60 s of GraphQL time it allows a user each minute), 5 minutes otherwise; when it becomes active or comes back on screen, only if the last poll started a minute ago or more (2026-11-11: not at every click into HQ); 5 s after a PR's page closes or sends a form (a review submitted). After an error it backs off (doubling, up to 30 minutes), and only that retry and Refresh ask until a poll works. GitHub's rate limit, read from each answer's headers: below 100 points left, or told to wait (`retry-after`), no poll before the reset. A poll's answers are read and compared, and the cache written, off the main thread (`HQKit.GitHubPoll` holds the pace). PR ↔ session: a PR URL in the session's Bash output, or a PR whose head branch and repository match the session's. PR ↔ task: the task's `links`. Test runs use fixtures (`HQ_GITHUB=fixtures`).

### Slack

A user token pasted in Settings › Slack, kept in the Keychain (`io.github.co42.hq.slack`); read-only (T-312). A Slack permalink (a message, a reply in a thread, a channel: `SlackLink` in HQKit) on a task's `links` or a reminder's links is its own kind of link (`ModalRoute.slack`) and opens as a click on it does: the browser hands it to the Slack app at the message, the thread or the channel (T-335). HQ reads what it points to once, when it's linked or at launch: `conversations.info` (the channel's name; none in a direct message), `conversations.history` or `.replies` (the message), `users.info` (its author); kept in `slack.json` beside the store. It follows no conversation and polls nothing. New Task… and New Reminder… take the Slack link on the clipboard, each time until × drops that copy: HQ asks the pasteboard whether it holds a link (`detectedPatterns`, no prompt) and reads it only then. Test runs use fixtures and never reach Slack. The plan for the rest (a safety net for unread messages, Make Task from any row): "Slack in HQ plan" in HQ's files, T-297.

## 6. Sessions

- **Discovery**: a session appears with its first hook event. Its transcript is read best effort for the name only.
- **Open**: running in a Ghostty terminal (matched by `tty`): `focus` it; a background session (`claude --bg`: `claude agents --json` lists it with `kind: background` and the handle it takes) has no Ghostty terminal: the only Ghostty terminal titled with its name (after Claude's status glyph) whose tty runs Claude, since an agent-view viewer shows no session in its arguments or sockets; else its modal; running elsewhere: say so; ended: a new Ghostty tab with `claude --resume <id>`, typed then Return. Close Session: `/exit` in its terminal, or `claude stop <handle>` for a background session, run as the session's own Claude binary.
- **Empty sessions**: a session with no prompt, name, title, link or task is off the grid while it runs outside Ghostty, and its record goes when it ends (and at each vault read for one that ended before): the claude daemon's spares (`~/.claude/daemon.log`: `bg claimed-spare … (spare)`, then `killed`) run the plugin's hooks like any Claude.
- **Start**: from a task, a PR or New Session…: a name, a folder and a first message, then a Ghostty tab running `claude --session-id <uuid> --name '<name>' "$(cat '<prompt file>')"`. hq knows the id up front, so the card and the task link exist from the start. A session started under another opens as a tab in that one's Ghostty window (the window that has its tty), else in the front window (v14). The form also takes a role, a parent and a **History** (v14, T-408; it replaced Fork): with a history, `claude --resume <history> --fork-session --session-id <uuid> --name '<name>'`, the same way, so it starts with that session's conversation so far and still gets its own role, task and first message. Start Session from Its History… fills the form with that session as History, its parent and role, and its name marked ⑂.
- **Close** (2026-11-11): a running session at its prompt (idle, done, failed) gets `/exit` and Return typed into its terminal; a working or compacting one gets Escape first, which stops the turn, then `/exit`. One that waits on the user gets no keys, since Return would answer its prompt: HQ says so and offers Focus. Once its Claude has quit, the terminal closes (its tab with it when alone), if that happens within 15 s: a `/exit` that didn't take never closes the terminal later. A card whose Claude never reported (no pid, no transcript: a start or resume that never ran) has nothing to resume and goes; an ended card still on the grid goes to Closed Sessions.
- **Not started**: at launch, a card whose Claude never reported and that HQ started over a minute ago goes. A resume whose tab doesn't open puts the card back in Closed Sessions.
- **/clear** (2026-11-11): Claude ends the session (SessionEnd `clear`) and goes on under a new `session_id` (SessionStart `clear`, same pid). The new id takes over the card: its place, face, name, PR links and the tasks it works on that aren't done, so its `hq` task commands work as before; the old id stays in Closed Sessions, still linked to its tasks.
- **Subagents**: a subagent's or teammate's events carry `agent_id`. A wait remembers which thread raised it (none: the main thread), and only a tool event from that thread ends it; a subagent's tool event doesn't end a failure or a compaction either. Stop, a prompt and an interrupt end any wait.
- **Replay**: an event `hq hook` kept while HQ was off is older than any live one. Replayed after a live event that already moved the session, it changes nothing but the PRs and pages it adds.
- **Interrupted**: Esc or Ctrl+C in the terminal sends no Stop. HQ reads the transcript's "[Request interrupted by user…]" (best effort) and a working or waiting session goes idle. A prompt cancelled before any answer (or while Claude thinks, or blocked by a hook, or a queued one cancelled) leaves nothing in the transcript (2026-11-11, T-371): while a session works, HQ reads Claude Code's own record of it every 2 s, `~/.claude/sessions/<pid>.json` (best effort, its format is internal), and a session whose Claude says `"status": "idle"` goes idle once that and Working have both held 3 s, so a Stop just behind wins. Each one is logged in `sessions.log`.

| Event | State |
|---|---|
| SessionStart | idle |
| UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure | working; a subagent's tool event ends no wait it didn't raise, no failure, no compaction |
| PreToolUse AskUserQuestion / ExitPlanMode | needs you: question / plan, until a tool event from the same thread |
| PermissionRequest, Notification `permission_prompt`, Elicitation | needs you: permission, unless already question or plan, until a tool event from the thread that asked |
| Stop | done, unread until the user opens it, looks at its terminal or sends the next prompt; it notifies nothing |
| StopFailure | failed |
| PreCompact → PostCompact | compacting → the previous state |
| SessionEnd (`clear` too: see /clear), pid exit | ended |

Known gap: Esc, a rejection or an interrupt sends nothing, so the state holds until the next event. Cards show how long a state has lasted, so a stale one is visible.

## 7. Claude integration

Plugin `plugin/`, bundled into `HQ.app/Contents/Resources/Plugin` by `build.sh` and installed globally from there (`tools/install-plugin.sh`, also Setup › Install). Claude Code runs it from its own copy per version: a change under `plugin/` needs a version bump in `plugin.json` and `tools/install-plugin.sh`, and reaches sessions started after that.

- `hooks/hooks.json`: the events above → `${CLAUDE_PLUGIN_ROOT}/bin/hq hook`, timeout 2 s. PreToolUse matcher `AskUserQuestion|ExitPlanMode`; PostToolUse unfiltered (artifacts, PR URLs).
- Skills, without `allowed-tools`, two since plugin 0.10.0 (2026-11-11: the start text names both, and a rule lives in one place): `hq` (doing the moment work starts, each subtask too; a task read with its subtasks before the work and again between pieces; the description one current document, changed one part at a time; a project on every task; what the user must check stays doing with an `hq notify`, and they move it to done; new tasks on Tasks, the Backlog only when the user says so; links on the task they're for; `--important` only for a ping; `hq remind`; Blocked and blocked by, unasked, the moment a task waits; since 0.11.0 the sessions it starts, under it and reporting to it, `hq ls roles` before `--role`, `--beside` for a handoff), `hq-files` (notes linked to their task, named by `file new`; `hq notify` when one is ready to read). The start text says which to load before what, and names a reminder due on the session's tasks.
- **The start text** (SessionStart's stdout, at every source: startup, resume, clear, compact, fork; the hook has no matcher): HQ's lines (it tracks the session, its tasks, the session that started it, which it reports to and messages with SendMessage by its name, how many sessions it started, the skills), then its role's line and text, read from the note at that moment, so an edited role reaches its sessions when they next resume or compact. Claude Code takes 10,000 characters from a hook; past that it hands Claude a file and a 2,000-character preview (checked 2026-11-11). So the whole stays under it: a role's text up to `roleTextLimit` (8,000, where the role editor warns) reaches whole beside HQ's longest lines, and a longer one is cut with a line that says `hq role show` prints it whole. With HQ off, the hook prints nothing: the session starts without them.
- `bin/hq` runs the linked binary; for `hook` it exits 0 even while the link is missing (a build in progress).

```
hq status                                      # whether HQ runs, its build and since when; needsYou, updates, how many sessions, tasks, files, artifacts
hq ctx [--all]                                 # this session's role, who started it, its tasks, every session it started and theirs, closed ones too (role, state, task), what is doing in its project (--all: everywhere), recent files, other sessions
hq ls tasks [--overview|--backlog] [--parent T-n] [--project p] [--tag t] [--all]
hq ls sessions [--here] [--tree] [--all]       # --here: the sessions whose folder is in this repository; --tree: each team under its top session; --all: closed ones too, in their teams
hq ls prs | files | artifacts | projects | reminders | roles
hq ls notifications [--all]                    # Needs You (waiting sessions, review requests, rows), Updates, Later; --all adds Earlier
hq project edit Name [--folder dir] [--repo owner/name,…]
hq task add "Title" [--project p] [--tag t] [--parent T-n] [--backlog] [--status s] [--link item,…] [--body -]   # end of Tasks; a subtask takes the parent's project
hq task move T-n todo|doing|done|backlog [--list tasks|backlog]   # review is refused, pointing to hq notify
hq task edit T-n [--title …] [--body - [--force]] [--section S --body -] [--replace old --with new] [--project p] [--add-tag t] [--remove-tag t] [--parent T-m|none]
hq task tick T-n "start of the item" [--untick]   # one checklist item; prints "2 of 4 ticked"
hq task show T-n [T-m …] [--deep|--brief|--body]  # parents, reminders, description, subtasks (--deep: their descriptions), links; no paths
hq task link T-n <url | T-m | session id | note name>
hq task unlink T-n <the same item>
hq task delete T-n [--yes]                     # with its subtasks, to the Trash; without --yes: what it would delete
hq task history T-n                            # what sessions changed in it through hq, the last 30 days
hq task undo T-n [--yes]                       # put back every task its latest hq change touched
hq file new "Title" [--task T-n] [--body -]    # "<date> - Title"; a dated title keeps one date
hq file write <name> [--body - [--append]] [--section S --body -] [--replace old --with new]
hq file show <name>                            # its name, path or title
hq file delete <name> [--yes]                  # to the Trash; without --yes: what it would delete
hq artifact add <url> --title t [--date d] [--task T-n]     # one HQ didn't capture; a ?sk= share key is dropped
hq session new "Name" [--task T-n] [--role R] [--parent <session> | --parent none | --beside] [--history <session>] [--cwd dir] [--message -]
                                               # from a session: under it, in its Ghostty window; --beside: at its level (a handoff)
hq session edit <session> --parent <session>|none   # Move Under, Make Root; never under its own team
hq session show <id>                           # its id or 6 characters of it; --parent and --history take a name too
hq session close <session>                     # one under this session (any depth), as Close Session: input emptied, /exit; refused while it waits on the user
hq session resume <session>                    # a closed one under this session, as Resume: a new tab in its parent's Ghostty window, its place in the team kept
hq role show | new | edit | delete <name>      # new and edit: [--name n] [--line l] [--color c] [--body -]; delete: to the Trash, without --yes what it would do
hq notify "…" [--important] [--link T-n,<url>,…] [--task T-n]   # Updates; --important: Needs You, with a banner
hq remind "…" --at <when> [--important] [--link …] [--task T-n] # Later until <when> (16:00, in 2h, tomorrow at 15:00, friday 3pm); a word it doesn't read is refused, the reply says the time it read
hq notification done|delete <id> [--not-mine]              # one this session sent or set; the id's first 8 characters do
hq hook                                        # used by the plugin
```

Every action the UI has on a task, file or artifact has its `hq` command, and every command that changes a task goes through the same check that the session is on it (`--not-mine` otherwise; a needless `--not-mine` is answered "T-12 is yours already" on stderr, so it doesn't become a reflex). `hq help --json` is the commands' schema, each with the shape of its result (`output`, the `JSON:` line of `hq help <command>`): `tools/docs-lint.sh` checks the docs, the skills, the help texts and the hook's start text against it.

What sessions read: the text output is short and has no vault paths (a note goes by the name `hq file show` takes); a list cut at its page ends with `50 of 112: --limit 200, or --offset 50 for the next` (tasks under `--overview`, `--project` or `--parent` aren't cut); `-q` prints only the key of what a command made or listed. The parser takes `--name value` and `--name=value`; a list option (`--link`, `--tag`, `--task` on notify) given twice keeps both, any other given twice with two values is refused; an empty argument says so ("`<task>` is empty: check the variable you passed"); `-` reads stdin for `--body` and `--message` only. A retired flag (`--type`, `--now`, `--reason`) answers one line on stderr and the command runs; a retired command says what replaced it, and runs it when it can (`hq link <item> <task>` runs `hq task link`). <!-- docs: ok names the retired flags and command hq still answers -->

Partial edits: `task tick`, `task edit --section` and `--replace` change one part of a description and keep every other byte; each fails when its target isn't there, or `--replace` finds it more than once. `task edit --body` alone replaces it all, and is refused (`stale`) when the description changed since this session last read it: `task show` (with its description) and the session's own writes record what it read, per session and task, in memory; `--force` writes over it. `file write` takes the same `--section` and `--replace`.

Builds: every reply carries the running app's build (`app`), fixed at launch. When it is older than the `hq` binary on disk (a release installed, HQ not restarted), `hq` says so once per session on stderr.

`hq hook` reads stdin, adds Claude's pid, its tty and whether Ghostty is an ancestor, sends the event over the socket with a 1 s timeout and exits 0. With nothing listening (HQ is off) it appends the event, without what HQ never reads (tool output, file contents), to `pending-hooks.jsonl` beside the store (`HookSpool`); the app replays it at launch, and again 3 s later, keeping every state event, the tool calls it reads something from and each session's last tool call, older than 7 days dropped. Commands find their session from `CLAUDE_CODE_SESSION_ID`. Commands from the socket don't register Undo, and nothing they change notifies on its own: a session tells the user with `hq notify`. `hq notify` without `--link` links the session's open tasks and what it made since its last notification; a second one before the user reads the first updates that row.

## 8. Iterations

The cockpit was built in one go from the T-46 plan (2026-11-04). Since then HQ grows by iterations: a story task "HQ - Iteration vN" whose subtasks are the work, built on a branch `vN` and shipped in batches the user tries in their own HQ. [ITERATION.md](ITERATION.md) says how one runs, from start to release to close; [RELEASE_NOTES.md](RELEASE_NOTES.md) says what each version shipped.

## 9. To check during the build 🔍

- `hq hook` latency with the app binary as CLI. Over ~30 ms → a Foundation-only `hq-hook` target.
- Ghostty ids across a Ghostty restart; `focus` when Ghostty is on another Space.
- Gap feedback in a view-based `NSOutlineView` inside SwiftUI's scroll view: `.gap` is on and every drop lands right in the UI test, but the parting rows and the drop highlight need a look with a real drag (synthetic drags don't draw).
- GitHub's limits over a working day: a poll's few queries every 2 minutes, beside the user's sessions' own `gh` calls.

## 10. Risks

| Risk | Mitigation |
|---|---|
| SwiftUI page plus AppKit outline and grid: scrolling and sizing | No inner scroll views; each reports its height; checked with `APP_SEED=large` |
| Inline editing fights drag and selection | Drag starts outside the field editor; a click on the title edits |
| The real vault migration | Backup first, idempotent planner, tested on a copy, only keys HQ owns |
| GitHub rate limits or outages | A few small queries every 2 minutes, back-off, cached data, a quiet banner |
| Sessions started with the old plugin | Hook protocol unchanged; they keep reporting |
| Transcript format is internal | Best effort; hooks are the source of live data |
| iCloud vault: sync delays, conflict copies | FSEvents plus a rescan when HQ becomes active; `* 2.md` conflict copies never indexed twice |

## 11. Repo

```
hq/
  CLAUDE.md  PLAN.md  DESIGN.md  ITERATION.md  RELEASE_NOTES.md  README.md
  Package.swift  build.sh  Info.plist.in
  Icon/              AppIcon.icon (Icon Composer); compiled into Resources/ (not in git)
  Sources/HQ/        app: App.swift, Views/, DesignKit/, Agent/ (CLI + socket), Ghostty.swift, GitHub.swift, Snapshot.swift, SelfTest.swift, UITest.swift
  HQKit/            its own package (swift test --package-path HQKit), no UI: model rules, front matter, markdown, faces, GitHub parsing, hook events, state machine
  Vendor/mermaid/    mermaid.js 11.17.2 and its MIT license, copied into the bundle by build.sh
  HQKit/Tests/       unit tests and GitHub fixtures
  plugin/            .claude-plugin/plugin.json, hooks/, skills/, bin/hq
  .claude-plugin/marketplace.json
  tools/             check.sh (every check), snap.sh, selftest.sh, uitest.sh, grid-lint.sh, perf-lint.sh, docs-lint.sh, check-layout.swift, perf.sh, launch.sh, install-plugin.sh
```

## 12. AppKit inside SwiftUI, Swift 6 at AppKit's edges

Clicks that land nowhere, rows that vanish and crashes at these seams came back in nearly every iteration up to v8. The fixes that held:

| Where | Do | Because |
|---|---|---|
| An AppKit view hosted in the page (the outline, the session grid) | its container sets its frame in `layout`; never edge constraints | constraints stopped following the container: rows past an opened fold took no clicks (T-207) |
| A table or collection inside SwiftUI's scroll view | its `enclosingScrollView` is nil; no scroll view of its own | it laid itself out to the page's scroll view and put cards past the edge (T-255) |
| A control that acts on the press | AppKit takes the mouseDown and its release | a SwiftUI ancestor saw the mouseUp and unselected the row (b75d851) |
| A single click beside a double-click | `ClickTarget` or `SelectOpen`, never `onTapGesture(count: 2)` | SwiftUI holds the single click for the double-click interval |
| Rows during a drag | change nothing until the drag ends | a row change during a gap drag crashed in AppKit |
| Undo | one grouping per event, closed by AppKit | a manual `endUndoGrouping` crashed |
| KVO, notifications, timers, WebKit and `UNUserNotificationCenter` delegates, called on the main thread | a `nonisolated` method or closure, then `MainActor.assumeIsolated { … }` | the module's default isolation is the main actor |
| A completion called on a background queue (`NSItemProvider` loads) | never `assumeIsolated`; hop with `Task { @MainActor in … }` | `_dispatch_assert_queue_fail` |
| AppleScript, file reads off the main thread | `nonisolated static` functions on value types marked `Sendable` | |
| A method passed as a value (`.map(model.f)`) | a closure: `.map { model.f($0) }` | the method reference loses its isolation |
| An observer to remove | `isolated deinit` | |
| A cache under `@ObservationIgnored` | reads the observed values it depends on | a stale cache showed a deleted file (T-183) |
| A note read empty while iCloud writes it | never trusted: read again | a subtask lost its parent (T-236) |
