# Release notes

## v9.1 · 2026-11-07

**The hq command, and hq plugin 0.7.2**
- `hq task add` puts a task at the end of Tasks; `--backlog` puts it in the Backlog, which sessions do only when you say so.
- The skills have sessions read their task again between pieces of work and before finishing: you may edit it or add subtasks meanwhile.

## v9 · 2026-11-07

**Notifications**
- One bell replaces "need you", "new", Review Next and Mark All Seen.
  - Nothing waiting: a plain bell.
  - Only updates: their count as a badge.
  - Something needs you: a filled orange bell with that count, breathing until you open it.
- ⌘J or the bell opens the **notification center**, a sheet like a file's. It has four sections:
  - **Needs You**: sessions that wait on you, each with Focus; pings; important reminders that are due.
  - **Updates**: what sessions tell you; reviews, comments and failed checks on your PRs; review requests; replies and mentions.
  - **Later**.
  - **Earlier**: what you read or did in the last day.
- **A row** reads like a macOS notification:
  - who and when, then two lines of text (all of it once you select the row), then its links;
  - unread rows are bold with a dot, and nothing is dimmed;
  - a link opens over the center, and Back returns to it.
- **Acting on rows:**
  - Later, Read (Done for a reminder) and More show on hover.
  - Keys: ↑ ↓, Return opens, E reads, L puts it Later, ⌫ deletes, ⌘C copies its text.
  - Mark All Read (⇧⌘J) is in the header.
- One row per session and per PR: a new event updates its row. Bots and your own actions never notify.
- **Reminders**: New Reminder… (⌃⌘R, in the + menu) or Remind Me… in the center, with any text, a time, and Important or not.
  - A reminder is a to-do: it stays until you mark it Done (E). Opening what it links doesn't complete it.
  - Edit one in place with Return, Edit or a double-click.
- **One When picker** for Later, a reminder's time and its edits:
  - type "tomorrow 9am", "in 2h", "fri" or "next friday at 3pm";
  - or pick In 1 Hour, This Evening, Tomorrow, Next Week, or a date and a time.
- A macOS banner, the Dock badge, and a new bell in the menu bar with its count show what needs you, from any app.
- **HQ catches up after being off**:
  - reminders that came due;
  - what happened on GitHub in the last 10 days (Settings › GitHub › Notifications, 3 to 30 days);
  - what sessions did meanwhile: `hq hook` keeps their events while HQ is closed, and HQ replays them at launch, so a session that started waiting on you shows in Needs You, with a banner.
- Gone: the blue dots on rows, chips and the section bar, the blue glow and the blue sky. A session that ends its turn shows Done on its card, lightly, with no glow and no blink.
- Turn off Claude Code's own notifications in Ghostty: HQ's banners replace them. Set `"preferredNotifChannel": "notifications_disabled"` in `~/.claude/settings.json`.

**Tasks**
- No more Review status: Todo, Doing, Done. A task in Review becomes Doing, and its reason becomes a notification.

**Toolbar**
- The + menu sits beside the bell, with New Reminder….
- Fixed: the pointing hand over the bell and + showed late, and stayed after the pointer left.

**App**
- HQ opens at login. Settings › General turns that off.
- Settings › Keys lists the notification center's keys.

**The hq command, and hq plugin 0.7.1**
- `hq notify "…"` tells you something is ready; `--important` pings you. To a session, "ping me" means that.
- `hq remind "…" --at "tomorrow 9:00"` sets a reminder.
- `hq ls notifications` lists them.
- `hq notification done|delete <id>` lets a session clear a ping or reminder of its own that no longer holds.
- The skills have sessions keep finished work in Doing and notify you what to check; you move it to Done. They move a task to Done themselves only when it needs no look from you.
- `hq task move … review` is refused, pointing to `hq notify`.
- `--link` takes a file name with a comma in it.

**For contributors**
- Fixed: UI checks that failed now and then:
  - a click on a task's key;
  - the outline checks after it;
  - a chip in the center.

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
- Fixed: a double-click on a title edited it but unselected its row; so did a click on a selected row's status.

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
