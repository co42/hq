# Release notes

## v8 · 2026-11-06

**Pull requests**
- Each row says when: in Reviews when your review was asked ("asked 2h ago"), in Yours when the PR last changed ("updated 5m ago").
- A click on a row's face shows its session's menu under the face, as on a task, with Start Another Session on the PR. Ended sessions too.
- Refresh, and Reload in a PR's or an artifact's window, turn while they load.
- Fixed: Copy Link in a PR's or an artifact's window changed size once clicked.

**Sessions**
- No more Hide: every open session stays on the grid. The eye button is now **Closed Sessions** (a clock and its count): the sessions closed in the last 14 days, to resume one.
- Fixed: on a wide window, a row's 4th card sat past the page's edge, and a click on its face did nothing.

**Tasks**
- A click on a task's key, at the right of its row, copies its key and title.

**The hq command, and hq plugin 0.6.11**
- `hq task delete` and `hq file delete`: their notes go to the Trash. Without `--yes` they only say what they would delete.
- A session can't change a task it isn't on by mistake: `hq task edit`, `move` and `delete` refuse, naming the task, unless `--not-mine`.
- `hq task history T-12` shows what sessions changed in a task through `hq`; `hq task undo T-12` puts back the latest change.

## v7.1 · 2026-11-06

**Performance**: at rest HQ went from about 40% CPU and 430 MB to under 1% and about 80 MB, with nothing changed on screen.
- Working faces sway and cards breathe on the system's animation server: HQ no longer redraws them dozens of times a second.
- The sky is drawn once per mood: no more memory spike of about 250 MB at launch and at each mood change.
- A session's tool calls no longer redraw the page, nor does a GitHub poll that changed nothing.
- With two working sessions on one task, its row's face changes at the next redraw (within 30 s), not at each tool call.

**For contributors**
- `tools/perf.sh --check` holds HQ to CPU and memory budgets; `tools/perf-lint.sh` flags per-frame redraws and drawing through SwiftUI's GPU renderer.

## v7 · 2026-11-06

**Pull requests**
- **Reviews** (was *Waiting for your review*) lists every open PR you review that nobody approved yet, the ones you already reviewed included.
- A filter on the card replaces *Show Reviewed*: Not Approved (the default), Waiting for You, All.
- Reviews sort by when your review was asked, Yours by last update: the newest on top.
- **Copy Link** in a PR's and an artifact's window (⇧⌘C).
- A click on a new (blue) PR, file or artifact marks it seen, as it does for a task.

**Sessions**
- Cards are one row, a third shorter: the state and the time sit on the right. Four in a row when the page is wide enough.
- A click on the face of a session HQ can't bring forward opens its window, which says why, instead of doing nothing.

**Tasks**
- A task's description toggle sits right after its title: there when it has one, accent while it shows, under the pointer to write one.
- The progress ring shows a task's subtasks by status: done in green, review in orange, doing in yellow.
- The links under a task act like everything else: a click selects, a double-click opens, a right-click shows the menu.
- Fixed: a task could show none of its subtasks until a restart, when one of their notes was read while iCloud was still writing it.
- Fixed: a held ⇧-arrow could carry a task out of its parent. It now stops at the edge; a single press works as before.
- Fixed: a task's disclosure could sit off its line after an indent, an outdent or a move between lists.
- Fixed: the attention dot touched the drag grip.

**hq plugin 0.6.10**
- `hq ls prs` follows the page: Reviews, then Yours, each with its status.
- `hq-tasks`: a subtask moves to Doing before Claude touches it, not only its parent.

## v6 · 2026-11-06

First public release: the cockpit (sessions with their faces, pull requests, files and artifacts, Tasks and the Backlog as one outline), the `hq` command and the Claude Code plugin.
