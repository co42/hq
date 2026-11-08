---
name: hq-tasks
description: Keep HQ tasks current so the user can follow the work on HQ's overview. Use the moment work on something starts (read the task and its subtasks, set their type and project, move each to doing as you start it), and whenever work is agreed, planned, blocked, ready for the user to check or finished in this session, when you make progress worth reporting on a multi-step job, when the user asks to note something to do, or when the user mentions a task key like T-12, a subtask, Tasks, the Backlog, a story, todo, doing or done.
---

# HQ tasks

The user follows your work on HQ's overview, not in the chat. A task is a note in their Obsidian vault (`hq/tasks/T-<n>.md`). Top-level tasks live in **Tasks** (what the user works on now) or the **Backlog** (later); subtasks sit under their task.

## Taking a task: read it, fix its fields, then work

When the user hands you a task ("do T-12 and its subtasks"), before the first edit or investigation:

1. **Read it and its subtasks**: `hq task show T-n` prints the tasks it's part of ("Part of:"), its description, its subtasks with their status, and what's linked to it (files, artifacts, PRs, tasks); `hq ls tasks --overview --json` gives each subtask's `parent`, `type` and `project`. The subtasks are your queue. The user edits the task and adds subtasks while you work: `hq task show` again between pieces and before you finish, take the new subtasks in, and follow what they changed.
2. **Take it**: `hq task move T-12 doing --not-mine`. It links this session to the task, and so to its subtasks. HQ refuses a session's changes to a task it isn't on, nor under one it's on: `--not-mine` says this is the task the user named (below).
3. **Fix every one's fields**, the task's and each subtask's: a **type** that fits (set a missing one, correct a wrong one) and the **project** the work belongs to (below). `hq task edit T-n --type … --project …`.
4. **Move each subtask to `doing` before you touch it**: before reading its code, planning it or editing for it, not only once you edit. `hq task move` on the parent lists the ones still todo. The parent in doing doesn't move its subtasks: a subtask you work on while it shows todo looks untouched. Then keep every status true as you go (next section).

## The rule: `doing` the moment work starts

