# Release notes

## v15 · 2026-11-13 · Models

**Sessions** (plugin 0.12.0)
- A session card says what it runs on, in a pill after its folder and branch's: "Opus VH · 442k", its model, its effort (L, M, H, VH for very high, Max) and the tokens its context holds. Hover it for the whole of it. Its team rows and its window show the same; a /model or /effort typed in its terminal shows after its next reply.
- Start a Session has Model and Effort, its role's until you pick; with neither, they name Claude Code's own from its settings ("Opus", "High"). A card's menu and the session's window have Model ▸ and Effort ▸: HQ types /model or /effort in its terminal, only while it waits for its next message, and the card keeps what you picked until a later reply says otherwise.
- Roles have a model and an effort (Starts on, in Roles): Leader ships on Opus, very high; Worker on Opus, high. `hq session new --model --effort` and `hq role edit --model --effort`; a session started with a role gets its role's.
- The Worker text asks a Worker to check the ask against the task's goal and to look past the instance; the Leader text starts a Worker for a trivial task on Opus medium.
- A subtask whose session is its parent's shows that face too.

**Notifications**
- Every notification is a card, as a task is: its text in three lines, the button at its end shows all of it; its links on one line, "+3" for the rest. Nothing runs over the next card.

**Pull Requests**
- In a review's window, Next Review marks it reviewed and shows the next PR of the Reviews list, as its filter shows it (Go › Next Review too).
- Show Drafts in the Reviews filter: drafts are hidden by default, from Reviews and Needs You.

**Fixes**
- A review you put Later in Needs You leaves the Reviews list until it comes back, as one with a reminder does.
- Every link and blocking task at the end of a task's card shows the pointing hand, wherever the page has scrolled. A check now sweeps the whole window for any clickable part without it.
- The role window shows its name and line first; its Used by chips wrap without running under the title. The same fix holds every wrapping row of chips.
- A GitHub link HQ hasn't fetched yet reads owner/repo#n, not its whole address.
- With scroll bars shown always (a mouse plugged in), the page's column stays centered and no longer runs under the scroll bar.
- Every sheet and Settings grow with View › Zoom: at 115% Start a Session's top was cut.
- README: install from a clone with `./build.sh --force "install"`.

## v14.2 · 2026-11-12

- HQ opens at once, even when iCloud has moved your notes off the Mac (a full disk makes it do so): it used to read every task note before showing its window, one download at a time, minutes on end. Now nothing waits on a note: iCloud is asked for all the missing ones at once, and they come in as they arrive.
- Until your tasks and files are read, Tasks and Files say they're loading, and how many notes iCloud is still bringing, instead of showing an empty list.

## v14.1 · 2026-11-12

**Stories**
- A task's chevron shows or hides its subtasks again: the three modes are gone.
- A top-level task with subtasks has a filter button, by its chevron: Only Blocked and Doing keeps the tasks that are Blocked or doing, and their parents. A task only blocked by another doesn't show. Remembered per story.

**Pull Requests**
- A review you set a reminder on for later leaves the Reviews list and stays in Needs You.

**Leaders and Workers** (plugin 0.11.1)
- `hq session close` and `hq session resume` for the sessions a session started: a Leader closes a Worker once its task is done and brings it back when needed. `hq ctx` lists closed ones too. Resume from Closed Sessions opens a session in its parent's Ghostty window.
- The Leader and Worker texts ship as HQ's defaults: few tasks with short titles, details in descriptions, links and Blocked kept current, the user asked before tasks are added or removed. The hq skill gives every session the same rules.
- `hq role show --json` gives the role's text alone.

## v14 · 2026-11-11 · Leaders

Sessions start sessions and lead them (T-370). A session another one starts sits under it, and any session can have a role: the text it starts with. A Leader follows a story and keeps it moving; Workers do the work and report to it.

**Teams on the page**
- The grid shows the top-level sessions, every card the same size, two columns from 1060 pt. A card shows its role under its name.
- A team's card shows its sessions as small faces, each with its state (working, needs you, failed, done), "+3" when they don't fit; one that needs you is never hidden. It glows while one of them needs you, red when one failed.
- Its round toggle opens the card itself, a row per session, deeper ones indented, floating over the cards below: nothing on the page moves. One team open at a time; a click outside, Escape, ⌘↑ or the toggle folds it.
- The arrows walk the cards and an open team's rows; ⌘↓ and ⌘↑ show and hide a team's sessions.
- A closed leader stays on the grid, faded, while one of its sessions runs, and leaves with the last one.
- A session's menu: Start Child Session…, Start Session from Its History…, Move Under ▸, Make Root, Close Team (N sessions)….
- Sessions drag as tasks do: between cards or rows a session lands where you let it go; on a card, a menu offers Move Under, Move Above, Move Below, Make Root. The drop ring shows whole.
- ⇧↑ ⇧↓ ⇧→ ⇧← move the selected session: on one column as tasks (Indent, Outdent), on two in the arrow's direction, never under another; a team's rows keep the task keys.
- A team's toggle takes every click, however quick.

