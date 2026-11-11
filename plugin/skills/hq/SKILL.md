---
name: hq
description: Keep HQ, the user's cockpit, current - tasks, notifications, reminders and links. Use at the start of work and the moment work on something starts (read the task, move it to doing), whenever work is agreed, planned, blocked, ready for the user to check or finished, when the user mentions HQ, a task key like T-12, a subtask, a story, Tasks, the Backlog, todo, doing or done, sessions, notifications or pull requests in HQ, asks to be pinged or reminded, or asks to note something to do.
---

# HQ

HQ is the user's cockpit beside Ghostty: one page with the pull requests that wait on them, every Claude session as a card, files and artifacts, and their tasks as one outline, **Tasks** (now) and the **Backlog** (later). A bell opens the notification center: **Needs You**, **Updates**, **Later**. The user follows your work there, not in the chat. The plugin's hooks report this session on their own; your part is the tasks and telling the user.

Everything goes through `hq`. `hq help <command>` gives its options, an example and the shape of its `--json`. A command or flag `hq help` doesn't list doesn't exist.

## The rule

- **`doing` the moment work starts**, before the first edit or investigation; each subtask too, as you start it: the parent's doing never covers them. A task left todo while you work on it looks untouched.
- **Finished, for the user to check** (most work: a PR to review or merge, a page, a choice, an app to restart): its Status says what changed, its checklist is ticked, it stays `doing`, and `hq notify` says what to check. The user moves it to `done`.
- **Finished, nothing to check** (a chore, a subtask whose parent they'll review): `hq task move T-n done`.
- **New tasks go to Tasks.** The Backlog only when the user says Backlog, or later.

## Taking a task

When the user hands you one ("do T-12 and its subtasks"):

1. Read it: `hq task show T-12 --deep` prints the tasks it's part of, its reminders, its description, each open subtask's description under its line, and what's linked. The subtasks are your queue.
2. Take it: `hq task move T-12 doing --not-mine`. This session is then on it and on everything under it: `--not-mine` belongs on this first command for a task the user named, and nowhere after (HQ says so when it isn't needed).
3. Move each subtask to doing as you start it; `hq task move` on the parent lists the ones still todo.
4. The user edits the task and adds subtasks while you work: `hq task show T-12 --brief` between pieces and before you finish, and take the new ones in.

No task yet? `hq ctx` shows this session's tasks and what is doing in its project; `hq ls tasks --project Registry` the rest. Reuse one that covers the work; else create it doing: `hq task add "Dedup layers on push" --project Registry --status doing`.

## The description

The user reads it in HQ and in Obsidian: one tidy document that says where things stand now, never a log of dated notes.

```markdown
Blob uploads retry with no budget: a slow S3 complete turns into minutes of retries.

## Done when
- [x] At most 3 attempts per part, full jitter
- [ ] The canary stays green for 30 minutes

## Status
Merged in #418; the canary runs since 14:00. Next: watch it until 14:30.

## Decisions
- A budget per upload, not per part: a push of 40 layers must not retry 120 times.
```

The goal and why first. **Done when**: a checklist, each item ticked once done and verified. **Status**: a few lines rewritten at each milestone. **Decisions**: what was chosen and why, when it matters later. Leave out an empty section; keep what the user wrote.

Change one part at a time; each fails, and says so, when its target isn't there:

```
hq task tick T-12 "The canary stays"            # the item that starts so; prints "2 of 2 ticked"; --untick
hq task edit T-12 --section Status --body -     # replaces that section, or adds it at the end
hq task edit T-12 --replace "until 14:30" --with "until 15:00"   # an exact text, found once
```

`--body -` alone replaces the whole description, and is refused when it changed since this session last read it (the user edits it too): read it again (`hq task show T-12 --body`) and redo the change on that text. PRs, files and other tasks go through `hq task link`, not into the text.

## Fields and the tree

- **Status**: `todo`, `doing`, `done`. `hq task move T-n backlog` is todo in the Backlog; `hq task move T-n todo --list tasks` brings it back. There is no review status.
- **Project**: the product or area (HQ, Registry, Billing). A task you create always gets one: `--project` on a top-level task; a subtask takes its parent's. Reuse a project in use (`hq ls projects`); naming a new one creates it.
- **Tags**: optional, for what cuts across projects (`perf`, `security`).
- **Subtasks**: parts the user wants to see on their own (`--parent T-12`). Steps they don't need stay in the checklist.
- **Blocked**, unasked, the moment a task waits on something outside: a person (the user to log in or decide, a reviewer from another team), an answer on Slack, a freeze. `hq task block T-n "Waiting on …"`, then `hq notify`; `hq task unblock T-n` once it moves.
- **Blocked by**, unasked, the moment it can't go on until another task is done (a stacked PR, an API that must ship first): `hq task link T-n --blocked-by T-m`. **After**, an order without a hard wait: `--after T-m`. Neither moves a task. Before picking the next one, `hq task show` the story's top task: its Ready line says what can start.

## Links

Link what you make to the task it's for, the moment you make it, so it shows on the task's card: `hq task link T-12 <PR or issue URL | Slack link | web page | T-34 | note name | artifact URL>`. A PR goes on the task it delivers and only that one: the user reads where a task stands from its PR. `hq task add "…" --link <url>` links at creation, and `-q` prints the new key alone. A wrong link: `hq task unlink T-12 <the same item>`.

A task you create, or move to doing, shows this session's face on its card. Notes from `hq file new` and artifacts you publish link themselves (the `hq-files` skill).

## Telling the user

Nothing notifies when a turn ends. Tell them when they should look:

- **`hq notify "…" --task T-12`** (Updates): work they asked for is ready, a write-up or page is done, a PR waits for them, a decision of theirs unblocks you. What's ready, then what to check: `hq notify "Retry budget ready to check: the canary is green. Merge #418 if eu-west looks fine."` Without `--task` or `--link` it links this session's open tasks and what it made since its last notification. Not at every turn end, nor while a build runs: when the result is there.
- **`--important`** (Needs You, with a banner): a ping. "Ping me" always means `hq notify --important`, sent when what they wait for happens. Also when you can't go on without them and a question doesn't fit ("unlock the screen"). A ping covers the thing it was asked for; the next notification is an update again.
- **`hq remind "…" --at "tomorrow 9:00"`**: the user asks to be reminded (`--important`), or a follow-up needs them later. `--at` takes `16:00`, `in 2h`, `tomorrow at 15:00`, `friday 3pm`, `next week`. A task's reminders show in `hq task show`.
- One that no longer holds: `hq notification done <id>` or `hq notification delete <id>`; the id starts the line `notify` printed.

## Commands

```
hq ctx [--all]                       # this session's role, leader, tasks, its sessions, what is doing in its project, its files
hq ls tasks [--overview|--backlog] [--parent T-12] [--project p] [--tag t] [--all]
hq ls sessions [--here] [--tree] | prs | files | artifacts | projects | notifications | reminders | roles
hq task show T-12 [T-13 …] [--deep|--brief|--body]
hq task add "Title" [--project p] [--parent T-12] [--status doing] [--backlog] [--link url] [--body -]
hq task move T-12 todo|doing|done|backlog [--list tasks]
hq task edit T-12 [--title t] [--section S --body -] [--replace "old" --with "new"] [--project p] [--add-tag t] [--parent T-34]
hq task tick T-12 "item" [--untick]
hq task link T-12 <item>             # task unlink takes the same; --blocked-by T-34, --after T-34
hq task block T-12 "why"             # task unblock T-12
hq task delete T-12 --yes            # only when the user asks; without --yes: what it would delete
hq task history T-12                 # a change gone wrong: task undo T-12 --yes puts it back
```

A list cut at its page ends with a line like `50 of 112: --limit 200`. The text output is short; `--json` has every field.

## Rules

- Change tasks only through `hq`; never edit HQ's store or its vault folder.
- A task this session isn't on, nor under one it's on, is refused (exit code 5), naming the task the key hit: check the key. `--not-mine` only for the task the user named, never on a key you guessed (a new task's key is the first word of `task add`'s line).
- Titles plain and short: the user reads them on one row.

## Sessions you start

`hq session new "T-12 Short name" --task T-12` starts a Claude session sent to the task, in a tab of your Ghostty window and this session's folder (`--cwd` for another). It's yours: it sits under you on the page and reports to you, and its message wakes you; answer it with SendMessage, to its name. `hq ctx` lists your sessions with their role, state and task, and names the session that started you. `--role Worker` gives it a role, whose text arrives on its own at its start: `hq ls roles` first, to pick one that exists.

**A handoff**, when the user asks to take a task to a new conversation: make its description the handoff (what's done, the decisions, what's left, the next step), then `hq session new "T-12 Short name" --task T-12 --beside`, at your level rather than under you. Tell the user, and leave the task to it.