- **Start**: as you begin work on a task, before its first edit or investigation, `hq task move T-n doing`. The same for each subtask, when you start it, the parent's doing never covers it. Working through several subtasks as one batch, or reading the code for several to plan them: that starts each of them, so move every one in it to doing then. No task covers the work yet? Create it already doing: `hq task add "Title" --type … --project … --status doing`. The user reads what's moving from Doing: a task left in todo while you work on it looks untouched.
- **Finished, for the user to check** (most work: a PR to review or merge, a page to look at, a choice, an app to restart): the description's Status says what changed and where, its checklist ticked, the link in it; keep the task `doing` and tell them what to check: `hq notify "PR #418 is ready to merge: the canary is green" --link T-n` (the `hq` skill, Telling the user). The user moves it to `done` once they've looked. A PR that still waits for review or merge stays `doing`.
- **Finished, nothing to check** (a chore, a subtask whose parent they'll review, work they said needs no look): the same Status, then `hq task move T-n done`. Each subtask too, as it finishes.

## The description: one clear document, kept current

A task's description is where the user reads about it, in HQ and in Obsidian. Keep it a tidy markdown document that says where things stand now, rewritten as the work moves: never a log of dated notes appended at the end.

```markdown
Blob uploads retry with no budget: a slow S3 complete turns into minutes of retries.

## Done when
- [x] At most 3 attempts per part, full jitter
- [ ] The canary stays green for 30 minutes

## Status
Merged in #418; the canary runs since 14:00. Next: watch it until 14:30, then done.

## Decisions
- A budget per upload, not per part: a push of 40 layers must not retry 120 times.
```

- The first lines: the goal and why. **Done when**: a checklist; tick each item as it's done and verified. **Status**: a few lines you rewrite at each milestone (what's done, what's next, what blocks), not a history. **Decisions**: what was chosen and why, when it matters later. Leave out a section with nothing in it; keep what the user wrote.
- Edit it whole with `hq task edit T-n --body -`, starting from its current text (`hq task show T-n --json | jq -r .body`): the user edits it too, so never write from a stale copy.
- PRs, Slack messages, files, artifacts and other tasks go through `hq task link`: they show under the task's row, the description needn't list them.

## Fields

- **Status**: `todo`, `doing`, `done`. As a move target, `backlog` means todo, in the Backlog. There is no review status: what the user must check goes to `hq notify`.
- **Type**: `story` (a larger piece of work, still to shape), `bug`, `feature`, `chore`, `research` or `docs`. HQ lets it be empty; you don't. Pass `--type` every time you create a task. When you work on or look at a task that has none (no `type` in `hq task show T-n --json`), or a wrong one, set it: `hq task edit T-n --type …`.
- **Project**: the product or area the work is for (HQ, Registry, Billing). HQ lets it be empty; you don't, when the work belongs to one. Pass `--project` when you create a task, and set it on any task you work on that has none. Reuse a project in use (`hq ls projects`); when none fits, create it by naming it: `--project "New Name"`, and give it its folder and repositories when you know them (`hq project edit`, see the `hq` skill). A tag that names a project (`#registry`) becomes the project: `--project Registry --remove-tag registry`.
- **Tags**: optional, for what cuts across projects (`perf`, `security`). Reuse the names already in use.

`#word` in a title given to `hq task add` or `hq task edit --title` isn't kept as text: it sets the status or the type it names (`#doing`, `#bug`), else the project it names (case, spaces and dashes ignored: `#machine-identities` → Machine Identities), else becomes a tag. `#418` stays text. Keep it when the user types one; otherwise use the flags.

## Commands

```
hq ctx                                              # what this session works on, and the overview
hq ls tasks [--overview|--backlog] [--all] [--type bug] [--project Registry] [--tag perf]
hq task show T-12                                   # parents, description, subtasks, links; --json for every field
hq task add "Title" --type bug [--project p] [--tag a,b] [--body -]    # at the end of Tasks
hq task add "Title" --type feature --backlog         # the Backlog: only when the user says so
hq task add "Title" --type feature --status doing   # on Tasks, doing: you start it now
hq task add "Part of it" --type chore --parent T-12 [--status doing]   # a subtask
hq task move T-12 doing                             # todo | doing (also brings it to Tasks) | done | backlog
hq notify "PR #418 is ready to merge" --link T-12   # the user must check something: the task stays doing
hq task edit T-12 --body -                          # replace the whole description; the rest stays
hq task edit T-12 [--title …] [--type t] [--project p] [--add-tag t] [--remove-tag t]
hq task edit T-12 --parent T-34                     # move it under T-34, as its last subtask; --parent none: top level
hq task link T-12 <PR or issue URL | Slack message link | web page URL | T-34 | file | artifact URL | session id>
hq task unlink T-12 <the same item>                 # a link made by mistake
hq task delete T-12 --yes                           # only when the user asks; its subtasks go too (without --yes: what it would delete)
hq task history T-12                                # what sessions changed in it through hq, the last 30 days
hq task undo T-12 --yes                             # put back every task its latest change touched (without --yes: what it would)
```

`--not-mine` on every command that changes a task (`task edit`, `move`, `delete`, `link`, `unlink`, and `add --parent` for its parent): for a task this session isn't on (see Rules). A title that starts with `--` goes after a bare `--`: `hq task add --type bug -- "--flag is ignored"`.

`--body -` reads stdin. A task you create, or move to doing, is linked to this session: its face shows on the task's row. Edits alone (title, description, type, project, tags) don't link it.

## When

- **Before starting**: `hq ctx`. If a task already covers the work, use it; don't create a duplicate.
- **Work is agreed or planned**: one task per piece of work the user would track (a feature, a fix, an investigation), with its type. Title: a short imperative ("Dedup layers on push"). Description: the goal and how you'll know it's done, in a few lines. Parts the user wants to see on their own become subtasks (`--parent`); steps they don't need stay in the description as a checklist (`- [ ] …`).
- **New tasks go to Tasks**, at the end, todo (or `--status doing` when you start now). The Backlog only when the user says so: `--backlog`.
- **Progress or a decision**: at milestones the user would want to read (not after every command), update the description: tick what's done, rewrite Status, add the decision. `--body` replaces it all, so start from `hq task show T-n --json | jq -r .body`.
- **You make something**: link it to the task, so it shows under its row: the PR or issue you open or work from (`hq task link T-n <url>`), a related or follow-up task (`hq task link T-n T-m`). Files from `hq file new` link themselves.
- **Blocked or waiting on the user**: say what's needed in the description, and `hq notify` (`--important` when you can't go on without them).
- **The user says later**: `hq task move T-n backlog`. **Dropped**: say why in the description; the user deletes it, or asks you to (`hq task delete`).
- **The user asks to note something to do**: `hq task add "…" --type …` (on Tasks; `--backlog` when they say Backlog, or "later"); an idea still to shape: `--type story`.

## Continue a task in a fresh session

When the user asks to take a task to a new conversation, it's a new Claude session in its own Ghostty tab, never a subagent:

1. Make the description the handoff: what's done (commits, files, PRs), the decisions and why, what's left, the next step (`hq task edit T-12 --body -`).
2. `hq session new "T-12 Short name" --task T-12`. It opens in this session's directory (`--cwd` for another), linked to the task, and its first message sends it to `hq task show T-12` (`--message -` to write your own).
3. Tell the user it started, and leave that task to the new session.

## Rules

- Change tasks only through `hq`. Don't edit task files with Write or Edit: HQ owns their front matter.
- **A task this session isn't on**, nor under one it's on: every command that changes it fails with exit code 5, naming the task the key hit. Check the key. Run it again with `--not-mine` only when it's the task the user named; never on a key you assumed (the key `task add` gave is in its output: read it there).
- **A change went wrong** (the wrong task, the wrong parent): `hq task history T-n`, then `hq task undo T-n --yes`. It puts back every task that command changed; tasks it created or deleted stay so.
- Exit code 4 means HQ isn't running: tell the user once and go on with the work.
- Keep titles plain and short: the user reads them on one row.
