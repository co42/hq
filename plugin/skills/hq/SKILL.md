---
name: hq
description: What HQ is and how to use the hq command. Use at the start of work, when the user mentions HQ, the overview, Tasks, the Backlog, sessions, or pull requests, files or artifacts in HQ, or asks what this session works on, which tasks, notes or artifacts belong to it, or which other sessions run beside it.
---

# HQ

HQ is the user's cockpit for their day with Claude Code: a native Mac app beside Ghostty. One page, top to bottom: the **Pull Requests** that wait on them, every open Claude **Session** as a card with a face, **Files and Artifacts**, then their tasks as one outline: **Tasks** (what he works on now) and the **Backlog** (later). A task's row shows the faces of the sessions on it, and under it its PRs, issues, files, artifacts and linked tasks. Anything opens in a sheet over the page. Orange means the user must act (a session that asks, a task in Review, a PR waiting for their review); blue means new since he looked.

This session reports to HQ through the plugin's hooks on its own. Your part is to keep its tasks current, so the user can follow the work without reading the chat. In short: a task goes to `doing` the moment work on it starts, and so does each subtask; `review --reason` when the user must check something; `done` when finished, its description saying what changed; every task you create gets a `--type`. The `hq-tasks` and `hq-files` skills say how.

## The hq command

`hq` talks to the running app. Every command takes `--json`; `hq help` lists them all, `hq help <command>` shows a command's options.

```
hq ctx                                    # this session's tasks, the overview's Review and Doing, recent files and artifacts, other sessions
hq status                                 # whether HQ runs, and what needs the user
hq ls tasks [--overview|--backlog] [--all] [--type t] [--project p] [--tag t]
hq ls sessions | prs | files | artifacts | projects
hq project edit Registry [--folder ~/code/registry] [--repo acme/registry,acme/image-sync]
hq task show|add|move|edit|link|unlink …   # see hq-tasks
hq file new|write|show …                  # see hq-files
hq session new "T-12 Short name" --task T-12 [--cwd dir] [--message -]   # a fresh Claude session in a new Ghostty tab
```

## What links where

- A task you create, move or edit from this session is linked to it: this session's face shows on the task's row. The user can also drop a task on a session's card.
- Link what you make to the task it's for, so it shows under the task's row: `hq task link T-12 <PR or issue URL | T-34 | file | artifact URL>`. A PR opened by a session on the task shows there on its own; link it anyway, so the link lives in the task's note. Two linked tasks show under each other. A wrong link: `hq task unlink T-12 <the same item>`.
- A file you create links to its task (`hq file new --task`). An artifact you publish links to this session, and to its task when the session works on exactly one. Either one made for a task is in the task's project.

## Projects

A project (HQ, Registry, Billing) groups tasks, files and artifacts. It has a folder, where sessions on its tasks start, and its GitHub repositories, whose PRs' review sessions start there too. `hq ls projects` shows each with its folder (or `folderGuess`, the folder its sessions ran in most) and repositories. When you work in a project's repository and it has no folder or misses that repository, set them: `hq project edit Registry --folder <repo dir> --repo owner/name`. A new project needs no command: naming it on a task (`--project "New Name"`) makes it.

## Artifacts

A page you publish with the Artifact tool lands in Files and Artifacts on its own; one HQ missed (published before, elsewhere, or a link the user gives you) goes in with `hq artifact add <url> --title "…" [--date 2026-11-03] [--task T-n]`. Before publishing a page on a subject, look for one (`hq ctx`, `hq ls artifacts`): to revise it, republish to its URL instead of making a new one. A note the user keeps and edits is an HQ file (`hq-files`); a page to look at or share is an artifact.

## Rules

- Never edit HQ's store, socket or vault folder. Go through `hq`.
- If `hq help` doesn't list a command or flag, it doesn't exist: don't guess.
- Exit code 4 means HQ isn't running. Say so once; don't retry in a loop.
