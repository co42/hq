# hq — design

How HQ looks, moves and speaks. HQ is open all day on the right half of the screen, next to Ghostty, so every choice here is judged by one question: does it stay pleasant at hour eight? The general rules come from bama's `mac-design`, `design-system`, `layout-grid` and `ux-design` skills. This page holds only what's specific to HQ, and wins where they differ.

HQ is a **cockpit** (2026-11-04): one page the user lives on, everything else in a sheet over it. Sessions with faces, pull requests, and tasks with their Backlog as one outline. No folders, no sidebar, no views, no comments.

## 1. Feeling and principles

**Feeling: calm, instant, sure, and a pleasure to look at.** HQ is quiet until something needs the user. Then it's obvious what, and one key away. (Look reworked 2026-11-05, T-218: the HQ file "HQ UI rework plan" says why.)

1. **Attention is earned.** Only what needs the user is orange (a session that waits on them, a ping, a due important reminder, a PR waiting for their review). The page shows state; what happened goes to the notification center, read once (§11, 2026-11-06), so nothing on the page is "new". A working session's face moves (§10), and a card that needs the user and the toolbar's bell glow and breathe until he looks (§11); nothing else loops, pulses or spins.
2. **Native structure, tailored detail.** Apple's toolbar, sheets, menus and Settings. Custom parts only where content needs them: faces, status glyphs, session cards, outline rows, chips.
3. **Depth says what's an object.** Content sits on raised cards over a calm canvas; the page's top carries a soft sky that follows the day (§12). Liquid Glass is the layer that floats over it all: the toolbar, the section bar, each section's controls, hover controls, the modal's header.
4. **One glance, little scrolling.** The page answers, top to bottom: what waits on GitHub, what my sessions do, what they wrote, what I'm working on, what's next. Tight, macOS text sizes; cards fit their rows, nothing reserves empty space. The only ornament is the sky, and it carries the day's state.
5. **Stable.** The user orders sessions and tasks themselves; nothing reorders on its own except what §5 and §7 allow (an ended session leaves the grid, a done task moves to the Backlog the next morning).
6. **Instant.** Every key and click shows its result in the same frame. Local data never shows a spinner. Undo instead of confirmation dialogs.
7. **Keyboard first, drag friendly.** The outline is edited like a markdown todo file; drag and drop is buttery smooth and always shows where the item lands.
8. **A click selects, a double-click opens.** Everywhere: session cards, task rows, PR rows, chips, the modal's rows. Text is the exception: a double-click on a title or a description edits it. So are the notification center's links and names: a click opens them (§11).

## 2. References

| App | Take |
|---|---|
| Bike, Workflowy, Things | An outline edited as text: Return adds, Tab nests, the row is the field. Quick entry that stays open for the next item |
| Linear | Status glyphs as one drawn family (14 pt, 1.5 pt stroke). Type icons with a tint as a label. "Structure should be felt, not seen" |
| GitHub | Pull request states and their colors (open green, draft gray, merged purple, closed red); review and checks as words |
| Mail | An unread dot that goes once read; Remind Me puts a message away until a time, then brings it back |
| Raycast | Quick Open: a big field, scannable rows, each action's shortcut shown next to it |
| Ghostty | Native first ("behave like you expect an application to behave") |
| Things 3 | A big bold title, each list's symbol on its own color, whitespace, a status change you feel (the pop) |
| Linear (March 2026 refresh) | "Don't compete for attention you haven't earned": labels as neutral capsules with a color dot, quiet icons, controls that recede |
| Reminders, Settings | White grouped cards on a gray window, generous corners |
| Photos (macOS 26) | A floating glass control over scrolling content: the section bar |

## 3. Window and toolbar