**Roles**
- A role is a note in your vault, `hq/roles/<Name>.md`: a color, one line and its text. Leader and Worker ship with HQ; Restore Default brings their text back.
- The masks button on Sessions opens Roles: the list, each role laid out like a file, edited in place (⌘E), New Role, Delete with Undo.
- A session with a role gets its text when it starts, resumes, compacts or clears, after HQ's line saying who started it and how to message it.

**Start a Session**
- Role, Parent and History. A child opens in its parent's Ghostty window. Role starts at the role its siblings have.
- History replaces Fork Session: a new session that starts with another's conversation, and still gets its own role, task and first message.
- A session's window shows its role, who started it and its sessions; the menu bar's Focus ▸ and Closed Sessions keep teams together.

**Sessions' `hq`** (plugin 0.11.0)
- `hq session new --role --parent --beside --history`, `hq session edit --parent`, `hq ls sessions --tree`, `hq ls roles`, `hq role show | new | edit | delete`.
- `hq ctx` says the session's role, who started it, and the sessions it started.
- The skill: sessions you start report to you; a handoff is `--beside`; block a task the moment it waits on someone.

**Fixes** (T-430, T-439)
- Close Session works with text typed in the session: it's cleared, then the session exits.
- "Only Blocked and Doing" (was Only Blocking and Doing) keeps a task's blocked and doing subtasks and their parents, nothing else.
- Cards nested two levels deep keep a margin on the right.
- Each zoom step resizes the whole page at once, and View › Actual Size is on right after a Zoom In.
- A PR or issue link shows its icon before GitHub has sent it; a task window's group of links is "Links".
- A session whose prompt you cancel before it answers goes back to Idle within seconds, instead of Working until the next message.
- A review you set a reminder on for later leaves Reviews and Needs You until the reminder is due.
- HQ reopens where it was, at its size, for each screen setup.
- Open HQ, Notifications and New Task… from the menu bar take you to HQ's desktop when it's on another one.
- A link's long text (a Slack message) is cut in its tooltip, its menu and the task's window.
- Editing a long description no longer makes the page jump: the page scrolls only to keep the caret in view.
- The task list no longer repairs its own frame: each case had its cause fixed, and a new one fails the tests.

**Tests**
- A full check fails past 2 minutes; the perf budgets run beside the tests.

## v13.1 · 2026-11-11

What the full review of v13 found (T-427): nothing you or a session writes is lost, what was wrong is fixed, and the tests run in 90 seconds instead of 13 minutes.

**Your text is safe**
- An editor writes nothing when you didn't type in it, so it never puts back an old description over what a session wrote meanwhile. When you both changed it, the changes on different lines are joined; on the same lines yours is kept, a notification says so, and ⌘Z brings back the other.
- A description you were writing in a task's window is saved in that task when you leave it any way (⌘J, a banner, Back), never in the next task you open.
- ⌘Z puts back only what your edit changed: a status or description a session set since stays.
- HQ never writes over a note it couldn't read (iCloud still downloading it), and a vault it can't list keeps your tasks on the page with a banner, instead of an empty page.
- Its store or its notifications file, unreadable, is moved aside and kept, never replaced by an empty one; a notification a newer HQ wrote costs that row only.
- Quit and Restart HQ save the open editor and the last second's notifications.

**Tasks**
- Selecting a task fades the rest only when it is blocked by or comes after another task, and only its content, to 62%; while HQ isn't in front nothing fades and the selection is gray.
- A block's header lines up with its sibling cards, and every chevron and description button sits in one column down the list.
- The fold control is a chevron in its three forms. Keys share one width, so titles line up. "N ready" is gone from the progress line. A Blocked task with no reason says "Blocked"; a Blocked block shows its red edge.
- A Blocked task holds its subtasks: they count as blocked, not ready.
- Moving several tasks at once no longer crashes: the cause is fixed (selecting several comes back in v14).
- The outline holds its height: no more rows cut off after a search clears, at any size.

