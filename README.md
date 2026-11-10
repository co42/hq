# HQ

A native macOS cockpit for a day of work with [Claude Code](https://claude.com/claude-code). One page shows your Claude sessions and what they're doing, the pull requests that wait on you, the files and artifacts your sessions wrote, and your tasks with their Backlog as one outline. Anything bigger opens in a sheet over it.

HQ indexes and links; other apps do the work. Ghostty runs the sessions, an Obsidian vault holds tasks and notes as plain markdown, GitHub holds pull requests, claude.ai hosts artifacts. HQ never owns a terminal and never locks your data in: delete it and your notes are still notes.

> HQ is a personal tool, built for one workflow (Ghostty, Obsidian, `gh`, macOS 27) and used every day. It's shared as it is: expect to adapt it to yours. What changed in each release: [RELEASE_NOTES.md](RELEASE_NOTES.md).

## The page

| Section | What it shows |
|---|---|
| **Pull Requests** | Two cards: *Reviews* (not approved yet, by default) and *Yours*, with review state and checks. HQ asks GitHub every two minutes while its window is on screen, and again as you leave a PR's page |
| **Sessions** | A card per Claude Code session, with a generated face and its live state: working, asks a question, plan ready, wants permission, done, failed. Opening one focuses its Ghostty terminal; an ended one resumes in a new tab |
| **Files and Artifacts** | The notes your sessions wrote in the vault, and the claude.ai pages they published, shown live in the app. A note or a description edits in place, looking as it reads: a double-click puts the caret where you clicked, lists continue on Return, ⌘B, ⌘I and ⌘K mark words, checkboxes tick on a click |
| **Tasks** and **Backlog** | One outline, edited like a markdown todo list: Return adds a task, Tab nests it, a drag moves it. Each task is a card with its session's face first, its key and its links (a PR with its status: Draft, Approved, Merged); each top-level task is a story on its big card, with its progress; a task with subtasks is a block, its subtasks indented, and its chevron shows all of them, only the ones blocking another or doing, or none. A task's window shows its subtasks the same way. A task can be Blocked (with a reason or not), blocked by another task (a red chip on its card, a click shows that task) or come after one (selecting a task lights what it waits on): B, ⇧B, A. A button in a card's corner shows its description; Space opens the task. Under each list, a new task's card takes the next one. Dropped on another task, a task asks where it goes or how it links; dragged out it types its line in Ghostty ("Task T-12: Title", as Copy and ⌘C give for any item). Each task is a note in the vault, linked to its sessions, PRs, files, artifacts and Slack messages. New Task… (⌘N) adds one from a small sheet, with the Slack link you just copied |

Attention is earned: only what needs you is orange (a session that asks, a ping, a due reminder), and the page shows state, never "new". What happened goes to the **notification center** (⌘J, the toolbar's bell, or the menu bar), read once: Needs You, Updates, Later. Sessions tell you there when work is ready (`hq notify`), GitHub reviews and comments on your PRs land there, and reminders, yours or a session's, come back there at their time: Remind Me… on a task, a PR, a file or an artifact sets one about it. ⌘K opens Quick Open.

The look is native macOS 27: raised cards on a calm canvas, a soft sky at the top that follows the day, and Liquid Glass for everything that floats (the toolbar, the section bar, the modal's header). [DESIGN.md](DESIGN.md) has every rule.

## How it works

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

- **One process**, the app: a store for what has no file (sessions, artifacts, notifications), an index of the vault, the hook socket, the Ghostty bridge and the GitHub poller. It stays alive when its window closes. With a Slack token, it reads a linked Slack message once to name it, and never writes to Slack.
- **The `hq` command** is the app's own binary, linked at `~/.local/bin/hq`. It talks to the running app over a Unix socket.
- **A Claude Code plugin** (`plugin/`): its hooks report every session event through `hq hook`, which always exits 0, fast, and never opens the app. Its skills (`hq`, `hq-tasks`, `hq-files`) teach Claude to keep tasks current (`doing` when it starts, a description kept up to date, a notification when you must check something) and to write plans and reports as notes linked to their task.
- **Tasks and files are notes** under `<vault>/hq/tasks/` and `<vault>/hq/files/`. HQ writes only the front matter keys it owns, line by line, so everything else in a note keeps its exact text:

```yaml
---
title: Retry budget for blob uploads
status: doing           # todo | doing | done
project: Registry
tags: [perf]
parent: T-9             # subtasks are their own notes
list: overview          # overview | backlog
links: [https://github.com/acme/registry/pull/418]
sessions: [2f1c9e0a-…]
---
The description, in markdown.
```

## Requirements

- macOS 27, with the Swift 6.4 toolchain (Xcode 27 or its command line tools)
- [Claude Code](https://claude.com/claude-code)
- [Ghostty](https://ghostty.org), which HQ drives through AppleScript (macOS asks for Automation access once)
- A folder of markdown notes: Obsidian's iCloud vault named "Notes" by default, any other in Setup
- The [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, for the pull requests
- `jq`
- Optional: a Slack user token (Settings › Slack, the scopes it needs listed there), for Slack links named by their message

## Install

```sh
git clone https://github.com/co42/hq.git
cd hq
./build.sh                # builds, signs, installs /Applications/HQ.app, links ~/.local/bin/hq
tools/install-plugin.sh   # or Setup › Install in the app
```

Then open HQ. Its Setup sheet checks the three things it needs (the plugin, Ghostty access, the vault) and fixes each with a button. Claude Code sessions started after the plugin is installed show up on their own.

- `build.sh` signs with your Apple Development certificate when it finds one, ad hoc otherwise; `SIGN_IDENTITY` picks another.
- The plugin installer adds a local marketplace, installs `hq@hq` for every session, and allows `Bash(hq:*)` in `~/.claude/settings.json`. Undo: `claude plugin uninstall hq@hq && claude plugin marketplace remove hq`.

## The `hq` command

Mostly for Claude, through the plugin's skills, but it works from any terminal:

```sh
hq ctx                                    # what this session works on, and the overview
hq ls tasks | sessions | prs | files | artifacts | projects
hq task add "Dedup layers on push" --project Registry
hq task move T-12 doing                   # todo | doing | done | backlog
hq notify "PR #418 is ready to merge: the canary is green" --link T-12
hq remind "Look at the canary again" --at "tomorrow 9:00"
hq task show T-12
hq task link T-12 <PR URL | T-34 | file | artifact URL | session id>
hq file new "Retry budget plan" --task T-12 --body -
hq session new "T-12 Retry budget" --task T-12   # a new Claude session in a Ghostty tab
```

## Development

```
Sources/HQKit   the model, no UI: task tree, statuses, front matter, GitHub parsing, hook events
Sources/HQ      the app: CockpitView, SessionGrid (NSCollectionView), TaskOutline (NSOutlineView),
                ModalHost, DesignKit/ (tokens and parts), Agent/ (the CLI and its socket)
plugin/         the Claude Code plugin: hooks and skills
tools/          snapshots, tests and lints
```

`./build.sh --dev [--debug]` installs a test copy at `~/Library/Developer/HQ/HQ.app`, which the tools run. Every check runs beside your own HQ, on a throwaway store and vault in `/tmp`, with its window kept behind yours:

| Check | Command |
|---|---|
| Unit tests | `swift test --scratch-path ~/Library/Developer/HQ/test-build` |
| Model self-test | `tools/selftest.sh` |
| UI test: real clicks and keys | `tools/uitest.sh` |
| Snapshots of every screen, light and dark, at two widths | `tools/snap.sh` (to `/tmp/HQ-shots/`) |
| The 4 pt grid | `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/HQ-shots/*-layout.json` |

Views use DesignKit's tokens and parts only: no raw colors, fonts, radii, durations or symbol names outside `Sources/HQ/DesignKit/`. A change under `plugin/` reaches sessions after a version bump in `plugin/.claude-plugin/plugin.json`.

Read [PLAN.md](PLAN.md) (architecture, model, decisions) before changing how HQ works, and [DESIGN.md](DESIGN.md) before touching a view. [CLAUDE.md](CLAUDE.md) holds the rules for Claude sessions that work on HQ.

## License

[MIT](LICENSE). HQ started from [bama](https://github.com/daveebbelaar/bama)'s macOS app and agent-cli templates (MIT), and bundles [Mermaid](https://github.com/mermaid-js/mermaid) (MIT) to draw diagrams in notes: their notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
