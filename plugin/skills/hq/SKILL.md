---
name: hq
description: What HQ is and how to use the hq command, notifications and reminders included. Use at the start of work, when the user mentions HQ, the overview, Tasks, the Backlog, sessions, notifications, or pull requests, files or artifacts in HQ, asks what this session works on, which tasks, notes or artifacts belong to it, or which other sessions run beside it, when work the user asked for is ready for them to look at, and when the user asks to be pinged or reminded.
---

# HQ

HQ is the user's cockpit for their day with Claude Code: a native Mac app beside Ghostty. One page, top to bottom: the **Pull Requests** that wait on them, every open Claude **Session** as a card with a face, **Files and Artifacts**, then their tasks as one outline: **Tasks** (what they work on now) and the **Backlog** (later). A task's row shows the faces of the sessions on it, and under it its PRs, issues, files, artifacts and linked tasks. Anything opens in a sheet over the page. A bell in the toolbar (and the menu bar) opens the **notification center**: **Needs You** (sessions that wait on them, pings, reminders that are due), **Updates** (what sessions tell them, reviews and comments on their PRs), and **Later**.

This session reports to HQ through the plugin's hooks on its own. Your part is to keep its tasks current, so the user can follow the work without reading the chat, and to tell them when something is ready. In short: a task goes to `doing` the moment work on it starts, and so does each subtask; finished work the user should look at (most of it) stays `doing` with an `hq notify` saying what to check, and they move it to `done`; `done` yourself only when nothing needs their look, its description saying what changed; every task you create gets a `--project` when the work belongs to one. The `hq-tasks` and `hq-files` skills say how.

## The hq command

`hq` talks to the running app. Every command takes `--json`; `hq help` lists them all, `hq help <command>` shows a command's options.

```
hq ctx                                    # this session's tasks, the overview's Doing, recent files and artifacts, other sessions
hq status                                 # whether HQ runs, and how much needs the user
hq ls tasks [--overview|--backlog] [--all] [--project p] [--tag t]
hq ls sessions | prs | files | artifacts | projects | notifications   # prs: Reviews then Yours, as on the page
hq notify "…" [--important] [--link T-12,<url>]   # tell the user (below)
hq remind "…" --at "tomorrow 9:00" [--important] [--link …]   # a reminder: in Later, back at its time
hq notification done|delete <id>          # one this session sent or set, that no longer needs the user
hq project edit Registry [--folder ~/code/registry] [--repo acme/registry,acme/image-sync]
hq task show|add|move|edit|link|unlink …   # see hq-tasks
hq file new|write|show …                  # see hq-files
hq session new "T-12 Short name" --task T-12 [--cwd dir] [--message -]   # a fresh Claude session in a new Ghostty tab
```

## Telling the user

The user doesn't watch every session. When a turn ends, its card shows it quietly; nothing notifies. Tell them yourself when they should look:

- **`hq notify "…"`** (Updates): the work they asked for is ready to check, a write-up or a page is done, a PR is open for their review, a decision of theirs unblocks the next step. A sentence or two: what's ready, then what to check, like `hq notify "Retry budget ready to check: the canary is green. Merge #418 if eu-west's retries look fine to you."` The center shows two lines, and all of it when the user selects the row. It links this session's open tasks and the files, artifacts and PRs it made since its last notification; `--link` names other things instead. A second notification from this session before they read the first updates it, so don't hold back the last one. Not at every turn end, and not when the turn only waits on a background job or a build: notify when the result is there.
- **`--important`** (Needs You, with a banner): a ping. **"Ping me" always means `hq notify --important "…"`**, sent when what they're waiting for happens ("ping me when the deploy is green": notify the moment it's green, or failed). Also when you can't go on without them and a question doesn't fit ("unlock the screen", "log in to AWS"). Nothing else: a question you ask with AskUserQuestion, a permission or a plan already shows in Needs You on its own.
- **`hq remind "…" --at <when>`**: the user asks to be reminded (`--important`), or a follow-up you can't do now needs them later ("look at the canary again"). `--at`: `16:00`, `in 2h`, `tomorrow 9:00`, `monday`, `next week`, `2026-11-09T09:00`.
- **One that no longer holds**: the follow-up you set a reminder for got done early, a ping you sent is moot. `hq notification done <id>` (read, or done for a reminder) or `hq notification delete <id>`. The id starts the line `hq notify` and `hq remind` print; `hq ls notifications` lists them. Only yours: another's needs `--not-mine`, when the user names it.

## What links where

- A task you create, move or edit from this session is linked to it: this session's face shows on the task's row. The user can also drop a task on a session's card.
- Link what you make to the task it's for, so it shows under the task's row: `hq task link T-12 <PR or issue URL | Slack message link | any web page | T-34 | file | artifact URL>`. A PR opened by a session on the task shows there on its own; link it anyway, so the link lives in the task's note. Two linked tasks show under each other. A wrong link: `hq task unlink T-12 <the same item>`.
- A file you create links to its task (`hq file new --task`). An artifact you publish links to this session, and to its task when the session works on exactly one. Either one made for a task is in the task's project.

## Projects

A project (HQ, Registry, Billing) groups tasks, files and artifacts. It has a folder, where sessions on its tasks start, and its GitHub repositories, whose PRs' review sessions start there too. `hq ls projects` shows each with its folder (or `folderGuess`, the folder its sessions ran in most) and repositories. When you work in a project's repository and it has no folder or misses that repository, set them: `hq project edit Registry --folder <repo dir> --repo owner/name`. A new project needs no command: naming it on a task (`--project "New Name"`) makes it.

## Artifacts

A page you publish with the Artifact tool lands in Files and Artifacts on its own; one HQ missed (published before, elsewhere, or a link the user gives you) goes in with `hq artifact add <url> --title "…" [--date 2026-11-03] [--task T-n]`. Before publishing a page on a subject, look for one (`hq ctx`, `hq ls artifacts`): to revise it, republish to its URL instead of making a new one. A note the user keeps and edits is an HQ file (`hq-files`); a page to look at or share is an artifact.

## Rules

- Never edit HQ's store, socket or vault folder. Go through `hq`.
- If `hq help` doesn't list a command or flag, it doesn't exist: don't guess.
- Exit code 4 means HQ isn't running. Say so once; don't retry in a loop.
