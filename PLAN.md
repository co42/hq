# hq — plan

hq is the user's cockpit for a day of work with Claude Code: a native macOS app docked on the right half of the screen, with Ghostty on the left. One page shows their Claude sessions with their faces and live state, the pull requests that wait on them, and their tasks with their Backlog as one outline; anything bigger opens in a sheet over it. hq indexes and links; other apps do the work: Ghostty runs sessions, Obsidian holds the notes, the browser shows artifacts, GitHub holds PRs and issues.

How it looks and behaves: [DESIGN.md](DESIGN.md). The build plan this was rebuilt from: the HQ file "2026-11-04 - HQ cockpit build plan" (T-46).

Legend: ✅ verified on this Mac or in source · 🔍 to check during the build.

## 1. Principles

- **Tailored to the user.** Built from their workflow (Ghostty, Obsidian, worktrees, GitHub), not from another tool. Never look at, copy or model anything on claude-run: not its code, UI, data model, words or skills.
- **One page.** The cockpit is the only view; everything else is a sheet over it. No folders, sidebar, view picker, inspector or comments (2026-11-04).
- **hq never owns a terminal.** The user arranges Ghostty as they like. hq finds a session's terminal and focuses it, or opens a tab to start or resume one.
- **Files are the truth where they exist.** Tasks and files are Obsidian notes; hq writes only the front matter keys it owns. hq's store holds only what has no file: sessions, artifacts, what the user has seen.
- **Hooks never slow Claude.** Fast, always exit 0; the next event repairs a missed one.

## 2. Decisions

| Topic | Decision |
|---|---|
| App | SwiftUI on macOS 27 only (2026-11-05), AppKit where SwiftUI falls short (the outline, the session grid, the Ghostty bridge, text editors). Swift 6.4, a Swift package, no Xcode project |
| Names | App `HQ`, bundle id `io.github.co42.hq`, CLI `hq` |
| Process | One process, the app: store, vault index, hook socket, Ghostty bridge, GitHub poller. Stays alive when its window closes |
| CLI | The app binary is the CLI (bama `agent-cli`): `~/.local/bin/hq` links into the bundle and talks to the running app over a Unix socket. If the app is closed, `hq` opens it in the background; `hq hook` never does |
| Store | SwiftData in `~/Library/Application Support/HQ/`: sessions, artifacts, seen and change records. GitHub's last answer is cached beside it as JSON. Live session state stays in memory |
| Vault | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes`; hq's folder is `hq/` with `tasks/` and `files/`. Front matter read and written line by line (`HQKit.FrontMatter`), so other keys keep their text |
| Claude plugin | `plugin/` in this repo, installed globally through a local marketplace: hooks and skills. `Bash(hq:*)` allowed in `~/.claude/settings.json` |
| Ghostty | AppleScript in-process (`NSAppleScript`). Automation permission |
| GitHub | GraphQL with the token from `gh auth token`, one aliased query per poll, read-only |
| Artifacts | claude.ai links captured from hooks, shown live in a web view with HQ's own claude.ai sign-in |
| Signing | Apple Development certificate, installed to `/Applications/HQ.app` |
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
| Performance ✅ | 500 tasks and 30 sessions (`APP_SEED=large`, the UI test's last group), App Nap off: scrolling at trackpad speed 8 ms median per frame, a search keystroke about 30 ms, a fold 13 ms, a move about 20 ms, Show Descriptions about 75 ms once. With the screen locked, App Nap's timer coalescing triples every measured stall: measure with it off |

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
             │ store: sessions, artifacts, seen, changes    │◄── GraphQL ── api.github.com
             │ vault index: tasks, files (memory)           │◄── FSEvents ── <vault>/hq/
             └──────────────────────────────────────────────┘
```

- `Sources/HQKit`: no UI. Task statuses and types, the task tree and its operations, the vault migration planner, the done rule, front matter, markdown blocks and checkbox toggling, face specs and their palette, GitHub parsing and link rules, hook events and the session state machine.
- `Sources/HQ`: the app. `CockpitView` (the page), `SessionGrid` (`NSCollectionView`), `TaskOutline` (`NSOutlineView`), `ModalHost` (the sheet and its kinds), `DesignKit/` (tokens and parts), `Agent/` (CLI and socket).

## 5. Model

### Task: `<vault>/hq/tasks/T-<n>.md`