**A task's window**
- Its status glyph at the title's left (a click moves it on, held for the list), its project and tags on one line, Blocked only when it is: the description and the subtasks are on the first screen.
- Then Description, Subtasks, Related tasks, Files and links, each one's action at the end of its label: Edit, Block… · Blocked By… · After…, Link….
- A subtask's window links to its parent.

**Sessions**
- A session that asks you something stays orange when one of its subagents finishes a tool.
- After `/clear` a session keeps its face, its name and its tasks.
- Close Session never types into a question or a permission prompt: it brings the session forward. A card whose Claude never started can be closed.
- Ghostty is asked off HQ's main thread, one call at a time, with a 3 s limit: a stuck Ghostty never freezes HQ.

**Reminders and GitHub**
- `hq remind --at "tomorrow at 15:00"` (or "friday at 3pm", "1h30") is that time; words it doesn't read are refused, and the reply says when.
- GitHub isn't asked at every click into HQ; it follows its back-off and rate limit. Linked PRs past the 60th are read too.
- A review asked again without a new commit waits for you again.
- A diagram that fails or hangs no longer blocks the next ones.

**Sessions' `hq`** (plugin 0.10.0)
- Two skills instead of three, each rule said once. `hq task tick`, `task edit --section` and `--replace` change one part of a description; `task show --deep` reads a story in one call; a description changed since the session read it isn't written over.
- `hq ls sessions --here`, cut lists that say so, a subtask takes its parent's project, `task add --link`, reminders in `task show`, `--name=value`, the JSON shape in `hq help`, which HQ build runs.

**For sessions working on HQ**
- `tools/check.sh` runs everything in about 90 s (13 min before): test copies side by side, waits on what shows instead of fixed sleeps, `--fast` while working. `./build.sh` installs only a tree the release gate passed.
- The gate tells the truth: test copies have their own preferences, snapshots reseed per page, a missing click target or a vanished check shows, a hung test copy is stopped with its stack, a crash's stack is in the summary.

## v13 · 2026-11-10

The task list, redrawn as cards: where a story stands, and what holds it, at a glance.

**Tasks**
- Each task is a card. A top-level task is a story: a big card with its title and its progress ("1 of 17 done", how many are doing, blocked and ready), its subtasks under it in a tray. A task with subtasks is a block, its subtasks indented.
- **Blocked**, **blocked by** and **after**. B blocks a task, with a reason or not: its card takes a red edge and the reason. ⇧B picks the task it waits on: a red chip on its card, a click shows that task. A picks the task it comes after. Selecting a task lights what's related to it and fades the rest; Escape unselects.
- A card's chevron shows all its subtasks, only the ones blocking another or doing, or none. ← and → do the same, ⌥← and ⌥→ for every task under it.
- Every card starts with its session's face, or a plain avatar when no session works on it (a click offers Start Session…). The key always shows. Links sit at the end of the line, one family of icons, a PR with its status (Draft, Approved, Merged).
- A button in a card's corner shows its description in the card. Space opens the task.
- The whole card drags. Between cards it moves, a line showing where. Onto a card, a menu asks: as a subtask, above, below, or a link (blocked by, after). No grip and no buttons under the pointer: the card's menu has everything.
- Under each list, a new task's card: click it, or ↓ on the last task, type, Return.
- One task is selected at a time; several come back in a later version.

**A task's window**
- What it's blocked by, comes after, blocks and is linked to, with Blocked By… and After…. Then its subtasks as the list shows them, the same cards and keys, and a New Subtask card.

**Pull Requests**
- A PR shows only on the task it's linked to, not on every task its session is on. Sessions link it where it belongs.
- HQ asks GitHub every 2 minutes, and the poll no longer times out with many linked items (PR #1).

**Sessions** (plugin 0.9.0)
- `hq task block` and `unblock`, `hq task link --blocked-by` and `--after`. `hq task show` shows a story's progress and what's ready. The skills tell sessions to block a task they can't go on with, and to link a PR to the task it's for.

**Fixes**
- A new task never takes the id of a deleted one. Before, it could inherit that task's files, artifacts and links, and become the task another one was blocked by.
- Tooltips show after 100 ms.

## v12.1 · 2026-11-10

A fix for the markdown editor.

**Fixes**
- Editing a description or a note no longer moves its text. Each line keeps its place and height; only what the marks add moves anything (`##`, `**`, a list's `- [ ]`, a code block's fences, a line they make wrap).
- In a task's window only the description's text turns into the editor: the card stays, outlined while you edit, and Done takes Edit's place. A note keeps its byline, labels and title while you edit it.

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
