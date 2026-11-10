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
| Ghostty | AppleScript in-process (`NSAppleScript`). Automation permission |
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
| Hooks ✅ (S4, Claude Code 2.1.317) | Command hooks get the event JSON on stdin; SessionStart stdout reaches the model as context. Common fields: `session_id`, `transcript_path`, `cwd`, `hook_event_name`. `/clear` = SessionEnd(`clear`) then SessionStart(`clear`) with a new `session_id`. AskUserQuestion and ExitPlanMode also raise PermissionRequest and a `permission_prompt` Notification. Nothing fires on Esc, rejection or interrupt. `idle_prompt` 60 s after activity. Stop carries `last_assistant_message`; PermissionRequest carries `tool_name` and `tool_input`; PreToolUse ExitPlanMode carries `planFilePath`. Plugin `bin/` is last on the Bash PATH and absent from the hook PATH. A skill with `allowed-tools` needs approval to load: don't use it |
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

- `Sources/HQKit`: no UI. Task statuses, the task tree and its operations, the vault migration planner, front matter, markdown blocks and checkbox toggling, face specs and their palette, GitHub parsing and link rules, hook events and the session state machine.
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
sessions: [2f1c9e0a-…]
created: 2026-11-03
---
The description, in markdown. Older dated notes stay here as paragraphs.
```

- `n` is the highest existing plus one. All other keys and the body keep their exact text.
- `HQKit.TaskTree`: built from (parent, list, order); a missing parent or a cycle puts a task at the top level. Operations return the notes that change: insert after, insert first child, indent, outdent, move among siblings, move to a list, drop (on a row: last child; between rows: sibling at that index; on a list header: last top-level task), delete with the subtree. Never into its own subtree. Order is fractional: the midpoint between neighbors, the siblings renumbered when a gap falls under 1e-6.
- **Migration** (once, then idempotent; `HQKit.TaskMigration` plans it, the app applies it after zipping `<vault>/hq/tasks` to `~/Library/Application Support/HQ/Backups/tasks-<date>.zip`): `status: backlog` → `todo` + `list: backlog`; `todo` → `list: backlog`; `doing`, `review` → `list: overview`; `done` → `list: backlog` with `done:` from the file's modification date. A missing type stays missing.
- **Nothing moves on its own** (2026-11-09, T-345): a task changes list or place only when the user moves it, or a session through `hq`. A done task stays where it is.
- **Review** is no status (2026-11-06): a note whose front matter says `status: review` reads as doing. On the first vault scan each overview task still in Review gets an Updates row, "T-12 was in Review: <reason>", linked to it; its `review`, `review_by` and `review_at` keys go the next time HQ writes the note.

### Session (SwiftData `SessionRecord`)

A Claude `session_id` with its name (the latest of the user's rename in HQ, the name HQ gave a session it started, and a /rename in Claude Code (`custom-title`, kept as `renamed` so an old one never comes back over a later rename in HQ); else Claude's `ai-title`, else the first prompt), state, cwd, repo, branch, origin, pid and tty, and the cockpit's fields: `order`, `closedAt`, `faceSalt`, `links` (PR URLs it printed). Ended (SessionEnd other than `clear`, or the pid exits) sets `closedAt`; Resume clears it and appends the session to the grid.

Task ↔ session links live in the task notes (`sessions:`), many to many. They are made by `hq` commands from a session, Start Session on a task, a task dropped on a card, and Link to… in a modal.

### File and artifact

Files are notes under `<vault>/hq/files/` with `sessions:` and `tasks:` in their front matter. Artifacts (`ArtifactRecord`) hold the URL, title, session and `tasks`. A file written or an artifact published by a session is linked to the session, and to its task when it works on exactly one.

### Notifications and seen

`notifications.json`, beside the store, written by the app only: the rows (`Notice`: kind session, GitHub or reminder; level important or update; its source, a session id or a PR's URL; the text; how many events merged into it; its links as selection keys; when; when read; when due, while in Later; a PR's or an issue's title as it notified, T-360), when the user last opened the center (the bell breathes for what needs them after it), the GitHub event keys already turned into rows (kept 30 days, longer than the longest lookback, so nothing notifies twice). Read rows go after two weeks. Needs You = the sessions that wait on the user plus the unread important rows; Updates = the unread update rows; `hq status` reports both as `needsYou` and `updates`.

`SeenRecord(key, seenAt)` keeps what the user acknowledged: `review:<url>` (Mark Reviewed, until the PR's next commit) and `blink:<session id>` (a card stops breathing until its next state). Sessions keep their own unread flag (done after Stop, until the user opens them, or looks at their terminal: while Ghostty is in front, HQ reads its focused tty every 2.5 s and a done session on it is read). Nothing else is new or seen.

### GitHub

`gh auth token`, kept in memory, fetched again on a 401. A poll asks for PRs that request the user's review directly (`user-review-requested:@me`, not team requests), the open PRs they reviewed, their own open PRs, and every PR or issue linked to a task, a session or an unread notification (`resource(url:)`, up to 60); with each PR, its last 5 comments and its reviews' text, each author with its type, to tell bots apart. GitHub stops a query at 10 s, and all of it in one ran past that (T-41, 2026-11-10). So a poll is several GraphQL queries sent together: each search alone, then the linked items 20 at a time. If one fails, the poll fails and keeps its last answer, and the log says why. Every 60 s while HQ's window is on screen (in front or not: the user keeps it beside Ghostty, T-366), 5 minutes otherwise; at once when it becomes active or comes back on screen after a minute; 5 s after a PR's page closes or sends a form (a review submitted); back off on errors and rate limits. PR ↔ session: a PR URL in the session's Bash output, or a PR whose head branch and repository match the session's. PR ↔ task: the task's `links`. Test runs use fixtures (`HQ_GITHUB=fixtures`).

### Slack

A user token pasted in Settings › Slack, kept in the Keychain (`io.github.co42.hq.slack`); read-only (T-312). A Slack permalink (a message, a reply in a thread, a channel: `SlackLink` in HQKit) on a task's `links` or a reminder's links is its own kind of link (`ModalRoute.slack`) and opens as a click on it does: the browser hands it to the Slack app at the message, the thread or the channel (T-335). HQ reads what it points to once, when it's linked or at launch: `conversations.info` (the channel's name; none in a direct message), `conversations.history` or `.replies` (the message), `users.info` (its author); kept in `slack.json` beside the store. It follows no conversation and polls nothing. New Task… and New Reminder… take the Slack link on the clipboard, each time until × drops that copy: HQ asks the pasteboard whether it holds a link (`detectedPatterns`, no prompt) and reads it only then. Test runs use fixtures and never reach Slack. The plan for the rest (a safety net for unread messages, Make Task from any row): "Slack in HQ plan" in HQ's files, T-297.

## 6. Sessions

- **Discovery**: a session appears with its first hook event. Its transcript is read best effort for the name only.
- **Open**: running in a Ghostty terminal (matched by `tty`): `focus` it; a background session (`claude --bg`: `claude agents --json` lists it with `kind: background` and the handle it takes) has no Ghostty terminal: the only Ghostty terminal titled with its name (after Claude's status glyph) whose tty runs Claude, since an agent-view viewer shows no session in its arguments or sockets; else its modal; running elsewhere: say so; ended: a new Ghostty tab with `claude --resume <id>`, typed then Return. Close Session: `/exit` in its terminal, or `claude stop <handle>` for a background session, run as the session's own Claude binary.
- **Empty sessions**: a session with no prompt, name, title, link or task is off the grid while it runs outside Ghostty, and its record goes when it ends (and at each vault read for one that ended before): the claude daemon's spares (`~/.claude/daemon.log`: `bg claimed-spare … (spare)`, then `killed`) run the plugin's hooks like any Claude.
- **Start**: from a task, a PR or New Session…: a name, a folder and a first message, then a Ghostty tab running `claude --session-id <uuid> --name '<name>' "$(cat '<prompt file>')"`. hq knows the id up front, so the card and the task link exist from the start. **Fork**: `claude --resume <id> --fork-session --session-id <uuid> --name '<name> ⑂'` in a new Ghostty tab in the session's folder, the same way.
- **Close**: a running session gets `/exit` and Return typed into its terminal; once its Claude has quit, the terminal closes (its tab with it when alone).
- **Interrupted**: Esc or Ctrl+C in the terminal sends no Stop. HQ reads the transcript's "[Request interrupted by user…]" (best effort) and a working or waiting session goes idle.

| Event | State |
|---|---|
| SessionStart | idle |
| UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure | working |
| PreToolUse AskUserQuestion / ExitPlanMode | needs you: question / plan, until that tool's PostToolUse |
| PermissionRequest, Notification `permission_prompt`, Elicitation | needs you: permission, unless already question or plan |
| Stop | done, unread until the user opens it, looks at its terminal or sends the next prompt; it notifies nothing |
| StopFailure | failed |
| PreCompact → PostCompact | compacting → the previous state |
| SessionEnd (reason ≠ `clear`), pid exit | ended |

Known gap: Esc, a rejection or an interrupt sends nothing, so the state holds until the next event. Cards show how long a state has lasted, so a stale one is visible.

## 7. Claude integration

Plugin `plugin/`, bundled into `HQ.app/Contents/Resources/Plugin` by `build.sh` and installed globally from there (`tools/install-plugin.sh`, also Setup › Install). Claude Code runs it from its own copy per version: a change under `plugin/` needs a version bump in `plugin.json` and `tools/install-plugin.sh`, and reaches sessions started after that.

- `hooks/hooks.json`: the events above → `${CLAUDE_PLUGIN_ROOT}/bin/hq hook`, timeout 2 s. PreToolUse matcher `AskUserQuestion|ExitPlanMode`; PostToolUse unfiltered (artifacts, PR URLs).
- Skills, without `allowed-tools`: `hq` (what HQ is, the CLI, telling the user: `hq notify` when something is ready to look at, `--important` only for a ping they asked for or when blocked on them, `hq remind`), `hq-tasks` (one task per piece of work the user would track, in its project; subtasks for parts the user wants to see; `doing` when starting; the description kept current by editing it; when the user must check something (most work), the task stays doing and `hq notify` tells them, and the user moves it to done; `done` only when nothing needs their look; new tasks at the end of Tasks, the Backlog only when the user says so; the task read again between pieces, since the user edits it and adds subtasks), `hq-files` (notes linked to their task; `hq notify` when one is ready to read).

```
hq status                                      # whether HQ runs; needsYou, updates, and how many sessions, tasks, files, artifacts
hq ctx                                         # this session's tasks, the overview's Doing, recent files, sibling sessions
hq ls tasks [--overview|--backlog|--all] [--project p] [--tag t]
hq ls sessions | prs | files | artifacts | projects
hq ls notifications [--all]                    # Needs You, Updates, Later; --all adds Earlier
hq project edit Name [--folder dir] [--repo owner/name,…]
hq task add "Title" [--project p] [--tag t] [--parent T-n] [--backlog] [--body -]   # end of Tasks; --backlog: top of the Backlog
hq task move T-n todo|doing|done|backlog       # review is refused, pointing to hq notify
hq task edit T-n [--title …] [--body -] [--project p] [--add-tag t] [--remove-tag t] [--parent T-m|none]
hq task show T-n                               # parents, description, subtasks, links
hq task link T-n <url | T-m | session id | path>
hq task unlink T-n <the same item>
hq task delete T-n [--yes]                     # with its subtasks, to the Trash; without --yes: what it would delete
hq task history T-n                            # what sessions changed in it through hq, the last 30 days
hq task undo T-n [--yes]                       # put back every task its latest hq change touched
hq link <url | path> T-n
hq file new "Title" [--task T-n] [--body -]
hq file write <path> --body - [--append]
hq file show <path>
hq file delete <path> [--yes]                  # to the Trash; without --yes: what it would delete
hq artifact add <url> --title t [--date d] [--task T-n]     # one HQ didn't capture; a ?sk= share key is dropped
hq session new "Name" [--task T-n] [--cwd dir] [--message -]
hq notify "…" [--important] [--link T-n,<url>,…]          # Updates; --important: Needs You, with a banner
hq remind "…" --at <when> [--important] [--link …]        # Later until <when> (16:00, in 2h, tomorrow 9:00, monday)
hq notification done|delete <id> [--not-mine]              # one this session sent or set; the id's first 8 characters do
hq hook                                        # used by the plugin
```

Every action the UI has on a task, file or artifact has its `hq` command, and every command that changes a task goes through the same check that the session is on it (`--not-mine` otherwise). `hq help --json` is the commands' schema: `tools/docs-lint.sh` checks the docs and skills against it.

`hq hook` reads stdin, adds Claude's pid, its tty and whether Ghostty is an ancestor, sends the event over the socket with a 1 s timeout and exits 0. With nothing listening (HQ is off) it appends the event, without what HQ never reads (tool output, file contents), to `pending-hooks.jsonl` beside the store (`HookSpool`); the app replays it at launch, and again 3 s later, keeping every state event, the tool calls it reads something from and each session's last tool call, older than 7 days dropped. Commands find their session from `CLAUDE_CODE_SESSION_ID`. Commands from the socket don't register Undo, and nothing they change notifies on its own: a session tells the user with `hq notify`. `hq notify` without `--link` links the session's open tasks and what it made since its last notification; a second one before the user reads the first updates that row.

## 8. Iterations

The cockpit was built in one go from the T-46 plan (2026-11-04). Since then HQ grows by iterations: a story task "HQ - Iteration vN" whose subtasks are the work, built on a branch `vN` and shipped in batches the user tries in their own HQ. [ITERATION.md](ITERATION.md) says how one runs, from start to release to close; [RELEASE_NOTES.md](RELEASE_NOTES.md) says what each version shipped.

## 9. To check during the build 🔍

- `hq hook` latency with the app binary as CLI. Over ~30 ms → a Foundation-only `hq-hook` target.
- Ghostty ids across a Ghostty restart; `focus` when Ghostty is on another Space.
- Gap feedback in a view-based `NSOutlineView` inside SwiftUI's scroll view: `.gap` is on and every drop lands right in the UI test, but the parting rows and the drop highlight need a look with a real drag (synthetic drags don't draw).
- The rate limit of one aliased query a minute, over a working day.

## 10. Risks

| Risk | Mitigation |
|---|---|
| SwiftUI page plus AppKit outline and grid: scrolling and sizing | No inner scroll views; each reports its height; checked with `APP_SEED=large` |
| Inline editing fights drag and selection | Drag starts outside the field editor; a click on the title edits |
| The real vault migration | Backup first, idempotent planner, tested on a copy, only keys HQ owns |
| GitHub rate limits or outages | One aliased query per poll, back-off, cached data, a quiet banner |
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
  Sources/HQKit/     no UI: model rules, front matter, markdown, faces, GitHub parsing, hook events, state machine
  Vendor/mermaid/    mermaid.js 11.17.2 and its MIT license, copied into the bundle by build.sh
  Tests/HQKitTests/  unit tests and GitHub fixtures
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
