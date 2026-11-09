# Release notes

## v12 · 2026-11-09

**Tasks**
- A task row moves only by its **grip** (⠿, at its left under the pointer). The open hand shows over the grip, and the closed one while you press it. Dragged from anywhere else, its title included, a task is carried as a PR or a file row is. Dropped on another task, it links the two and neither moves. Dropped on a session card, it links to that session. Dropped in Ghostty, it types the task's line.
- Dropping a task on another shows it under that one only, and unlinking it there leaves the other task alone. Before, both showed each other and Unlink removed both.
- A little less space between top-level tasks (12 pt, was 16).
- **Remind Me…**: the alarm among a task row's actions under the pointer, and in its menu and its window, opens New Reminder about the task. The task is linked, and its title is the reminder's words until you type your own. PRs, files and artifacts have it too, in their menus and windows, and File › Remind Me… works on whichever is open or selected.

**Copy**
- **Copy**, in every item's menu and as the first button in its window, copies one line per item: its kind, key and title, ready to paste for a session. "Task T-12: Retry budget", "PR acme/registry#418: Retry budget", "Session <id>: its name", `File "<name>"`, "Artifact <address>: its title". ⌘C copies the selected rows or card, and a click on a task's key copies its line. Copy Key and Title is gone: Copy does it.
- Anything dragged out of HQ gives that same line, a session card included: dropped in Ghostty, it types the session's line. Before, a card dropped outside HQ was refused and slid back.