- **One window**, no sidebar, no inspector, no view picker. HQ stays alive when the window closes (it hides; Window › HQ, ⌘0, brings it back).
- **First launch** places the window on the right half of the main display, full height; after that its frame is restored. Minimum 640 × 480.
- **Two sizes to design for**: 1504 pt wide (half a large display) and 756 pt wide (half a laptop's). The page's content is at most 1240 pt wide, centered, with 28 pt side margins (20 at 756).
- **Toolbar** (2026-11-06):
  - leading: the **bell**, a plain toolbar button that opens the notification center (§11; ⌘J): a bell when nothing waits; the update count as a quiet system badge when only updates do; while something needs the user, a filled orange bell with that count as the system's prominent badge, its glow breathing until the user opens the center after the latest thing that needs them. No words: its tooltip says what it counts, "2 need you, 3 updates";
  - then **New** (`plus`, a menu with no arrow: New Task ⌘N, New File… ⌃⌘N, New Session… ⇧⌘N, New Reminder… ⌃⌘R);
  - trailing: the search field (`.searchable`), which filters every section live and shows "3 of 14" in each header while it filters. (No item sits beside it: a flexible spacer leaves New adrift mid-toolbar, and neither `.automatic` placement nor a `DefaultToolbarItem(kind: .search)` moves the search next to it; centered placement clips the search item at 756 pt.)
- Nothing goes to the overflow menu at 756 pt.
- **Menu bar**: HQ's bell in the system menu bar, a filled bell with the Needs You count beside it while something needs the user; a click brings HQ forward on the notification center.
- **Section bar**: under the toolbar (a `safeAreaBar`), centered, one glass capsule: Pull Requests · Sessions · Files · Tasks, each its symbol and name. The section in view is highlighted (a quiet capsule that slides to the next, 0.26 s ease-in-out): the last section whose top passed under the bar, or Tasks once the page shows its end; a click scrolls to that section and holds it highlighted while the page scrolls there. Its glass isn't interactive: a bar that wide stretching on each click wobbles. At rest nothing sits under it; scrolled content passes under its glass with the scroll edge effect.
- **Problems** (Ghostty access off, plugin missing, GitHub signed out) show as one inline banner under the section bar (in the same `safeAreaBar`, in the page's column) with a Fix button. Never an alert, never a toast.

## 4. The page

Top to bottom, one scroll view on the canvas, under the sky (§12):

0. **The day**: "Thursday" in Large Title bold, "5 November" beside it in Large Title regular, secondary; under it one quiet line of what's going on: "3 sessions working · 2 pull requests wait for your review · 8 tasks open" ("A quiet day: nothing running, nothing open." when all are zero). 52 pt tall.
1. **Pull Requests**: "Pull Requests · 5", then on the trailing edge Refresh (`arrow.clockwise`, its tooltip saying when GitHub last answered, its arrow turning while HQ asks; HQ asks every minute while in front, every five otherwise, and when it comes forward) and "Open GitHub". Two group cards side by side: Reviews, and Yours (§6).
2. **Sessions**: "Sessions · 6", then Closed Sessions (`clock.arrow.circlepath` and its count, "4") and New Session (`plus`) on the trailing edge. A grid of session cards (§5).
3. **Files and Artifacts**: "Files and Artifacts · 12", then on the trailing edge its own search ("Search Files and Artifacts": titles that have it, both cards; Escape clears it), Pinned Only (a `pin` toggle, remembered), New File (`plus`: a popover asks the title; the note opens in its modal, in the editor) and Import Artifact (`square.and.arrow.down`; a popover: the link, filled from the clipboard when it holds one, and a title; the imported artifact is selected). Two group cards like the PRs': Files (notes under hq/files) and Artifacts (§6).
4. **Tasks**: "Tasks · 14 open", then its search field, Descriptions (`text.alignleft`) and Hide Done (`checklist.checked` with the count of done tasks in Tasks, every level), for Tasks only. The outline (§7), then a quick-add line.
5. **Backlog**: "Backlog · 8 open" with a disclosure, folded by default (remembered). Open: its own search field, its four filters (§7) and Descriptions in its header (no Hide Done: its Status filter does that), the same outline, a quick-add line. Each list's toggles are remembered.

**Every section folds** (2026-11-05): a chevron after its count, turned down while open; a click on the title hides the section down to its header (Hide and Show, as Finder's sidebar), and its header's actions go with it. HQ remembers it (the Backlog starts hidden, the others shown). Tab passes a hidden section; View has Hide and Show for each; New Task shows Tasks.

**Header actions are icons**: every action on a section header's trailing edge is an SF Symbol (a count beside it when it has one), its name in its tooltip and for VoiceOver; toggles show highlighted while on.

A section header is its **tile** (the section's symbol, white, on a 24 pt rounded square of its color: Pull Requests purple, Sessions the accent, Files and Artifacts teal, Tasks orange, the Backlog gray; desaturated while folded), its title in Title 2 bold, its count in a quiet capsule (monospaced digits, rolling when it changes), then the chevron. 28 pt between sections, 12 pt from a header to its content. The controls on the right of a header (buttons, toggles, the Backlog's pop-ups, the searches) are one family (2026-11-05) and **one glass group**, like a toolbar of the section's own: 28 pt tall glass capsules (`GlassEffectContainer`, interactive glass), icons secondary (primary under the pointer) in a 16 pt slot so icon buttons are one width, 8 pt apart; a toggle that is on is glass tinted with the accent, its icon in the on-accent color; a search is the same capsule with a magnifying glass and a clear button.

**One selection on the page.** A click selects what it lands on (a PR, a card, a file, a task's row, a chip under a row) and the other sections unselect, each keeping its selection aside for when Tab comes back; a click on nothing (the page around the sections, a header's empty part, between cards) unselects everything. A click on a PR, file or artifact also gives its section the keyboard. A link chip under a task selects on a click, opens on a double-click, and shows its menu on a right-click (2026-11-06): Open, the link's own actions (Open in Obsidian, Open in Browser, Open on GitHub, Copy Link), Unlink from T-12 when it was linked by hand, and Delete for a file or Remove from HQ for an artifact. A link's row in the task's modal has the same menu on a right-click. An item deleted while its modal is open goes back to the modal it was opened from.

**Empty states**: Sessions: "No Sessions. Sessions you start with the hq plugin show up here." with New Session…; Tasks: "Nothing on the overview. Add from the Backlog or type a task." (the quick-add line stays); PRs: "GitHub isn't set up" with the fix; Reviews, empty: "All reviewed" (§6). Empty states sit where the content would be, at the content's width.

## 5. Session cards

- **Grid**: 4 columns when the content is 1200 pt or wider (2026-11-06), 3 from 1060 pt, 2 from 692 pt, 1 below. 12 pt gaps. Fixed card height 68 pt. An `NSCollectionView` inside the page's scroll view.
- **Card**: a raised surface (§12), 12 pt padding, one row (2026-11-06):

```
[face 44]  registry: retry budget                         15m
           registry · retry-budget                   (○ Idle)
```

  - the face (§10); the name (Body semibold, never bolder while unread) with how long it has lasted on its right ("15m", monospaced digits, rolling); `repo · branch` (Subheadline, secondary, truncated in the middle) with the state on its right;
  - the state in a **capsule**, its glyph then its words: "Working" (accent tint), "Idle", "Done" (while unread, lightly: accent text on the chip fill, with its unread glyph), "Ended"; when it needs the user, orange (red when failed) and semibold: "Asks a question", "Wants permission", "Plan ready", "Failed". What it asks is not on the card: it's in the tooltip, the modal and its terminal.
  - **Glow** instead of a fill, only while the session needs the user: an orange edge and an orange light around the card (red when failed), breathing until the user looks (§11). A done session the user hasn't looked at shows it only in its state capsule. The other cards stay plain white, so the glowing ones are the brightest things on the page.
  - Tooltip: the name, and the reason when it needs the user. VoiceOver: one button ("name, state"); press shows details, action Focus (or Resume).
- What a session works on and made is in its modal, not on the card.
- **Order** is the user's: drag a card to move it; an accent bar between cards shows where it lands (`NSCollectionView` has no gap feedback), and the cards slide when it lands. New sessions join the end; cards that come or go animate. An ended session (SessionEnd other than `clear`, or its process exits) leaves the grid for Closed Sessions; the others keep their places and the gap closes. Every open session is on the grid: none hides (2026-11-06).
- **Hover** lifts the card (a deeper shadow). Selected: a 2 pt accent ring and a faint accent tint.
- **Click** selects the card; a click on its face focuses its terminal in Ghostty at once (an ended one asks "Resume …?"), no menu (2026-11-05). **Double-click** or Space opens its modal; Return opens it in Ghostty (focus by tty, or resume).
- **Drop a task** (from the outline) on a card: the task is linked to that session. The card highlights while a task hovers it, and stops when the drag leaves or ends.
- **Context menu** (the same as a click on a face elsewhere, §10): Focus / Resume · Show Details · Close Session · Copy Resume Command, Copy Session ID.
- **Closed Sessions** (a modal, from `clock.arrow.circlepath` in the header): the sessions closed in the last 14 days, each with Resume (`claude --resume` in a new Ghostty tab; the card joins the end of the grid).

## 6. Pull requests

- Two raised cards side by side from 1100 pt of content, stacked below. A card is as tall as its rows (no reserved empty rows); side by side, both take the taller one's height; an expanded card grows, and its neighbor with it.
- Rows of 40 pt, inset 6 pt in the card (hover and selection radius 10, concentric), a hairline between rows from where their text starts. PR, file and artifact rows share their left side and their right columns, so the three cards line up (2026-11-05), left to right, one face against the **kind tile** (a 20 pt rounded square in the state's color with the state's symbol in white, bold): the face (one per row, 2026-11-05: the session that matters most among those linked to the PR or working on its task, the tooltip naming them all; a dashed square when none; a click on a face shows its session's menu under it, as a task's does, with Start Another Session on the PR; on the dashed square it starts one) · kind tile (open green, draft gray, merged purple, closed red) · title over `repo #number · author · asked 2h ago` (Subheadline, secondary; 2026-11-06: in Reviews when the user's review was asked, else "reviewed" when they reviewed it; in Yours "updated"): the only part that grows · status (review state over checks) in a fixed 176 pt column (wide enough for "Changes requested by theo"), truncated with an ellipsis past it · task key in a fixed 44 pt column, right-aligned. No Open on GitHub button on the row (its context menu and modal have it).
- **All reviewed**: Reviews with nothing in it (and no search) fills its card with a green `checkmark.seal.fill` and "All reviewed".
- **Reviews** (2026-11-06): the open PRs the user reviews: those that request their review (theirs, or a team's), and the others' open PRs they reviewed (GitHub drops their review request once they submit a review, so HQ also asks for `reviewed-by:@me`). Orange until the user reviews on GitHub or marks it reviewed in HQ; a new commit after that makes it orange again. It's state on the page and never counts; a review newly asked of the user is an Update in the notification center (§11). Status: "Waiting for you", "Approved by you", "Approved by noor", "You asked for changes", "Reviewed". Its **filter**, a pop-up on the card's title line (always there, remembered, accent while off its default, as the Backlog's): **Not Approved** (the default: what nobody approved, the user included, reviewed or not), Waiting for You, All (approved ones too).
- **Yours**: the user's open PRs: "Approved by noor" (green), "Changes requested by theo" (red), "Review required", "Draft"; checks "Checks passed", "Checks failed", "Checks running". A review or a comment by a person, and checks turning failed, are Updates in the notification center (§11), never a mark on the row.
- **Order** (2026-11-06): Reviews, the latest asked first (when GitHub asked the user, else when they reviewed); Yours, the latest updated first. Each group shows five rows, then "Show N More".
- A click selects a PR's row, a double-click opens its modal (its GitHub page, §8). "Open GitHub" opens github.com/pulls. Context menu: Show Details, Open on GitHub, Mark Reviewed, Start Review Session…, Link to Task…, Copy Link.

### Files and Artifacts

- An artifact's title is its own: the `<title>` of the page a session published (HQ captures the page the publish made or updated, never one it only copied files from), and, once HQ shows the artifact, the title its page reports. **Remove from HQ** in an artifact's context menu takes any entry off the list (the page stays on claude.ai; Undo). **Link to Task…** in a file's, an artifact's or a PR's context menu opens a finder under the row: type a title or a number, ↑ ↓ to choose, Return or a click links.

- The same cards as the PRs', rows of one line, 32 pt (2026-11-05): the maker's face (a dashed square without one, as everywhere; a click shows its session's menu at once) · kind tile (a file: teal, `doc.text.fill`; an artifact: indigo, `globe`) · the title, then its project and up to two tags as label chips (§7) · in the PR rows' status column, its date ("2 hours ago"), right-aligned against the pin · in their key column, a pin (`pin.fill`, accent, when pinned; `pin` on hover). The maker is in the tooltip. The project chip is a button, as on a task's row: None, the projects, New Project…; with none, a quiet `shippingbox` alone.
- **Order**: pinned first, then the newest. Five rows, then "Show N More". The page's search, the section's search and Pinned Only filter both cards ("2 of 8").
- A click selects a row, a double-click opens it. Context menu: Open, Pin or Unpin, Link to Task…, Open in Obsidian and Delete (files: the note goes to the Trash, Undo brings it back) or Open in Browser and Copy Link (artifacts).
- Files and artifacts take a project, tags and a pin like tasks, in their modal's header line: files keep them in their front matter (`project`, `tags`, `pinned: true`), artifacts in HQ's store.

## 7. The outline: Tasks and Backlog

One AppKit outline (`NSOutlineView`, view-based) holds both lists, so rows drag between them and the arrow keys run across both. Edited like a markdown todo file. Each list sits on a raised card drawn behind its rows (from the row under its header to its quick-add line); its rows sit 8 pt inside the card, and a row's hover, selection and drop highlight are inset 6 pt with radius 10, concentric with the card.

### Row

32 pt, Body 13; top-level rows semibold, subtasks regular. A status glyph pops when the user changes it (§12).

**Calm at rest, rich under the pointer** (2026-11-06). At rest a row shows what tells its story; under the pointer, or selected, it adds what acts on it:

```
at rest     [face] ▸ ◐ Retry budget for blob uploads  ⬡ Registry  • perf  ≡        ◔
hover       ⠿ [face] ▸ ◐ Retry budget for blob uploads  ⬡ Registry  • perf  ≡   ◔  T-13  + ⇣ 🗑
```

- grip (hover) · **faces** of the sessions on the task, right after the grip and against the task, open ones first, ended ones dimmed after them; a click on a face shows its session's menu (§10), a click on the empty square starts a session on the task (22 pt, one face per row (2026-11-05): the session that matters most: one that needs the user, else one working, else the latest active open one, else the latest ended one, dimmed; the tooltip names them all; an orange or red badge when it needs the user; a dashed rounded square when nobody is on it, **shown only under the pointer**; a folded task counts its subtasks' sessions too) · indent · disclosure · **status glyph** (a click moves to the next status, from Done back to Todo, as ⌘Return does; ⌥-click opens the status menu: each status with its glyph, the current one checked) · the **title**, a text field: a click selects the row, a double-click edits it in place, caret where it landed, and a press that moves drags the row; it truncates with an ellipsis and shows the whole title as a tooltip; `#word` sets the status or the project it names, else becomes a tag, when editing ends; typing after `#` lists the statuses, projects and tags that start so · the **project** (a neutral chip, its `shippingbox` in the project's color; a click picks None, a project or New Project…, a popover with its name; a task in no project, its own or a parent's, shows the `shippingbox` alone, quiet, **only under the pointer**) and the **tags** (a neutral chip with the tag's color as a dot) · the **description toggle** (`text.alignleft`, 2026-11-06): secondary when the task has a description, accent while it shows; a click shows or hides it (one by one, also when the list's Descriptions shows them all); on a task with none, quiet and only under the pointer: a click opens an empty one to write. The status glyph takes clicks over the row's full height. A double-click on the row outside the title and description, Space or ⌘I opens the task.
- Trailing, in a stack that hides what doesn't fit (the title truncates first): the **progress ring** of everything under it, every level (2026-11-06: a quiet ring that fills clockwise from twelve with a segment per status, in its glyph's color: done green, doing yellow, todo the track left; a green disc when all is done; "2 done, 1 doing, 2 to do" in its tooltip and for VoiceOver) · the key (mono, secondary), **only under the pointer or selected**; a click on it copies "T-12 Title", as Copy Key and Title does, and it turns the accent color a moment (2026-11-06) · on hover: Add Subtask (`plus`), Move to Backlog / Move to Tasks (`tray.and.arrow.down` / `tray.and.arrow.up`), Delete (`trash`). Every hover action is also in the context menu and the menu bar.
- **No types** (2026-11-06: they don't use them): the page, the modal, the menus and the Backlog's filters show none. Notes keep `type:`, the CLI still takes `--type`.
- **Three statuses** (2026-11-06): Todo, Doing, Done. What the user must check is a notification (§11) and the task stays doing; nothing on a row asks for the user.

### Keys

Keyboard first, as in an outliner: the rows take arrows and single keys; a title or a description takes text until Escape gives the keyboard back to the rows. On the page, Tab and ⇧Tab move the keyboard from section to section (Pull Requests, Sessions, Files and Artifacts, Tasks, round the page, skipping empty ones); the section left unselects, and gets its selection back when Tab returns; the page scrolls the selected row or card of the section that takes the keyboard into view (the arrows too); in each, the arrows move the selection and Return or Space opens it (Return opens a session in Ghostty). In a title or a description, Tab still goes between them.

On a selected row (or several):

| Key | Does |
|---|---|
| ↓ ↑ | next / previous task |
| Tab ⇧Tab | next / previous section |
| ← → | fold / unfold |
| Return, or a double-click on the title | edit the title |
| ⇧Return | show / hide the description |
| N / ⇧N | new task below / new subtask, title edited; it takes the project in effect there (the task's own, or a parent's), written on it |
| ⇧→ / ⇧← | indent under the previous sibling / outdent; a held key does nothing more (2026-11-06) |
| ⇧↑ / ⇧↓ | move among siblings; past the first or last, out one level, above or below the parent; a held key stops at the first or last |
| ⌘Return | next status (Todo, Doing, Done, Todo…) |
| Space, ⌘I | open the task's modal |
| ⇧⌘B | move to the Backlog / to Tasks |
| ⌥⌘Return | Start Session… |
| ⌫, ⌘⌫ | delete (Undo) |

In a title:

| Key | Does |
|---|---|
| Return | new task below (first child when the task is open with children), in the project in effect there; nothing on an empty title |
| Tab, ⇧Return | edit the description (shown, even when empty) |
| ⇧Tab | edit the previous task's title |
| Escape, ↑ ↓ | end editing; the row (or the one above or below) is selected |
| ⌘Return, ⌘I, ⇧⌘B, ⌥⌘Return, ⌘⌫ | as on a row |
| ⌫ at the start | nothing: the caret stays, the task stays |
| ⇧← at the start / ⇧→ at the end | outdent / indent, the title still edited; a held key selecting the title stops at its edge |

In a description: Escape and ⌘Return save and select the row; Tab saves and edits the next task's title, ⇧Tab this task's title.

**Focus never drops.** Escape ends an edit and keeps it (⌘Z undoes). A task left with no title, description, subtasks or outputs is deleted (Undo). When a selected task leaves its list (deleted, moved to the other list, hidden by Hide Done or a filter), the task above it in that list takes the selection, else the one below; folding a task whose subtask is selected selects the task; dropped rows stay selected. Rows that move (indent, outdent, move) keep the selection and the keyboard. Every edit is one Undo step named after it ("Undo Indent", "Undo Move to Backlog"). The rows' keys come before the menu bar's, so they never depend on its state.

### Description

Markdown, inside the task's row under its title (the row grows), rendered (§9). Shown per task (⇧Return or the description toggle after the title, even when empty, to write one), or by its list's Descriptions for every task that has one. A double-click or Tab from the title turns it into the markdown editor in place (a click selects the row and still reaches links, checkboxes and chips; the outline's descriptions aren't selectable text); Escape or ⌘Return saves and ends editing. A description shows its first 20 lines in the outline, then "N more lines: open the task to read them all." (2026-11-05); the modal shows it all. An empty description hides again when editing ends. The task's links show under its title whether the description shows or not: its files, artifacts, PRs and issues, the PRs its sessions opened, and the tasks linked to it (`hq task link T-12 T-34`), as small chips on one line (kind icon, PR state icon or task glyph, the maker's face, the title). A click selects a chip, a double-click opens it, a right-click shows the link's menu (§4), a drag onto another task links it there too. No comments anywhere: a task has a description only.

### Quick add

A "New Task" line closes each list's card ("New Backlog Task" in the Backlog): an accent `plus.circle.fill` in the status column, where the new task's glyph will be, and the placeholder in secondary, with no hint. Return adds the task at the end of Tasks or the top of the Backlog and keeps the field for the next one; ⌥Return in the Tasks line sends it to the Backlog. `#tags` work.

### Search and filters

Each list has its own search field in its header ("Search Tasks", "Search Backlog"; Escape clears it). A search shows the tasks whose title (or key) has every word, and their parents, nothing else: not a match's siblings, not its subtasks. The toolbar's search does the same in both lists. "3 of 14" in the header while one runs.

The Backlog's **filters**, three pop-ups in its header, each its icon and its value, accent while it narrows the list: Status (Open = not done, the default; Todo; Doing; Done; Any), Project, Tag; `xmark`, always there, clears them all and the Backlog's search, off while neither applies (2026-11-05). A top-level task shows when it or one of its subtasks matches a filter; its subtree shows whole.

### Done

A done subtask stays checked under its parent (its list's Hide Done hides it). A done top-level task in Tasks stays in place, checked, until the next morning (05:00 local), then moves to the top of the Backlog (Status Done shows it). That is the only time a task moves on its own.

### Order

The user's, by drag or keys. A task Claude creates goes to the Backlog unless created with `--now` (Claude is about to work on it with the user), which puts it at the end of Tasks.

### Drag and drop

The most important interaction. It must feel buttery smooth.

- Drag from anywhere on a row, its title included, except a title being edited. Several selected rows drag together with a count badge. The drag image is the row; other apps receive the title as text.
- **Where it lands shows before release**: between rows, the rows part (gap feedback) at the indent level of the landing place; on a row, the row highlights (it becomes the last child); on a list header, the item goes to the end of that list. A folded row opens after hovering 0.6 s. The page scrolls near its edges.
- Never into its own subtree: the outline refuses it and the cursor says so.
- A cancelled drag (Escape, or a drop outside the window) leaves nothing behind.
- Every drop is one Undo step. Option copies nothing: tasks are unique, so the cursor shows a move only.
- A task dropped on a session card is linked to that session (§5).
- **Linking by drag**: a file, an artifact or a PR (its row in Files and Artifacts or Pull Requests, or a link chip under another task) dropped on a task's row links it to that task: the row under the pointer highlights, the item shows under it, one Undo. Something already linked there is refused. Other apps get the link (PRs, artifacts) or the title.

## 8. The modal

A native sheet over the window, about 88% of the window's content (at least 720 × 520), the window dimmed by the system. Inside, the canvas with the item's sky (§12), and each group (a task's properties, description, subtasks, links; a session's needs-you box, Works on, Made and linked, Last message, Details; a PR's review box; the notification center's sections) on a raised card; a session's needs-you box and a PR's review box glow orange (red when failed) instead of a tinted fill. The start form and Closed Sessions are small: their sheet stays at 720 × 520.

**Header bar**, on the canvas with no rule under it, every button glass (`glass`; the kind's actions as one `GlassEffectContainer` group; the one prominent action in `glassProminent`): Close (Escape, a glass circle) · **Back** ("‹ T-13 Retry budget…", ⌘[) when something was open before · the title · the kind's actions (one prominent at most). Its controls sit as far from the sheet's sides as from its top (Close centered 26 pt from both, the last button 14 pt), so they nest in the round corners as the window's traffic lights do. Opening an item from inside the modal pushes it on the Back stack (a link in the notification center too, so Back returns to the center); opening from the page starts fresh.

| Kind | Holds | Actions |
|---|---|---|
| Task | key and place ("On the overview", "In the Backlog", "Subtask of T-13"); title (Title 1, editable); Status (segmented: Todo, Doing, Done); Project (its chip: a click picks None, a project in use or New Project…, a right-click its color); Tags (chips: a right-click sets the color or removes the tag; + adds one, completing from the tags in use); On it (session chips with face and state, Start Session…); Description (rendered, Edit; checkboxes tick in place); Subtasks (glyph toggles done, title opens it, "Add subtask"); Files, artifacts, PRs and issues (face, kind, title, time; × unlinks what was linked by hand, one Undo; **Link…**, always there: a popover that searches the files, artifacts, PRs and issues not linked yet as the user types, a click or Return links one) | Delete, Move to Backlog / Add to Tasks, Open in Obsidian |
| Session | face 72 pt, name, `repo · branch`, state pill; the needs-you box (a question with its options, a plan rendered, a permission with the tool and input in mono, an error); Works on (tasks, unlink with ×); Made and linked; Last message (markdown); Details (directory, branch, started, session id, copyable) | Close Session, **Focus** or **Resume** |
| File | the note rendered, Edit (⌘E) for the editor in the same column, so the text starts and wraps where it does when rendered; Escape or ⌘Return saves (2026-11-05), Cancel drops the changes; "Written by <session> · 20 minutes ago" | Delete (to the Trash; Undo), Edit, Open in Obsidian; while editing, Cancel and Save |
| Artifact | the live page (`ArtifactReader`, sign-in unchanged) | Reload (its arrow turns while the page loads, 2026-11-06), Copy Link (as wide with its checkmark as with `link`), Open in Browser |
| Pull request, issue | one line: state pill, author, branch, review state, checks in words, then its linked tasks (a click opens one) and sessions' faces, and Link (to a task or a session); the review box while it waits for the user ("noor asked for your review 2 hours ago", Start Review Session…); under them, the page itself on github.com in a web view (2026-11-05: no leaving HQ to read or review). HQ keeps its own GitHub sign-in apart from the browser's; a sign-in and an organization's single sign-on stay in the view, a link the user clicks to another site opens in the browser | Reload (⌘R), Copy Link (⇧⌘C, `link`, a checkmark once copied), Mark Reviewed (while waiting), Open on GitHub |
| Notifications | the notification center (§11): the reminder form at the top while it's open, then Needs You, Updates, Later and Earlier | Remind Me…, Mark All Read (⇧⌘J) |
| Start a session | Name (prefilled "T-13 Retry budget for blob uploads"), Folder (pop-up, preselected: the folder of the task's project, or of a parent's, or of the project the PR's repository belongs to (Settings › Projects); then the task's sessions' folders, recent folders, Choose…), First message (multi-line, prefilled; the message editor has the keyboard, caret at the end) | Cancel, **Start** (⌘Return) |
| Closed Sessions | the sessions closed in the last 14 days | Resume |

Close Session on a running session types `/exit` and Return into its terminal, then closes the terminal once Claude has quit. Starting a session writes the first message to `~/Library/Application Support/HQ/Prompts/<uuid>.md` and types `claude --session-id <uuid> --name '<name>' "$(cat '<path>')"`: fish, zsh and bash all read it. If Ghostty can't be reached, the form stays with its text and the banner says why, with Try Again.

## 9. Markdown and Mermaid

- **Viewer** (`MarkdownView`, Foundation's parser through `HQKit.Markdown`): headings (Title 2, Title 3, Headline), paragraphs keeping single line breaks, lists with nesting, **task lists whose checkboxes tick in place** (`- [ ]` ↔ `- [x]` in the source, one Undo step: in a task's description and a file's view), quotes with a bar, tables, rules, code blocks with Copy, inline code, bold, italic, links (the browser), `[[wikilinks]]` (Obsidian), Mermaid blocks drawn by the bundled mermaid.js as images (`MermaidRenderer`).
- **Editor** (`MarkdownEditor`, an `NSTextView`): monospaced, lines 1.35 times the font's height (as airy as the rendered note), Undo, Find (⌘F, its own find bar; ⌘G, ⇧⌘G), no spell check, light syntax coloring (headings, list markers, code spans and fences in a quiet secondary, links) in DesignKit colors. Saves when editing ends, on ⌘Return, or when the user leaves; Escape saves a task description and drops a file's edit in progress. The same editor serves descriptions (in the outline and the modal) and files.

## 10. Faces

Each session gets a face generated from its session id, the same everywhere (cards, rows, PR rows, chips, modals, Quick Open). The user tells sessions apart by their faces at a glance.

- **One vector family** on a 40 × 40 grid: rounded joins, one stroke weight (1.3 at 40), friendly and calm, not childish, harmonious with macOS colors. A squircle mask (30% continuous corners).
- **Parts**: backgrounds (12 colors in two OKLCH tiers, pastel and deep, none near system orange or red); patterns at large sizes (two-tone diagonal, soft stripes, rings, dots); skin tones (8); face shapes (4); hair (10 styles × 8 colors, two playful); headwear (10: none, beanie with pompom, cap, top hat, beret, party hat, headband, crown, bucket hat, hood); eyes (6); eyewear (6: none, round, square, shades, visor, monocle); facial hair (5); mouths (6); extras (headphones, earrings, freckles, blush); clothes (10 colors).
- **Rules** (`HQKit.FaceSpec`): no hat over a hairstyle it would clip badly, eyes hidden under shades and a visor, features at least 3:1 against skin, skin at least 1.4:1 against the background (otherwise the part is drawn again from the same seed stream).
- **Level of detail**:

| Size | Draws |
|---|---|
| up to 20 pt | solid background, head, hair or headwear silhouette, two eye dots, dark eyewear; strokes at least 1.25 pt |
| 21 to 31 pt | adds eyes, mouth, facial hair, earrings |
| 32 pt and up | everything: patterns, freckles, blush, fine details |

- **Distinct**: among open sessions no two share background and headwear. A salt chosen when HQ first sees a session (0, then up to 8 more tries) is stored, so a face never changes.
- **Ended**: the face fades (45%) in its own colors, so it stays recognizable in Closed Sessions.
- **Working**: the head sways from the chin, 8° each way and nods down at each end, one sway every 2 s, each face from its own point so faces side by side don't move together; shoulders and background stay still. Everywhere the face shows (cards, the outline, rows, chips).
- **Click**: every face, anywhere (cards, the outline, PR, file and artifact rows, chips, the modal), shows the pointing hand, and acts on the press (AppKit takes it, so no row waits out a double-click: 2026-11-05). On a card, a click focuses the session's terminal (§5). Elsewhere it shows its session's menu under the face, their left edges lined up: Focus or Resume (an ended one asks "Resume …?" first), Show Details, (on a task's faces) Start Another Session on T-12…, (on a PR's) Start Another Session on registry #418…, Close Session, Copy Resume Command, Copy Session ID. Where a task or a PR has no face, its dashed square starts a session.
- **Badge**: an orange (needs the user) or red (failed) disc at the bottom right, 30% of the size (at least 7 pt), ringed with the surface color. Tooltip and VoiceOver label: "<session name>, <state>".

## 11. Notifications

Notifications are events the user reads once; the page keeps showing state: face badges, the orange glow of a session that waits, Reviews' "Waiting for you" (2026-11-06). Selecting or opening an item on the page reads nothing.

- **Needs You, orange**: a session that asks, wants a permission, has a plan ready or failed (red), for as long as it waits; a ping; a due important reminder. The bell (§3), the menu bar bell and the Dock badge count it, and the sky turns warm (§12). A PR waiting for the user's review is orange in Reviews (§6) and doesn't count.
- **A card glows**: while its session needs the user (orange; red when it failed), its edge and the light around it breathe softly, 0.9 s each way, until the user clicks the card, opens it, focuses it or looks at its terminal (the watch below); then it holds a faint glow while the state lasts. Its next state breathes again. What the user acknowledged is kept, so HQ starting doesn't make it breathe again.
- **A turn end notifies nothing**: the session's card says "Done" lightly (§5), no glow, no blink, until the user opens it or looks at its terminal.
- **Looking at a terminal reads it**: while Ghostty is in front and a card breathes or a done session waits unread on a terminal, HQ reads the focused terminal's tty every 2.5 s (AppleScript off the main thread, only with the Automation grant, never a prompt, nothing while Ghostty is in the back); within a few seconds the card on that tty stops breathing and a done session there is read. A session that asks, wants a permission or has a plan stays orange: it needs an answer, not a look.

### The notification center

- **A sheet** like a file's or a PR's (the large modal, §8). ⌘J, the toolbar's bell, the menu bar bell, Go › Notifications, the Dock menu and a banner open it. Its header: **Remind Me…** (the reminder editor at the top, below) and **Mark All Read** (⇧⌘J: every notification; due reminders wait to be done, a session that waits stays until it moves on).
- **Sections**, top to bottom: **Needs You** (the sessions that wait on the user, each with what it asks and Focus, gone once it moves on; then the unread important rows: pings and due important reminders) · **Updates** (unread update rows, due reminders) · **Later** (reminders and rows put away until a time, with that time, "Tomorrow 9:00") · **Earlier** (what was read or done in the last day, open: the 5 latest, then "Show 7 More"). Needs You and Updates both empty: "All caught up" under a green `checkmark.seal.fill`, nothing more (`AllClear`, as Reviews says "All reviewed"); the reminder editor opens above it.
- **A row**, as macOS draws a notification (2026-11-06, second pass): an unread dot (orange in Needs You, red for a failed session, the accent in Updates; none once read or done, nor in Later) · the session's face, the PR's kind tile, or a reminder tile (an alarm, orange when important) · a title line: who, bold while unread (the session's name, the PR's "registry #418", "Reminder"; a click opens it), "3 updates" when several events merged into it, the time on the right ("14m ago"; in Later, when it comes back) · the text, two lines at rest, **all of it and selectable once the row is selected** (its tooltip has it too, and Copy Text) · its links as chips: a click opens the item over the center; it reads a notification, never completes a reminder. Nothing is ever dimmed.
- **Selection and hover** draw as the other lists' (`rowHighlight`: `Radius.row`, inset `Space.xs + 2` in its box, the accent selection while the center has the keyboard).
- **Actions** float over the row's trailing end on hover and while it's selected, a small lifted bar: **Edit** (reminders) · **Later** (the When picker), or in Later the time, which changes it · **Read**/**Mark as Unread**, or for a reminder **Done**/**Mark as Not Done** · **More** (its context menu: Open, Edit…, Read or Done, Later › its choices or Bring Back Now, Copy Text, Delete).
- **Read in place**: a row read, done or undone while the center shows keeps its place, with its actions, until the center closes; then it's in Earlier. A notification is read once opened; **a reminder is a to-do**, done only with Done (E): a due one stays in Needs You or Updates until it's done or put Later.
- **The When picker**, the one place a time is picked (Later, a reminder's time, a Later row's time): a popover with a field on top ("Tomorrow 9am, in 2h, fri…"), what it reads shown in full as the first choice ("Friday 13 November, 15:00"), then In 1 Hour, This Evening (until 17:00), Tomorrow and Next Week, each with its time on the right ("Sat 9:00"), and Pick Date & Time… (a calendar and a time, Set). ↑ ↓ or the pointer move, Return or a click picks. It reads `16:00`, `9am`, `18h30`, `in 2h`, `tomorrow 9:30`, `mon`, `next week`, ISO dates, and wordier English as macOS reads dates in text ("next friday at 3pm").
- **The reminder editor**, a row: the reminder tile, "Remind me to…", the time (a button: the When picker; "Now" for one that came back), **Important** (a flag toggle, on by default), Cancel, Add or Save. Return saves, Escape cancels. New Reminder… (⌃⌘R), + › New Reminder… and Remind Me… open it at the top of the center, Tomorrow 9:00 by default; Edit, Return on a reminder that links nothing, or a double-click turn a reminder's row into it.
- **Keys**: ↑ ↓ move, Return (or a double-click) opens the first link (edits a reminder that links nothing), E reads or completes (again: unread, not done), L opens the When picker on the row, ⌫ deletes, ⌘C copies the text.
- **One unread row per source and level**: a new event from a session or a PR updates its row: the latest text, the count plus one, the links merged.
- **Where rows come from**:
  - `hq notify "…"` from a session: Updates. It links the session's open tasks and the files, artifacts and PRs it made since its last notification, or what `--link` names. With `--important`: Needs You, when the user asked to be pinged or the session can't go on without them.
  - Reminders, `hq remind "…" --at <when> [--important]` and New Reminder… (⌃⌘R): in Later until due, then Needs You if important, else Updates. Later on a row puts it there too, and it comes back at its own level.
  - GitHub, all Updates: on the user's open PRs, a new review (approved, changes requested, reviewed) or comment by a person (never a bot, never the user), and checks turning failed; on others' PRs, a review asked of the user. Nothing GitHub did before the first v9 poll notifies, nor anything older than the lookback (Settings › GitHub, 10 days by default): what HQ catches up on when it starts after being off. Event keys are kept 30 days, so nothing notifies twice.
  - A task on the overview still in Review when HQ first reads the vault in v9: one Updates row, "T-12 was in Review: <reason>", linked to the task (§7, three statuses).
- **Banners** (macOS notifications) for Needs You only: a ping, a due important reminder, a session starting to wait on the user (after 2 s, and not when the user already looks at its terminal in Ghostty). A click opens the center. While HQ is in front they go straight to macOS's list: the bell says it already. Never in test runs. Ghostty's own notifications for Claude are meant to be turned off.

## 12. Look

### Color

The Mac's accent and system colors carry every meaning. They follow Light, Dark, Increase Contrast and the accent the user chose. HQ adds only its own neutrals, each with light, dark and Increase Contrast values in `Ink`:

| Token | Is | Light / dark |
|---|---|---|
| `content` (canvas) | the page and the modal under the cards | a soft gray a step below white / near black |
| `card` (surface) | every raised card | white / an elevated gray |
| `cardHairline` | a card's edge | 7% black / an 8% white highlight (stronger with Increase Contrast) |
| `rowRule` | the line between rows in a card | 6% |
| `shadowNear`, `shadowFar`, `shadowLifted` | a card's contact shadow (1 pt), its soft far shadow (12 pt, 4 down), and the far one under the pointer (20 pt, 8 down) | black, deeper in dark mode |
| `labelFill` | a project's or a tag's capsule | the quaternary fill |

**The sky**: a 3 × 3 mesh gradient behind the top 420 pt of the page, fading into the canvas, under the toolbar and the section bar so their glass refracts it. Its three colors follow the day: **calm** (the accent, indigo, teal) when nothing needs the user, **needs you** (orange, pink, purple, the warm sky) while anything does. At its top it's 24% strong in light mode, 30% in dark; it crossfades over 1.4 s when the mood changes and never moves otherwise. The modal has its own sky at 70%: warm for the notification center while something needs the user and for a session that waits, calm otherwise.

| Token | Means | Color |
|---|---|---|
| `needsYou` | waiting on the user | `systemOrange`; text in a deeper shade in light mode (4.5:1) |
| update | a notification not read yet: the center's dot | the accent |
| `working` | Claude is working | the accent |
| `failed` | stopped on an error | `systemRed` |
| `doing` | task in progress | `systemYellow` |
| `done` | task done, checks passed, approved | `systemGreen`; words in primary next to a green symbol |
| `merged` | PR merged | `systemPurple` |
| idle, ended, todo | quiet | `.secondary`; `.tertiary` only for decoration (it measures under 3:1), never for information |

Tags and projects take a Mac system color (`LabelColor`): one their name gives, or the one the user picks with a right-click in the modal; their chips are **neutral capsules** (`labelFill`, secondary text) with the color only in their mark: a 6 pt dot for a tag, the tinted `shippingbox` for a project. Color never carries meaning alone: every glyph has a shape and a VoiceOver label.

### Type

macOS text styles. Body 13 for titles and rows; Subheadline 11 for second lines, chips and meta (monospaced digits); keys in Subheadline mono (repo and branch lines are Subheadline, not mono); section headers Title 2 bold; the page's day Large Title (bold, then regular); the modal's title Title 1.

### Space and shape

`Space` on the 4 pt grid (`xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · section 32`). Radii: chips 6 (label chips and state pills are capsules), controls 8, rows 10, cards 16, section tiles 7, Quick Open 26; glass controls are capsules; nested corners are concentric (rows sit 6 pt inside a card).

### Status glyphs

One drawn family, 14 pt in a 16 pt slot, 1.5 pt stroke. Marks inside discs are cut out.

| Task | Glyph |
|---|---|
| todo | secondary ring |
| doing | yellow ring, right half filled |
| done | green disc, check cut out |

| Session | Glyph |
|---|---|
| permission, question, plan | orange disc with `!`, `?`, three lines |
| failed | red disc with `×` |
| done, unread | accent dot |
| working | accent ring, 3/4 arc, static |
| compacting | accent ring, dashed |
| idle | secondary ring |
| ended | tertiary ring, dashed |

Other symbols are SF Symbols named once in `KitIcon`; the self-test checks each exists.

### Glass, materials, motion

**Liquid Glass is the layer that floats**, never the content: the toolbar and its bell (system glass, tinted orange while something needs the user), the section bar, each section header's control group, the modal's header buttons, sheets (system) and the Quick Open panel. Neighboring glass shares a `GlassEffectContainer`; custom glass is interactive (it answers the pointer on macOS 27). Cards, rows and the page get none: they are raised surfaces (`.surface()` in SwiftUI, `TaskOutlineView.drawCard` in AppKit) on the canvas, with the sky behind.

**Motion** goes through `Motion` (`Motion.appKit` for AppKit rows and cards), each one saying something: a card **lifts** under the pointer (0.18 s); the section bar's highlight **glides** to the section in view (0.32 s); a task's status glyph **pops** when the user changes it (a 0.34 s spring around its center); counts and times **roll** (`numericText`); the sky **crossfades** with the day's mood (1.4 s). HQ ignores Reduce Motion: its own animations are short and say something. A change of many rows at once (a search keystroke) happens in place, without fades. Nothing loops but a working session's face (§10) and the glow of a card or the bell breathing for the user (§11). What moves on its own runs on Core Animation, on the render server: the face's head parts are layers with a keyframe sway (`FaceLayer`), the glow's peak fades over the held glow (`BreathingView`), the sky's moods crossfade (`SkyLayerView`). Never a `TimelineView`, a display link or a SwiftUI animation that redraws every frame, and nothing drawn through SwiftUI's GPU renderer (`Canvas`, `MeshGradient`, `ImageRenderer.cgImage`): it holds about 250 MB for seconds after each use (`tools/perf-lint.sh` flags them; `// perf: ok <why>` for a drawing made once on the CPU, or a debug aid).

### Pointer

The pointing hand over everything a click acts on (over the Mac's arrow on push buttons): every button, toggle, pop-up, segmented control and switch while enabled, in the page, the modal, the toolbar and Settings (`handCursors()` on each SwiftUI root gives default-style buttons the hand; the window's own buttons keep the arrow); icons (status, type, pin, close, copy, open on GitHub, a row's hover actions), faces, chips (links, project, + tag) and checkboxes (`clickable()` in SwiftUI, `trackHandCursor()` in AppKit, a tracking area that follows scrolling). The toolbar's items get it from AppKit too (`toolbarClickable()`): SwiftUI's pointer style there comes late and sticks. Rows, cards and text keep the arrow or the I-beam.

## 13. Commands and keys

| Menu | Commands |
|---|---|
| File | New Task ⌘N, New Backlog Task ⌥⌘N, New File… ⌃⌘N, New Session… ⇧⌘N, New Reminder… ⌃⌘R, Quick Open… ⌘K (and ⌘P); Close ⌘W (the modal first, then the window: hidden, Window › HQ ⌘0 brings it back); the open item's way out (Focus or Resume, Obsidian, Browser, on GitHub) ⇧⌘O, Copy Link ⇧⌘C; Import Artifact… |
| Edit | Undo/Redo named after the action, Find… ⌘F (an editor's find bar while one has the keyboard, else the search field), Find Next ⌘G, Find Previous ⇧⌘G, Jump to Search Field ⌥⌘F (always the toolbar's), Edit File ⌘E |
| View | Show/Hide Descriptions in Tasks, Show/Hide Done in Tasks, Show/Hide Descriptions in the Backlog; Show/Hide Pull Requests, Sessions, Files and Artifacts, Tasks, and the Backlog ⌃⌘B; Refresh Pull Requests, Reviews (Not Approved, Waiting for You, All), Pinned Files and Artifacts Only; Zoom In ⌘+ (and ⌘=), Zoom Out ⌘−, Actual Size, Reload Page ⌘R (an artifact or a PR's page). No toolbar items: the toolbar holds the bell, New and the search, and stays |
| Go | Notifications ⌘J (off while the center shows), Back ⌘[, Mark All Read ⇧⌘J, Mark Reviewed (a PR waiting for the user) |
| Task | Open ⌘I, Mark Done ⌘Return, Status ›, Show/Hide Description ⇧Return (rows), Edit Description ⇧Return (title), Add Subtask, Start Session… ⌥⌘Return, Move to Backlog/Tasks ⇧⌘B, Move Up/Down ⇧↑/⇧↓, Indent/Outdent ⇧→/⇧←, Copy Key and Title, Delete ⌘⌫ |
| Session | Focus (or Resume) ⌘O (off for a running session HQ can't reach), Show Details, Close Session, Copy Resume Command, Copy Session ID, Start Review Session… (a PR), Closed Sessions (off when there are none) |
| Window, Help | standard; Window › HQ ⌘0 (the window is titled HQ there and in Mission Control); Help › Keyboard Shortcuts opens Settings › Keys |

Task and Session act on the open modal's item, or, with no modal, on the focused outline row or the selected card; File's way out, Copy Link, Mark Reviewed and Start Review Session… act on the open modal's item, else on the PR, file or artifact selected on the page; in a task's modal, Edit Description edits it there, Add Subtask adds to its list, and Open and Show/Hide Description are off. Task's Mark Done, Status, Show/Hide Description, Move, Indent/Outdent and Delete act on every selected row, as the outline's context menu does: Move says where they all go ("Move 2 to Tasks"), Mark Done says Not Done when all are done. Choice menus (Status, Project) check the current value and list None first. Mark All Read and Mark Reviewed are undoable, as are a notification's Read, Later and Remove. ⌘P, ⌘= and ⌘Return work with Caps Lock on and from the keypad. Find Next and Previous are on only while a markdown editor has the keyboard. Settings › Keys lists every shortcut. Task items whose keys are also text keys carry their shortcut only while the outline has the keyboard (⌘Return and ⌘⌫ on rows and titles; ⇧Return, ⇧ with arrows on rows), so titles and the markdown editor keep them. The Dock menu: New Task, New Reminder…, Notifications. Tooltips start with a verb and end with the shortcut: "Mark every notification read (⇧⌘J)"; the bell's starts with what it counts.

## 14. Words

| Term | Means | Not |
|---|---|---|
| Session | one Claude Code conversation | chat, agent, run |
| Needs you | waiting on the user: a session that asks, wants a permission, has a plan or failed; a ping; a due important reminder | blocked, pending |
| Notification | an event the user reads once, in the notification center | alert, inbox |
| Update | a notification that doesn't need the user: what a session tells them, a review or comment on their PR | news, new |
| Read | a notification the user is done with (Read, E, Mark All Read) | seen, dismissed |
| Later | a notification put away until a time; it comes back at its level | snooze |
| Reminder | a notification set for a time, by the user or a session | alarm, todo |
| Working, Idle, Done, Ended | the other session states | busy, finished |
| Focus | bring a session's terminal forward in Ghostty | open in Ghostty |
| Start | a new session in a new Ghostty tab | start in Ghostty |
| Open | a note in Obsidian; a page in the browser; an item in the modal | jump to |
| Resume | start an ended session again in a new Ghostty tab | restart |
| Task · Todo, Doing, Done | a piece of work and its statuses | issue, ticket, card |
| Tasks, Backlog | the two lists: what's on the overview, what's later | board, inbox |
| Type · Story, Bug, Feature, Chore, Research, Docs | what kind of work; a story is a larger piece, still to shape | label |
| Project | a larger effort a task belongs to | folder |
| Tag | a `#word` on a task | label |
| File | a note in HQ's Obsidian folder | doc |
| Artifact | a page Claude published on claude.ai | link |

Reasons read as sentences without a subject: "Wants to run Bash", "Asks: …", "Plan ready for review", "Failed: …".

## 15. Setup, health, Settings

- **First launch** shows a setup sheet: Claude plugin (Install), Ghostty access (Allow), Obsidian vault (found, or Choose…), GitHub (`gh` found and signed in, with the account; the fix when it isn't). It closes itself when the first three are green; GitHub is optional.
- **Settings**, one grouped form per tab, 520 pt wide: General (open at login, on from the first launch until the user turns it off; vault), Projects (each project, its chip as the section's header: the folder its sessions start in, Choose…, or the folder its sessions ran in most as a secondary guess; its GitHub repositories, `owner/name`, comma separated; also from a project chip's context menu, "Folder and GitHub…"), Claude (plugin status and Reinstall, last hook event), Ghostty (access status), GitHub (account, last update; Notifications: how far back GitHub events notify, 3 to 30 days), Keys (every shortcut). Only what works.

## 16. Parts, gallery, sample data

- **DesignKit parts**: `SurfaceModifier` (`.surface()`), `SkyView`, `SectionTile`, `SessionFace`, `SessionGlyph`, `TaskGlyph`, `TypeIcon`, `SessionCard`, `NotificationBell`, `MenuBarBell`, `RowHighlight` (`.rowHighlight()`), `PRRow`, `OutputChip`, `Chip`, `KeyLabel`, `HeaderButtonStyle`, `HeaderToggleStyle`, `HeaderSearch`, `InlineBanner`, `QuickOpenRow`, `SectionHeader`, `CodeBlock`, `ModalHeader`, `FilterBar`. Each draws every state (rest, hover, pressed, selected, focused, disabled, dragging, drop target) with a forced-state initializer for the gallery.
- **Gallery**: `APP_KIT_GALLERY=1` (parts), `APP_KIT_GALLERY=faces` (120 faces at 16, 22, 40 and 72 pt).
- **Sample data** (`APP_SEED=1`) mirrors the mockup: sessions in every state, tasks with subtasks, types, tags and projects, descriptions with checkboxes and code, the Backlog, PRs in every state, an issue, files, artifacts, hidden and closed sessions, notifications in every section of the center. `APP_SEED=large`: 500 tasks and 30 sessions.

## 17. Review

A UI step is done when every item holds, light and dark, at 1504 and 756 pt.

1. **Snapshots**: `tools/snap.sh`; look at every image. `tools/grid-lint.sh` and the layout probes pass. Glass and toolbar color are judged only on foreground captures (`HQ_FOREGROUND=1`, while the user is away).
2. **bama rules**: `mac-design/design-rules.md` (all 80) and `ux-design`.
3. **HIG**: outline views, lists and tables, sheets, toolbars, drag and drop, color, typography, keyboards, accessibility, searching.
4. **The earlier review** (2026-11-04 macOS 26 UI review): none of its flaws return, notably toolbar spacing, empty states that fill their space, status text contrast, truncation, Quick Open's Return, hover states, Settings listing only what works, sheet focus, the Dock menu.
5. **Squint test**: orange is the most visible thing on the page; nothing blue competes. Nothing moves on its own except what §5 and §7 allow.
6. **Keyboard and menus**: every action has a menu bar command and its shortcut; every item has a context menu; tooltips name the action and end with the shortcut; no shortcut collides with a standard one.
7. **Accessibility**: VoiceOver labels on icon buttons and faces, full keyboard reach, Increase Contrast, Reduce Transparency. Reduce Motion doesn't apply (§12).
8. **Truncation**: the longest seed names truncate cleanly (middle for paths), with tooltips; nothing goes to the overflow menu at 756 pt.
9. **Drag and drop**: every drop target shows where the item lands before release; the animation is smooth; a cancelled drag leaves nothing behind; every drop has Undo.
10. **Performance**: with `APP_SEED=large`, typing, expanding, dragging and scrolling never hitch; outline updates are diffs, never a full reload under the pointer. At rest, faces swaying, cards and the bell breathing, HQ uses no CPU and no GPU memory to speak of (`tools/perf.sh`; the UI test's `idle` group), and its launch has no memory peak (`tools/launch.sh`).