```yaml
---
title: Retry budget for blob uploads
status: review          # todo | doing | review | done
type: feature           # story | bug | feature | chore | research | docs (optional: Claude sets it, and adds it where missing)
project: Registry       # optional
tags: [perf]
parent: T-9             # optional: subtasks are their own notes
list: overview          # overview | backlog (top-level tasks only)
order: 3.5              # among siblings
review: PR #418 is ready to merge   # while status is review
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
- **Done rule**: a done top-level task on the overview moves to the top of the Backlog at the first 05:00 local after it was done.

### Session (SwiftData `SessionRecord`)

A Claude `session_id` with its name (the latest of the user's rename in HQ, the name HQ gave a session it started, and a /rename in Claude Code (`custom-title`, kept as `renamed` so an old one never comes back over a later rename in HQ); else Claude's `ai-title`, else the first prompt), state, cwd, repo, branch, origin, pid and tty, and the cockpit's fields: `order`, `hidden`, `closedAt`, `faceSalt`, `links` (PR URLs it printed). Ended (SessionEnd other than `clear`, or the pid exits) sets `closedAt`; Resume clears it and appends the session to the grid.

Task ↔ session links live in the task notes (`sessions:`), many to many. They are made by `hq` commands from a session, Start Session on a task, a task dropped on a card, and Link to… in a modal.

### File and artifact

Files are notes under `<vault>/hq/files/` with `sessions:` and `tasks:` in their front matter. Artifacts (`ArtifactRecord`) hold the URL, title, session and `tasks`. A file written or an artifact published by a session is linked to the session, and to its task when it works on exactly one.

### Seen and changed

`SeenRecord(key, seenAt)` and `ChangeRecord(key, changedAt, by)` with keys `task:T-13`, `file:<id>`, `artifact:<url>`, `gh:<url>`. A change is recorded when it comes through the socket (Claude), a hook (artifact) or GitHub (`updatedAt` moved, for the user's PRs and linked issues). New = `changedAt > seenAt`. Sessions keep their own unread flag (done after Stop, until the user opens them, or looks at their terminal: while Ghostty is in front, HQ reads its focused tty every 2.5 s and a done session on it is read).

### GitHub

`gh auth token`, kept in memory, fetched again on a 401. One GraphQL query per poll: PRs that request the user's review directly (`user-review-requested:@me`, not team requests), the user's open PRs, and every PR or issue linked to a task or session (`resource(url:)`). Every 60 s while HQ is visible, 5 minutes otherwise, at once when it becomes active; back off on errors and rate limits. PR ↔ session: a PR URL in the session's Bash output, or a PR whose head branch and repository match the session's. PR ↔ task: the task's `links`. Test runs use fixtures (`HQ_GITHUB=fixtures`).

## 6. Sessions

- **Discovery**: a session appears with its first hook event. Its transcript is read best effort for the name only.
- **Open**: running in a Ghostty terminal (matched by `tty`): `focus` it; running elsewhere: say so; ended: a new Ghostty tab with `claude --resume <id>`, typed then Return.
- **Start**: from a task, a PR or New Session…: a name, a folder and a first message, then a Ghostty tab running `claude --session-id <uuid> --name '<name>' "$(cat '<prompt file>')"`. hq knows the id up front, so the card and the task link exist from the start.
- **Close**: a running session gets `/exit` and Return typed into its terminal; once its Claude has quit, the terminal closes (its tab with it when alone).
- **Interrupted**: Esc or Ctrl+C in the terminal sends no Stop. HQ reads the transcript's "[Request interrupted by user…]" (best effort) and a working or waiting session goes idle.

| Event | State |
|---|---|
| SessionStart | idle |
| UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure | working |
| PreToolUse AskUserQuestion / ExitPlanMode | needs you: question / plan, until that tool's PostToolUse |
| PermissionRequest, Notification `permission_prompt`, Elicitation | needs you: permission, unless already question or plan |
| Stop | done, new until the user opens it or sends the next prompt |
| StopFailure | failed |
| PreCompact → PostCompact | compacting → the previous state |
| SessionEnd (reason ≠ `clear`), pid exit | ended |

Known gap: Esc, a rejection or an interrupt sends nothing, so the state holds until the next event. Cards show how long a state has lasted, so a stale one is visible.

## 7. Claude integration

Plugin `plugin/`, bundled into `HQ.app/Contents/Resources/Plugin` by `build.sh` and installed globally from there (`tools/install-plugin.sh`, also Setup › Install). Claude Code runs it from its own copy per version: a change under `plugin/` needs a version bump in `plugin.json` and `tools/install-plugin.sh`, and reaches sessions started after that.

- `hooks/hooks.json`: the events above → `${CLAUDE_PLUGIN_ROOT}/bin/hq hook`, timeout 2 s. PreToolUse matcher `AskUserQuestion|ExitPlanMode`; PostToolUse unfiltered (artifacts, PR URLs).
- Skills, without `allowed-tools`: `hq` (what HQ is, the CLI), `hq-tasks` (one task per piece of work the user would track, with a type; subtasks for parts the user wants to see; `doing` when starting; the description kept current by editing it; `review --reason` when the user must check something; never `done` unless the user says so; new tasks to the Backlog unless the user asked to work on them now), `hq-files` (notes linked to their task).

```
hq ctx                                         # this session's tasks, the overview's Review and Doing, recent files, sibling sessions
hq ls tasks [--overview|--backlog|--all] [--type t] [--project p] [--tag t]
hq ls sessions | prs | files | artifacts | projects
hq project edit Name [--folder dir] [--repo owner/name,…]
hq task add "Title" [--type t] [--project p] [--tag t] [--parent T-n] [--now] [--body -]
hq task move T-n todo|doing|review|done [--reason "…"]       # --reason with review
hq task edit T-n [--title …] [--body -] [--type t] [--project p] [--add-tag t] [--remove-tag t] [--parent T-m|none]
hq task show T-n                               # parents, description, subtasks, links
hq task link T-n <url | T-m | session id | path>
hq task unlink T-n <the same item>
hq link <url | path> T-n
hq file new "Title" [--task T-n] [--body -]
hq file write <path> --body - [--append]
hq file show <path>
hq artifact add <url> --title t [--date d] [--task T-n]     # one HQ didn't capture; a ?sk= share key is dropped
hq session new "Name" [--task T-n] [--cwd dir] [--message -]
hq hook                                        # used by the plugin
```

`hq hook` reads stdin, adds Claude's pid, its tty and whether Ghostty is an ancestor, sends the event over the socket with a 1 s timeout and exits 0. Commands find their session from `CLAUDE_CODE_SESSION_ID`. Commands from the socket don't register Undo, and they mark what they change as new.

## 8. Build steps

The cockpit, built in one go from the T-46 plan. Each step ends built, tested, reviewed and committed on `feat/cockpit`.

Steps 0 to 13 are done; step 14 ships.

0. ✅ Start: branch, baseline (build, `swift test`, self-test, UI test).
1. The docs: DESIGN.md and PLAN.md for the cockpit.
2. The model in HQKit, with unit tests: statuses and types, `TaskTree`, migration, the done rule, checkbox toggling, `FaceSpec`, GitHub parsing and link rules. Folders and comment threads go.
3. The data layer: vault keys and the migration with its backup, the store's new fields and records, `AppModel`'s cockpit state, seed data that mirrors the mockup (`APP_SEED=1`, `APP_SEED=large`).
4. Faces: `SessionFace` in DesignKit, three levels of detail, the gallery page `faces`.
5. The cockpit shell: one window, the toolbar, the page and its empty states, menus, Quick Open, the Dock menu.
6. Session cards: the grid, drag to reorder, a task dropped on a card, Hide, Hidden and Closed, Resume, Close.
7. The outline: rows, keys, descriptions, quick add, filters, drag and drop, the done rule.
8. The modal: the sheet, Back and Next, the task, session, file, artifact, start and hidden kinds, the markdown viewer and editor.
9. GitHub: the poller, the PR section, PR and issue modals, links.
10. Attention: seen and changes, the toolbar's counts, Review Next, Mark All Seen, the Dock badge; starting a session end to end.
11. CLI, hooks, skills; plugin 0.5.0.
12. Clean up what the cockpit replaced.
13. Full review and polish (DESIGN.md §17), with a fresh-eyes review.
14. Ship: `./build.sh`, the plugin, the report, merge to `main`.

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
  CLAUDE.md  PLAN.md  DESIGN.md
  Package.swift  build.sh  Info.plist.in
  Icon/              AppIcon.icon (Icon Composer); compiled into Resources/ (not in git)
  Sources/HQ/        app: App.swift, Views/, DesignKit/, Agent/ (CLI + socket), Ghostty.swift, GitHub.swift, Snapshot.swift, SelfTest.swift, UITest.swift
  Sources/HQKit/     no UI: model rules, front matter, markdown, faces, GitHub parsing, hook events, state machine
  Vendor/mermaid/    mermaid.js 11.17.2 and its MIT license, copied into the bundle by build.sh
  Tests/HQKitTests/  unit tests and GitHub fixtures
  plugin/            .claude-plugin/plugin.json, hooks/, skills/, bin/hq
  .claude-plugin/marketplace.json
  tools/             snap.sh, selftest.sh, uitest.sh, grid-lint.sh, check-layout.swift, install-plugin.sh
```