**Descriptions and notes**
- The editor looks like the text it edits: the same font and sizes, headings large, the marks dimmed, only code in mono. Switching between reading and editing moves nothing, and the box grows with its text.
- A double-click on a description (in the outline or the task's window) or on a note edits it with the caret where you clicked.
- Return continues a list (`-`, `1.`, `- [ ]`, `>`) and ends it on an empty item; Tab and ⇧Tab nest a list item and take it back out.
- ⌘B, ⌘I and ⌘K mark the selection bold, italic or as a link (to the address you copied); an address pasted over words links them. ⌘I no longer opens the task while you edit its description.
- A click on a checkbox in the editor ticks it. In the rendered text, done items step back.

**Notifications**
- A notification about a PR or an issue shows its title after "registry #418", quieter, cut with an ellipsis when the row is short. Review requests show it the same way.
- A row you read, complete, put Later or edit moves to its section at once. The selection goes to the next row, so E, E, E works down the list, and ⌘Z brings a row back.

**Pull Requests**
- Reviews keep up: HQ asks GitHub every minute while its window is on screen, also beside Ghostty. Before, that was every 5 minutes unless HQ was in front. It also asks a few seconds after you leave a PR's page or submit a review in it.

**Sessions** (plugin 0.8.1)
- Tasks have no type any more, in `hq` and its skills too: sessions no longer spend a command setting one. `#bug` in a title is a tag. `--type` is gone: a session still passing it gets an unknown-option error. Older notes keep their `type:` as written.

## v11.1 · 2026-11-09

A stability release.

**Fixes**
- Dragging a task out of the outline and dropping it elsewhere in the window no longer crashes HQ. The rows now hold still until the drag has really ended.
- Nothing moves on its own: a done task stays where it is until you move it, or a session does through `hq`. Before, done tasks left Tasks for the Backlog the next morning, and a done task you brought back to Tasks went straight back.
- A task's row shows the face of its own session, open or folded. Before, a folded task showed its subtasks' sessions too, so opening it changed its face.
- Closed Sessions no longer fills with empty "hq" sessions. The claude daemon behind background sessions starts spare Claudes and kills them seconds later; a session that ends with no prompt, name or link now leaves no record, and the ones already there are gone.
- A title you edit takes the row's width at once, also when you go straight from another title or a new task.
- The disclosure triangle shows the pointing hand, and so does a row's description toggle when it shows at rest; a check now sweeps every row control for it.
- A session started in the background (`claude --bg`): a click on its face brings forward the Ghostty tab that shows it, else its window says it runs in the background. **Close Session** stops it (`claude stop`); its conversation stays, to resume. Before, the click opened its window and Close Session did nothing.
- Close Session on a session HQ can't reach opens its window, which says so, instead of doing nothing.

**Sessions**
- **Fork Session**, in every session menu: a new session with this one's conversation so far, in a new Ghostty tab, as an ordinary session HQ focuses and closes like the others.

## v11 · 2026-11-09

**Slack**
- A Slack message, thread or channel links to a task or a reminder as a pull request does: paste it in **Link…**. Under a task it's a chip with the channel at rest ("#registry"), and "Julien in #registry: its first line" under the pointer. A double-click opens it as a click on a Slack link does: in the Slack app, at the message, the thread or the channel.
- **Settings › Slack**: paste a user token, kept in the Keychain. HQ reads a linked message once to name it. It never writes to Slack and follows no conversation.
- Copy a message's link in Slack, then **New Task…** or **New Reminder…**: it comes with the link, named after the message. That copy comes to each new one until you remove it with ×.

**Tasks**
- **New Task…** (⌘N, ⌥⌘N for the Backlog, +, the menu bar and the Dock) opens a small sheet: title, description, Tasks or Backlog, project, links. The task goes at the end of Tasks or the top of the Backlog, and its row is selected.
- The New Task line under each list still adds in place; a Slack link pasted there becomes the task's link.
- **Link…** lists matches as you type: ↑ ↓ or the pointer move, Return links one.

**Notifications**
- **New Reminder…** has Links too: anything Link… finds, or the Slack link you copied.

**Sessions**
- Faces come in nine skin tones, three light, three medium and three deep; before, most read brown or darker.
- A new session's face takes a skin tone no open session wears, in the group the grid shows least, so the grid mixes light, medium and deep. Existing faces change their skin once; the rest of each face stays.
- **Randomize Face** in a session's menu (a card's, a face's, Session in the menu bar) draws another face for it. Undo gives the old one back.

**HQ**
- **Restart HQ**, right above Quit HQ in the HQ menu and the menu bar icon's menu: HQ quits and opens again.

**The hq command, and hq plugin 0.7.4**
- `hq task link` and `hq remind --link` take a Slack message's link, and `hq task show` lists it as one. The skills say so.

**Fixes**
- The pointing hand shows over the links under a task every time, not only now and then.
- Scrolling no longer catches on its first step: the cards behind Tasks and the Backlog are drawn by the GPU now.

**For contributors**
- The flaky 500-task scroll check passes run after run; a stall report says which step was the worst.

## v10 · 2026-11-07

**Notifications**
- Pull requests waiting for your review stand in **Needs You** until you review them. Review opens one; Later puts it away until a time, as on any notification. They count in the bell, the menu bar and the Dock.
- **New Reminder…** (+, ⌃⌘R, the menu bar or the Dock) opens a small sheet of its own: what, when, important, the keyboard in the text. The center no longer has Remind Me….
- A review's or a comment's notification opens its pull request at that review or comment.
- GitHub notifications show when it happened, not when HQ heard of it.
- Earlier is folded by default; a click on its title shows it, as a page section.
- No more Mark All Read: each notification is read, done or put Later on its own.
- No unread dot on rows: faces and tiles line up on the left, as in the other lists; a bold name still says unread.
- A reminder's menu says **Remind Me** ▸ In 1 Hour, This Evening, Tomorrow, Next Week, Pick a Time….
- A reminder that links a task, a pull request, a file or an artifact shows on its row: a small alarm before the title, orange once it's due and important. A click opens it in the center.
- GitHub's catch-up goes as far back as its lookback says (Settings › GitHub, 10 days), from before v9 too.

**Menu bar**
- HQ's own mark, its ring and dot, instead of a bell: orange with the count while something needs you, blinking until you open the center.
- A click opens its menu: Open HQ, Notifications, New Task, New Reminder…, **Focus** ▸ a running session with its face (those waiting on you first), Quit HQ.
- Open HQ, and the Dock menu's items, bring HQ's window to the front from any app, also after ⌘W hid it.

**Toolbar**
- One row: the bell and + on the left, the section bar in the middle, the search on the right. On a window under 960 pt wide the section bar steps aside.

**Tasks**
- The links under a task are short until you point at it or select it (T-34, #418, a file's first letters), and closer to its title.
- A task's progress ring shows once something under it has started; all still to do, there's none.
- **Link…** in a task's menu and in Task › Link…: one search for tasks (by key or words), files, artifacts and pull requests, or paste any link.
- Any web page can be linked to a task: it shows under the task with a link icon and opens in the browser.

**The hq command, and hq plugin 0.7.3**
- `hq task move T-12 doing` lists the subtasks still todo, to move each as it starts.
- `task link`, `task unlink`, `link` and `task add --parent` refuse a task the session isn't on, unless `--not-mine`, as `edit`, `move` and `delete` do.
- `hq task link` takes any web address. A title can start with `--`, after a bare `--`.

**For contributors**
- What v1–v9 taught is now in the docs:
  - CLAUDE.md is rewritten;
  - ITERATION.md says how an iteration runs, from start to release to close;
  - DESIGN.md has §18 (every gesture on every element) and §19 (what was removed, and why);
  - PLAN.md has §12 (AppKit in SwiftUI, Swift 6 recipes).
- `tools/check.sh` runs every check in one go, and `build.sh --dev` waits while it runs.
- `tools/docs-lint.sh` holds the docs and skills to `hq help`.
- The UI test checks that every clickable on screen sits inside its containers.
- The self-test holds the menus and Settings › Keys together.
- Fixed: `build.sh` failed with "binary is older than…" after a checkout.
- Fixed: Settings › Keys missed Copy Link (⇧⌘C).

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
