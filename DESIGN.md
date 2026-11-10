# hq — design

How HQ looks, moves and speaks. HQ is open all day on the right half of the screen, next to Ghostty, so every choice here is judged by one question: does it stay pleasant at hour eight? The general rules come from bama's `mac-design`, `design-system`, `layout-grid` and `ux-design` skills. This page holds only what's specific to HQ, and wins where they differ.

HQ is a **cockpit** (2026-11-04): one page the user lives on, everything else in a sheet over it. Sessions with faces, pull requests, and tasks with their Backlog as one outline. No folders, no sidebar, no views, no comments.

## 1. Feeling and principles

**Feeling: calm, instant, sure, and a pleasure to look at.** HQ is quiet until something needs the user. Then it's obvious what, and one key away. (Look reworked 2026-11-05, T-218: the HQ file "HQ UI rework plan" says why.)

1. **Attention is earned.** Only what needs the user is orange (a session that waits on them, a ping, a due important reminder, a PR waiting for their review). The page shows state; what happened goes to the notification center, read once (§11, 2026-11-06), so nothing on the page is "new". A working session's face moves (§10), and a card that needs the user and the toolbar's bell glow and breathe until he looks (§11); nothing else loops, pulses or spins.
2. **Native structure, tailored detail.** Apple's toolbar, sheets, menus and Settings. Custom parts only where content needs them: faces, status glyphs, session cards, outline rows, chips.
3. **Depth says what's an object.** Content sits on raised cards over a calm canvas; the page's top carries a soft sky that follows the day (§12). Liquid Glass is the layer that floats over it all: the toolbar, the section bar, each section's controls, hover controls, the modal's header.
4. **One glance, little scrolling.** The page answers, top to bottom: what waits on GitHub, what my sessions do, what they wrote, what I'm working on, what's next. Tight, macOS text sizes; cards fit their rows, nothing reserves empty space. The only ornament is the sky, and it carries the day's state.
5. **Stable.** The user orders sessions and tasks themselves; nothing reorders on its own except an ended session leaving the grid (§5). A task moves only when the user, or a session through `hq`, moves it (2026-11-09, T-345).
6. **Instant.** Every key and click shows its result in the same frame. Local data never shows a spinner. Undo instead of confirmation dialogs.
7. **Keyboard first, drag friendly.** The outline is edited like a markdown todo file; drag and drop is buttery smooth and always shows where the item lands.
8. **A click selects, a double-click opens.** Everywhere: session cards, task rows, PR rows, chips, the modal's rows. Text is the exception: a double-click on a title or a description edits it. So are the notification center's links and names: a click opens them (§11). Every gesture on every element: §18.
9. **Siblings match** (2026-11-07). Parts that do the same job are one DesignKit part and act the same: task, PR, file, artifact and notification rows share their left side, their selection (`RowHighlight`) and their gestures; link chips, faces, header controls, pickers (`WhenPicker`) and empty states (`AllClear`) are each one part. A change to one kind is made to all of them, or it waits.
10. **One mark per meaning** (2026-11-07). No dot, badge or tint repeats what a tile, a bold title or a section already says; every count's tooltip says what it counts. What was removed and why: §19.

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
  - then **New** (`plus`, a menu with no arrow: New Task… ⌘N, New File… ⌃⌘N, New Session… ⇧⌘N, New Reminder… ⌃⌘R);
  - trailing: the search field (`.searchable`), which filters every section live and shows "3 of 14" in each header while it filters. (No item sits beside it: a flexible spacer leaves New adrift mid-toolbar, and neither `.automatic` placement nor a `DefaultToolbarItem(kind: .search)` moves the search next to it; centered placement clips the search item at 756 pt.)
- Nothing goes to the overflow menu at 756 pt.
- **Menu bar** (2026-11-07, T-309): HQ's mark, the app icon's ring and dot, in the system menu bar: a template image that follows the menu bar at rest; orange with the Needs You count beside it while something needs the user, blinking (0.9 s each way, on Core Animation) until the user opens the center, then steady while it still does. A click opens its menu (T-325), the Dock menu's words: **Open HQ** · Notifications (with "· 3 need you") · New Task… · New Reminder… · **Focus** ▸ the running sessions, each its face and "name · state" (the name cut at 30 characters), those that wait on the user first · Restart HQ (T-336: HQ quits and opens again; also in the HQ menu, above Quit HQ) · Quit HQ. Open HQ, and every item that opens something in HQ, brings its window forward from any app, also after ⌘W hid it (T-318).
- **Section bar** (one header row since 2026-11-07, T-326): in the toolbar, centered (`.principal`), one glass capsule of its own (the toolbar's shared glass hidden behind it): Pull Requests · Sessions · Files · Tasks, each its symbol and name. It shows only while the window is at least 960 pt wide (`Metric.sectionBarWindow`): on a narrower window it's the first to go, and the bell, + and the search keep the row. The section in view is highlighted (a quiet capsule that slides to the next, 0.26 s ease-in-out): the last section whose top passed under the bar, or Tasks once the page shows its end; a click scrolls to that section and holds it highlighted while the page scrolls there. Its glass isn't interactive: a bar that wide stretching on each click wobbles. Scrolled content passes under the toolbar with the scroll edge effect.
- **Problems** (Ghostty access off, plugin missing, GitHub signed out) show as one inline banner under the toolbar (a `safeAreaBar`, in the page's column) with a Fix button. Never an alert, never a toast.

## 4. The page

Top to bottom, one scroll view on the canvas, under the sky (§12):

0. **The day**: "Thursday" in Large Title bold, "5 November" beside it in Large Title regular, secondary; under it one quiet line of what's going on: "3 sessions working · 2 pull requests wait for your review · 8 tasks open" ("A quiet day: nothing running, nothing open." when all are zero). 52 pt tall.
1. **Pull Requests**: "Pull Requests · 5", then on the trailing edge Refresh (`arrow.clockwise`, its tooltip saying when GitHub last answered, its arrow turning while HQ asks; HQ asks every two minutes while its window is on screen (2026-11-10), every five otherwise, and when it comes forward) and "Open GitHub". Two group cards side by side: Reviews, and Yours (§6).
2. **Sessions**: "Sessions · 6", then Closed Sessions (`clock.arrow.circlepath` and its count, "4") and New Session (`plus`) on the trailing edge. A grid of session cards (§5).
3. **Files and Artifacts**: "Files and Artifacts · 12", then on the trailing edge its own search ("Search Files and Artifacts": titles that have it, both cards; Escape clears it), Pinned Only (a `pin` toggle, remembered), New File (`plus`: a popover asks the title; the note opens in its modal, in the editor) and Import Artifact (`square.and.arrow.down`; a popover: the link, filled from the clipboard when it holds one, and a title; the imported artifact is selected). Two group cards like the PRs': Files (notes under hq/files) and Artifacts (§6).
4. **Tasks**: "Tasks · 14 open", then its search field, Descriptions (`text.alignleft`) and Hide Done (`checklist.checked` with the count of done tasks in Tasks, every level), for Tasks only. The outline (§7), then a quick-add line.
5. **Backlog**: "Backlog · 8 open" with a disclosure, folded by default (remembered). Open: its own search field, its four filters (§7) and Descriptions in its header (no Hide Done: its Status filter does that), the same outline, a quick-add line. Each list's toggles are remembered.

**Every section folds** (2026-11-05): a chevron after its count, turned down while open; a click on the title hides the section down to its header (Hide and Show, as Finder's sidebar), and its header's actions go with it. HQ remembers it (the Backlog starts hidden, the others shown). Tab passes a hidden section; View has Hide and Show for each; New Task shows Tasks.

**Header actions are icons**: every action on a section header's trailing edge is an SF Symbol (a count beside it when it has one), its name in its tooltip and for VoiceOver; toggles show highlighted while on.

A section header is its **tile** (the section's symbol, white, on a 24 pt rounded square of its color: Pull Requests purple, Sessions the accent, Files and Artifacts teal, Tasks orange, the Backlog gray; desaturated while folded), its title in Title 2 bold, its count in a quiet capsule (monospaced digits, rolling when it changes), then the chevron. 28 pt between sections, 12 pt from a header to its content. The controls on the right of a header (buttons, toggles, the Backlog's pop-ups, the searches) are one family (2026-11-05) and **one glass group**, like a toolbar of the section's own: 28 pt tall glass capsules (`GlassEffectContainer`, interactive glass), icons secondary (primary under the pointer) in a 16 pt slot so icon buttons are one width, 8 pt apart; a toggle that is on is glass tinted with the accent, its icon in the on-accent color; a search is the same capsule with a magnifying glass and a clear button.

**One selection on the page.** A click selects what it lands on (a PR, a card, a file, a task's row, a chip under a row) and the other sections unselect, each keeping its selection aside for when Tab comes back; a click on nothing (the page around the sections, a header's empty part, between cards) unselects everything. A click on a PR, file or artifact also gives its section the keyboard. A link chip under a task selects on a click, opens on a double-click, and shows its menu on a right-click (2026-11-06): Open, the link's own actions (Open in Obsidian, Open in Browser, Open on GitHub), Copy (its line, §7) and Copy Link, Unlink from T-12 when it was linked by hand, and Delete for a file or Remove from HQ for an artifact. A link's row in the task's modal has the same menu on a right-click. An item deleted while its modal is open goes back to the modal it was opened from.

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
- **Background sessions** (`claude --bg`, 2026-11-09, T-327) run in the claude daemon's terminal, which Ghostty doesn't have: Focus brings forward the Ghostty tab that shows it, the only one titled with its name that runs Claude (Claude's agent view titles a tab "✳ <session name>"), whichever session owns that tab; with none, its modal opens and says it runs in the background. HQ never opens a tab for one. Close Session runs `claude stop <id>` (the conversation stays, to resume). HQ asks `claude agents --json` which sessions run in the background, the first time Ghostty doesn't find one.
- **Empty sessions** (2026-11-09, T-354): a Claude with no prompt, name, title, link or task yet stays off the grid while it runs outside Ghostty (the claude daemon starts spares around background sessions and kills them seconds later), and leaves no record when it ends: nothing to resume, nothing in Closed Sessions. One in Ghostty shows on the grid from its start.
- **Fork Session** (2026-11-09, T-355): a new session with this one's conversation so far, in a new Ghostty tab in its folder (`claude --resume <id> --fork-session --session-id <new> --name '<name> ⑂'`), an ordinary interactive session; its card joins the end of the grid at once.
- **Drop a task** (from the outline) on a card: the task is linked to that session. The card highlights while a task hovers it, and stops when the drag leaves or ends.
- **Context menu** (the same as a click on a face elsewhere, §10): Focus / Resume · Show Details · Fork Session · Close Session · Randomize Face · Copy (its line: "Session <id>: <name>", T-358), Copy Resume Command, Copy Session ID. ⌘C copies the selected card's line. A card dragged out to another app gives its line too.
- **Closed Sessions** (a modal, from `clock.arrow.circlepath` in the header): the sessions closed in the last 14 days, each with Resume (`claude --resume` in a new Ghostty tab; the card joins the end of the grid).

## 6. Pull requests

- Two raised cards side by side from 1100 pt of content, stacked below. A card is as tall as its rows (no reserved empty rows); side by side, both take the taller one's height; an expanded card grows, and its neighbor with it.
- Rows of 40 pt, inset 6 pt in the card (hover and selection radius 10, concentric), a hairline between rows from where their text starts. PR, file and artifact rows share their left side and their right columns, so the three cards line up (2026-11-05), left to right, one face against the **kind tile** (a 20 pt rounded square in the state's color with the state's symbol in white, bold): the face (one per row, 2026-11-05: the session that matters most among those linked to the PR or working on its task, the tooltip naming them all; a dashed square when none; a click on a face shows its session's menu under it, as a task's does, with Start Another Session on the PR; on the dashed square it starts one) · kind tile (open green, draft gray, merged purple, closed red) · title over `repo #number · author · asked 2h ago` (Subheadline, secondary; 2026-11-06: in Reviews when the user's review was asked, else "reviewed" when they reviewed it; in Yours "updated"): the only part that grows · status (review state over checks) in a fixed 176 pt column (wide enough for "Changes requested by theo"), truncated with an ellipsis past it · task key in a fixed 44 pt column, right-aligned. No Open on GitHub button on the row (its context menu and modal have it).
- **All reviewed**: Reviews with nothing in it (and no search) fills its card with a green `checkmark.seal.fill` and "All reviewed".
- **Reviews** (2026-11-06): the open PRs the user reviews: those that request their review (theirs, or a team's), and the others' open PRs they reviewed (GitHub drops their review request once they submit a review, so HQ also asks for `reviewed-by:@me`). Orange until the user reviews on GitHub or marks it reviewed in HQ; a new commit after that makes it orange again. It also stands in the notification center's Needs You until the user reviews it or puts it Later (§11, T-319). Status: "Waiting for you", "Approved by you", "Approved by noor", "You asked for changes", "Reviewed". Its **filter**, a pop-up on the card's title line (always there, remembered, accent while off its default, as the Backlog's): **Not Approved** (the default: what nobody approved, the user included, reviewed or not), Waiting for You, All (approved ones too).
- **Yours**: the user's open PRs: "Approved by noor" (green), "Changes requested by theo" (red), "Review required", "Draft"; checks "Checks passed", "Checks failed", "Checks running". A review or a comment by a person, and checks turning failed, are Updates in the notification center (§11), never a mark on the row.
- **Order** (2026-11-06): Reviews, the latest asked first (when GitHub asked the user, else when they reviewed); Yours, the latest updated first. Each group shows five rows, then "Show N More".
- A click selects a PR's row, a double-click opens its modal (its GitHub page, §8). "Open GitHub" opens github.com/pulls. Context menu: Show Details, Open on GitHub, Mark Reviewed, Start Review Session…, Link to Task…, Remind Me… (T-343), Copy (its line: "PR acme/registry#418: Title", T-358), Copy Link. ⌘C copies the selected row's line.

### Files and Artifacts

- An artifact's title is its own: the `<title>` of the page a session published (HQ captures the page the publish made or updated, never one it only copied files from), and, once HQ shows the artifact, the title its page reports. **Remove from HQ** in an artifact's context menu takes any entry off the list (the page stays on claude.ai; Undo). **Link to Task…** in a file's, an artifact's or a PR's context menu opens a finder under the row: type a title or a number, ↑ ↓ to choose, Return or a click links.

- The same cards as the PRs', rows of one line, 32 pt (2026-11-05): the maker's face (a dashed square without one, as everywhere; a click shows its session's menu at once) · kind tile (a file: teal, `doc.text.fill`; an artifact: indigo, `globe`) · the title, then its project and up to two tags as label chips (§7) · in the PR rows' status column, its date ("2 hours ago"), right-aligned against the pin · in their key column, a pin (`pin.fill`, accent, when pinned; `pin` on hover). The maker is in the tooltip. The project chip is a button, as on a task's row: None, the projects, New Project…; with none, a quiet `shippingbox` alone.
- **Order**: pinned first, then the newest. Five rows, then "Show N More". The page's search, the section's search and Pinned Only filter both cards ("2 of 8").
- A click selects a row, a double-click opens it. Context menu: Open, Pin or Unpin, Link to Task…, Remind Me… (T-343), then Open in Obsidian, Copy and Delete (files: the note goes to the Trash, Undo brings it back) or Open in Browser, Copy and Copy Link (artifacts). Copy gives the item's line (`File "<name>"`, "Artifact <address>: Title", T-358); ⌘C copies the selected row's.
- Files and artifacts take a project, tags and a pin like tasks, in their modal's header line: files keep them in their front matter (`project`, `tags`, `pinned: true`), artifacts in HQ's store.

## 7. The outline: Tasks and Backlog

One AppKit outline (`NSOutlineView`, view-based) holds both lists, so cards drag between them and the arrow keys run across both. Edited like a markdown todo file. **Each task is a card, each story a block** (2026-11-10, T-372): a top-level task is a story's goal, on a big card; a task whose subtasks show is a **block**, a tray (a shade under the cards, radius 16 at the top level, 12 inside) holding its card or header and its subtasks' cards; trays nest. A task with no subtasks open is a card (radius 10; the big card 14): raised, a red edge while Blocked (no edge for doing: too loud, 2026-11-10), flat and quieter once done. Cards and trays are Core Animation layers behind the rows, so a scroll redraws nothing (T-337); each card keeps its layers, so as a task folds or unfolds the cards and trays slide with the rows (0.25 s). The cards reach the section's edges, as the other sections' cards: no lines between tasks (2026-11-10). A card's selection and drop highlight are its own (below).

**Selection lights what's related** (2026-11-10): while tasks are selected, every other card fades (35%), but theirs, their parents and subtasks, what blocks them and what they block, what they come after and what comes after them. That's how "after" shows in the list.

**Indents and spacing** (2026-11-10, after the first preview): a subtask's card sits 24 pt in from its parent's, every level, but a story's own subtasks, which sit full width under its big card. A story's tray has 10 pt of padding, a block's 8. 8 pt between cards, 24 pt between stories.

### Card

**The same at rest and under the pointer** (2026-11-10): no grip, no buttons, no empty square appear; the menus and keys do what they did (§13, §18). A card's first line, 36 pt (12 pt in from its left), Body 13:

```
◐ T-282  ⏰ cluster-api: place by instance + optional geo region  • tag     ⊘ T-285  ⑂ #5460 Draft  ▤ 2  ▬▬ 1/3  [face] ⌄
```

- the **face** in its slot at the line's start, every card's (2026-11-10, after the third preview; below) · the **status glyph** (a click moves to the next status, from Done back to Todo, as ⌘Return does; ⌥-click opens the status menu: each status with its glyph, the current one checked; it takes clicks over the line's full height) · the **key**, always (mono, secondary; a click copies its line, "Task T-12: Title", as Copy does, and it turns the accent color a moment) · a **reminder's mark** when a reminder links the task (§11) · the **title**, a text field: a click selects the card, a double-click edits it in place, caret where it landed, and a press that moves drags the card; it truncates first, with an ellipsis, the whole title in its tooltip; `#word` sets the status or the project it names, else becomes a tag, when editing ends; typing after `#` lists the statuses, projects and tags that start so · the **project**, only when it isn't its parent's (a neutral chip, its `shippingbox` in the project's color; a click picks None, a project or New Project…) and the **tags** (a neutral chip with the tag's color as a dot).
- At its end, right to left, what doesn't fit hiding first: the fold **chevron** on a task with subtasks (below), and beside it the **description button** (`text.alignleft`, 2026-11-10, after the fourth preview) on every card with a description, the big card's too: a click shows or hides the description in the card and selects the task; the accent, on a faint accent tile, while it shows. Both keep their room on every card, so they line up down the list · a block's or a folded task's **progress** ("2 blocked" in red, a 64 pt bar of everything under it by state, "1/3"; "2 done, 1 doing, 1 blocked, 2 to do" in its tooltip) · its **links** (below) · the tasks it's **blocked by**, still open, a red capsule each ("⊘ T-268"; below).
- Under the first line: a Blocked task's reason, in red; its description when shown, from the glyph's right.
- **Three modes for its subtasks** (2026-11-10, after the third preview): **all**, **only what matters** (the subtasks blocking another task, at any depth, and its first five doing ones, each the deepest of its branch, with the tasks between them and it, as the same cards; Blocked ones and the ones waiting on a blocker don't count), or **none**. The chevron shows which (`chevron.down`, the filter lines, `chevron.right`) and a click steps all → what matters → none → all, passing a mode that would show the same; its tooltip says what shows and what a click does. ← shows fewer, → more (on a task with none, ← selects its parent; on one with all, → its first subtask); ⌥← and ⌥→ set none or all on it and every task under it; the card's menu has Show Subtasks › None, Only Blocking and Doing, All. A subtask nobody set follows its parent's choice, and its chevron says what that leaves on screen; its own choice wins under it (a click on it shows the rest). With none to show: its card alone, its progress at its line's end. A search shows all it finds. Remembered per task; the tasks folded before the modes stay hidden.
- **Face** (22 pt), in a slot at the start of every card's first line, before the status glyph, as on PR, file and artifact rows (2026-11-10, after the third preview; it was at the card's end): the session that matters most (one that needs the user, else one working, else the latest active open one, else the latest ended one, dimmed); the tooltip names them all; an orange or red badge when it needs the user; a click shows its session's menu (§10). Only the task's own sessions, never its subtasks' (T-346). A subtask whose session is its parent's leaves the slot blank (one mark per meaning; Geo Region had the same face on 17 cards). No session on it: a plain avatar, a quiet gray tile with a silhouette (`NoSessionFace`); a click offers Start Session… (⌥⌘Return).
- **The big card** (a top-level task, 14 pt padding): its first line holds the face, glyph, key, project and tags, and at its end the same as a card's; then its title on a line of its own in Title 3 bold (no description line since the third preview: its description button and ⇧Return show it); a Blocked reason; and with subtasks its **progress line**: a 200 × 6 pt bar of its subtasks by state (done green, doing yellow, blocked red, the rest the track), "**1** of **17** done", and how many are doing, blocked and ready, each with its color's dot.
- A block's header (a subtask with subtasks of its own, open) has no card: it sits on its tray, semibold. A status glyph pops when the user changes it (§12).
- **Selected**: a 2 pt accent ring on the card's own layer, whole, and a faint accent tint, as a session card (2026-11-10); gray, without the ring, while the outline doesn't have the keyboard. A double-click on the card outside the title and description, Space or ⌘I opens the task's window. One task at a time (2026-11-10, after the fourth preview: moving several crashed; back in a later version).
- **Padding**: 12 pt left and right in every card; a top-level task with no tray of its own gets a story's tray padding too, so every top-level glyph, title and end line up, folded or open (2026-11-10).
- **No types** (2026-11-06: they don't use them): the page, the modal, the menus, the Backlog's filters, `hq` and its skills (2026-11-09, T-220) have none. Older notes keep their `type:` as written; `#bug` in a title is a tag.
- **Three statuses** (2026-11-06): Todo, Doing, Done. What the user must check is a notification (§11) and the task stays doing; nothing on a row asks for the user.

### Blocked, blocked by, after

Where a story stands, and what holds it (2026-11-10, T-372). The tree is the plan: a task needs its subtasks. Three things more, stored in the task's note (PLAN.md §5):

- **Blocked**: it can't be done now. A reason is optional; it holds until the user or a session unblocks it. The glyph stays the status (2026-11-10); the card takes the red edge and the reason under the title, in red.
- **Blocked by a task**: it can't go on until that task is done, then it lets go on its own. No reason. A red capsule per open blocking task at the card's end, "⊘ T-268" (three, then "+2"), its title in the tooltip, the pointing hand over it: a click selects that task and brings it into view, unfolding its parents (behind "+2", a menu of the others). No line (2026-11-10).
- **After a task**: the order the user means. In the list, only through the selection (above): the tasks it comes after stay lit. Its window lists both (§8).
- **Nothing moves on its own**: neither link changes the order, which the user sets (a drag, ⇧↑ ⇧↓) or a session, through `hq`.
- Worked out, never stored: **ready** (todo, not blocked, nothing it comes after still open), the progress line's counts, a done task holding nothing.
- **Setting them**: Block… (B) asks for an optional reason, Unblock (B again) clears it; Blocked By… (⇧B) and After… (A) pick a task in a popover under the title ("Search a task, or type its key"; the story's open tasks first, for After the one above first; a link that would go in a circle, or that the tree already says, isn't offered). In the row's menu and Task in the menu bar too, with "Not Blocked by T-n" and "Not After T-n" to take one off. And a task dropped on another (§7, Drag and drop).

### Keys

Keyboard first, as in an outliner: the rows take arrows and single keys; a title or a description takes text until Escape gives the keyboard back to the rows. On the page, Tab and ⇧Tab move the keyboard from section to section (Pull Requests, Sessions, Files and Artifacts, Tasks, round the page, skipping empty ones); the section left unselects, and gets its selection back when Tab returns; the page scrolls the selected row or card of the section that takes the keyboard into view (the arrows too); in each, the arrows move the selection and Return or Space opens it (Return opens a session in Ghostty). In a title or a description, Tab still goes between them.

On the selected row (one at a time, 2026-11-10):

| Key | Does |
|---|---|
| ↓ ↑ | next / previous task; ↓ on a list's last task types in its new task's card (in a task's window, the new subtask's) |
| Tab ⇧Tab | next / previous section |
| ← | fewer subtasks: all → only blocking and doing → none; on a task that shows none or has none, select its parent |
| → | more subtasks: none → only blocking and doing → all; on one that shows all, select its first subtask |
| ⌥← ⌥→ | none or all, on it and every task under it |
| Return, or a double-click on the title | edit the title |
| ⇧Return | show / hide the description |
| N / ⇧N | new task below / new subtask, title edited; it takes the project in effect there (the task's own, or a parent's), written on it |
| ⇧→ / ⇧← | indent under the previous sibling / outdent; a held key does nothing more (2026-11-06) |
| ⇧↑ / ⇧↓ | move among siblings; past the first or last, out one level, above or below the parent; a held key stops at the first or last |
| ⌘Return | next status (Todo, Doing, Done, Todo…) |
| B / ⇧B / A | Block… (or Unblock) / Blocked By… / After… (§7) |
| Escape | unselect the task: nothing stays dimmed; in a task's window with nothing selected, close it |
| Space, ⌘I, a double-click | open the task's window |
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

Markdown, inside the task's card under its first line (the card grows), rendered (§9). Shown per task with its card's description button (§7, Card; 2026-11-10, after the fourth preview), ⇧Return or Show Description in its menu (even when empty, to write one), or by its list's Descriptions for every task that has one. A double-click or Tab from the title turns it into the markdown editor in place (a click selects the row and still reaches links, checkboxes and chips; the outline's descriptions aren't selectable text); a double-click puts the caret on the source under it, since the editor shows the same text in the same place (2026-11-09, T-368); the editor takes the rendered text's exact place and size, its box drawn 4 pt around it, and grows with its text up to 480 pt, then scrolls (2026-11-10: the row doesn't move); Escape or ⌘Return saves and ends editing. A description shows its first 20 lines in the outline, then "N more lines: open the task to read them all." (2026-11-05); the modal shows it all. An empty description hides again when editing ends. No comments anywhere: a task has a description only.

### Links on a card

At the end of a card's first line (2026-11-10, after the first preview), in one family: same size, same weight, secondary; only a PR's or an issue's state colors its icon (open green, draft gray, merged purple, closed red).

- **A PR**: its state's icon (open green, draft gray, merged purple, closed red), its number, and where it stands as a symbol after it (2026-11-10, T-393): a green ✓ approved, a red ✗ changes requested or checks failed, a gray dashed circle a draft; nothing in review; merged and closed say it with their icon. The words ("#5460 · Approved") are in its tooltip and in the task's window. **An issue**: its icon and number. Two of them, then "+3". On a short line the symbols go first, then the links.
- **Files, artifacts, Slack messages and web pages**: an icon each (`doc.text`, `globe`, `text.bubble`, `link`), with a count when several ("▤ 2").
- A click opens the link (several of a kind: a menu of them, a pick opens it); a right-click shows its menu (§4; several: the same pick menu); the tooltip names them all. The pointing hand over each.
- **A PR shows on the task it's linked to**, by the session that works on it or by the user (`hq task link`, a drop): HQ never links a session's PRs to its tasks on its own (T-393: a session on a story put every PR on all 17 of its tasks).
- **Linked tasks** (`hq task link T-12 T-34`, or T-34 dropped on T-12 and Link to) aren't drawn on the card: T-12's window lists them.

### Quick add

A **new task's card** follows each list's last card ("New Task", "New Backlog Task" in the Backlog; 2026-11-10, after the fourth preview): a card one line tall where a top-level task's would be, its edge dashed and no fill, an accent `plus.circle.fill` where a task's glyph sits and the placeholder in secondary where its title does, the face slot empty. A click anywhere on it, or ↓ on the list's last task, types in it, and it turns into a raised card with the selection ring; ↑, ⇧Tab or Escape go back to the last task. Return adds the task at the end of Tasks or the top of the Backlog and keeps the field for the next one; ⌥Return in the Tasks line sends it to the Backlog. `#tags` work. A task's window ends its subtasks with the same card, "New Subtask" (§8): ↓ on its last subtask types in it, ↑ goes back, Escape closes the window.

A Slack link pasted into the line becomes the task's link (T-313): out of the title, at the line's end as a short chip ("#registry") with × to drop it. Return adds the task with the link (one Undo); Escape drops both.

### New Task…

**New Task…** (⌘N, ⌥⌘N New Backlog Task…, + › New Task…, the menu bar and Dock menus; T-332, 2026-11-08) opens a small sheet of its own (560 × 328 pt), laid out as New Reminder… (§11): **Task** (the title, the keyboard in it; `#tags` work), **Description** (optional markdown, two to four lines), **In** (segmented: Tasks, Backlog), **Project** (a pop-up: None, then every project), **Links** (below), then Cancel and **Add Task** (Return in the title, or ⌘Return). The task goes at the end of Tasks or the top of the Backlog, one Undo; the sheet goes, its list unfolds and its row is selected. The lists' New Task lines stay for adding in place.

**Links**, in New Task… and New Reminder… alike (T-333): the chips of what it will link, each with ×, then **Link…** (the same popover as a task's, §8). A Slack link on the clipboard comes on its own, as Things' Quick Entry with Autofill brings what the user was looking at: a short chip, and the title takes the message's first line until the user types their own. It comes to every new sheet while it's on the clipboard; × drops that copy for good. A Slack link pasted into the title becomes a link, out of the words.

### Search and filters

Each list has its own search field in its header ("Search Tasks", "Search Backlog"; Escape clears it). A search shows the tasks whose title (or key) has every word, and their parents, nothing else: not a match's siblings, not its subtasks. The toolbar's search does the same in both lists. "3 of 14" in the header while one runs.

The Backlog's **filters**, three pop-ups in its header, each its icon and its value, accent while it narrows the list: Status (Open = not done, the default; Todo; Doing; Done; Any), Project, Tag; `xmark`, always there, clears them all and the Backlog's search, off while neither applies (2026-11-05). A top-level task shows when it or one of its subtasks matches a filter; its subtree shows whole.

### Done

A done subtask stays checked under its parent (its list's Hide Done hides it). A done top-level task stays where it is, checked, until the user moves it (Hide Done hides it in Tasks, the Backlog's Status filter there); no task moves on its own (2026-11-09, T-345).

### Order

The user's, by drag or keys. A task Claude creates goes to the end of Tasks; to the top of the Backlog only when the user asks for the Backlog (`--backlog`, 2026-11-07).

### Drag and drop

The most important interaction. It must feel buttery smooth.

- **The whole card drags** (2026-11-10, after the first preview; no grip). A press anywhere on a card that moves, its title included (except a title being edited, and its glyph, face, chevron and links), drags the task: between cards it moves there; on a task's card the drop menu asks (below); on a session card it links to that session; in another app (Ghostty) it types the task's line. The drag image is the card alone, not its row with the gap and tray around it (2026-11-10).
- **A line for other apps** (T-348): every item dragged out of HQ, and Copy (§13, T-358), gives one line per item, its kind, its key and its title, what a session can act on: "Task T-12: Retry budget for blob uploads", "PR acme/registry#418: Retry budget", "Issue acme/registry#77: Flaky push", "Session <id>: registry: retry budget", `File "2026-11-09 - Jobs network"` (the name `hq file show` takes), "Artifact <address>: HQ Notification Center", "Slack <address>: Julien in #registry: …", "Link <address>".
- **Where it lands shows before release; the cards hold still** (2026-11-10, after the third preview: the cards parted to make room as the pointer came near, so the one aimed at moved away and nothing could be dropped onto a card): over the middle of a card, that card takes a 2 pt accent ring and a touch of the accent (the drop menu asks, below); over its top or bottom quarter (8 pt at most) or the gap between cards, an accent line with a ring at its start shows where it goes, at the left of a card of that level. On a list header, the item goes to the end of that list. The page scrolls near its edges.
- **It lands where it's let go** (2026-11-10): a moved card takes its place at once, where the line was; nothing slides back from where it came from.
- **Tasks dropped on a task ask** (2026-11-10, T-391): released on a task's card, a menu opens where they landed: Add as Subtask(s) of T-n, Add Above T-n, Add Below T-n, then Link to T-n, T-n Is Blocked by …, … Blocked by T-n, T-n Comes After …, … After T-n; what can't be (into its own subtree, a circle) is dimmed. Escape leaves everything as it was. PRs, files and artifacts dropped with them link at once.
- Never into its own subtree: the outline refuses it and the cursor says so.
- A cancelled drag (Escape, or a drop outside the window) leaves nothing behind. The rows hold still until AppKit ends the drag, also after a drop elsewhere in the window and while a refused drag's image slides back: AppKit closes its drop gap on the rows it had (2026-11-09, T-353, a crash). A drag whose end never comes lets them go 3 s after the button is up.
- Every drop is one Undo step. Option copies nothing: tasks are unique, so the cursor shows a move only.
- A task dropped on a session card is linked to that session (§5).
- **Linking by drag**: a file, an artifact or a PR (its row in Files and Artifacts or Pull Requests) dropped on a task's card links it to that task: the card under the pointer highlights, the link shows on it, one Undo. Something already linked there is refused. A task asks (above). Other apps get its line.

## 8. The modal

A native sheet over the window, about 88% of the window's content (at least 720 × 520), the window dimmed by the system. Inside, the canvas with the item's sky (§12), and each group (a task's properties, description, subtasks, links; a session's needs-you box, Works on, Made and linked, Last message, Details; a PR's review box; the notification center's sections) on a raised card; a session's needs-you box and a PR's review box glow orange (red when failed) instead of a tinted fill. The start form and Closed Sessions are small: their sheet stays at 720 × 520.

**Copy and Remind Me…** (2026-11-09, T-358, T-343): every item's header has **Copy** first among its actions, after Reload on a page (`document.on.document`, a checkmark once copied, as wide either way; it copies the item's line, §7, and its tooltip shows it), and a task's, a PR's, a file's and an artifact's with **Remind Me…** (`alarm`: New Reminder… about it, §11). A PR's and an artifact's keep Copy Link beside it: the address alone, for a browser or a message.

**Header bar**, on the canvas with no rule under it, every button glass (`glass`; the kind's actions as one `GlassEffectContainer` group; the one prominent action in `glassProminent`): Close (Escape, a glass circle) · **Back** ("‹ T-13 Retry budget…", ⌘[) when something was open before · the title · the kind's actions (one prominent at most). Its controls sit as far from the sheet's sides as from its top (Close centered 26 pt from both, the last button 14 pt), so they nest in the round corners as the window's traffic lights do. Opening an item from inside the modal pushes it on the Back stack (a link in the notification center too, so Back returns to the center); opening from the page starts fresh.

| Kind | Holds | Actions |
|---|---|---|
| Task | key and place ("On the overview", "In the Backlog", "Subtask of T-13"); title (Title 1, editable); with subtasks, its progress line as on its big card (2026-11-10); Status (segmented: Todo, Doing, Done); Blocked (its reason in red and Unblock, or "No" and Block…, 2026-11-10); Project (its chip: a click picks None, a project in use or New Project…, a right-click its color); Tags (chips: a right-click sets the color or removes the tag; + adds one, completing from the tags in use); On it (session chips with face and state, Start Session…); Description (rendered, Edit; checkboxes tick in place); **Blocked by, after and linked tasks** (2026-11-10: the list shows these as chips and on selection only): Blocked by and Comes after, each task's glyph, key and title, a click opens it, × takes the link off, then **Blocked By…** and **After…** (the same picker as on a card); Blocks and Comes before, what waits on it; Linked, the tasks linked to it, × unlinks; **Subtasks**, under them: the list's own outline, only its descendants (2026-11-10, after the third preview): the same cards, faces, chips, links, three-mode chevrons, drag, menus and keys, its own selection; a double-click on a card or Space opens a subtask's window over it, a double-click on its title edits it; a blocking chip for a task outside it opens that task's window; then the new subtask's card, as a list's new task card (§7, Quick add; ↓ on the last subtask types in it, ↑ goes back, Escape closes the window); Files, artifacts, PRs and issues (face, kind, title, a PR's status in words and its time; × unlinks what was linked by hand, one Undo; **Link…**, always there: a popover, "Search, or paste a link": a pasted address first (a PR or an issue, an artifact, a Slack message, or any web page), then the task a key names, then the tasks (once something is typed), files, artifacts, PRs and issues whose title has the words, none linked yet; ↑ ↓ or the pointer move through them, Return or a click links one (T-333). The same popover opens under a task's row from its context menu and from Task › Link… (T-298)) | Copy, Remind Me… (icons), Delete, Move to Backlog / Add to Tasks, Open in Obsidian |
| Session | face 72 pt, name, `repo · branch`, state pill; the needs-you box (a question with its options, a plan rendered, a permission with the tool and input in mono, an error); Works on (tasks, unlink with ×); Made and linked; Last message (markdown); Details (directory, branch, started, session id, copyable) | Copy (an icon), Close Session, Fork Session, **Focus** or **Resume** |
| File | the note rendered, Edit (⌘E) for the editor in the same column, so the text starts and wraps where it does when rendered; Escape or ⌘Return saves (2026-11-05), Cancel drops the changes; "Written by <session> · 20 minutes ago" | Copy, Remind Me… (icons), Delete (to the Trash; Undo), Edit, Open in Obsidian; while editing, Cancel and Save |
| Artifact | the live page (`ArtifactReader`, sign-in unchanged) | Reload (its arrow turns while the page loads, 2026-11-06), Copy, Remind Me…, Copy Link (as wide with its checkmark as with `link`), Open in Browser |
| Pull request, issue | one line: state pill, author, branch, review state, checks in words, then its linked tasks (a click opens one) and sessions' faces, and Link (to a task or a session); the review box while it waits for the user ("noor asked for your review 2 hours ago", Start Review Session…); under them, the page itself on github.com in a web view (2026-11-05: no leaving HQ to read or review). HQ keeps its own GitHub sign-in apart from the browser's; a sign-in and an organization's single sign-on stay in the view, a link the user clicks to another site opens in the browser | Reload (⌘R), Copy, Remind Me…, Copy Link (⇧⌘C, `link`, a checkmark once copied), Mark Reviewed (while waiting), Open on GitHub |
| Notifications | the notification center (§11): Needs You, Updates, Later and Earlier | none |
| New Reminder | Remind me to, When, Important (§11) | Cancel, **Add Reminder** (⌘Return) |
| Start a session | Name (prefilled "T-13 Retry budget for blob uploads"), Folder (pop-up, preselected: the folder of the task's project, or of a parent's, or of the project the PR's repository belongs to (Settings › Projects); then the task's sessions' folders, recent folders, Choose…), First message (multi-line, prefilled; the message editor has the keyboard, caret at the end) | Cancel, **Start** (⌘Return) |
| Closed Sessions | the sessions closed in the last 14 days | Resume |

Close Session on a running session types `/exit` and Return into its terminal, then closes the terminal once Claude has quit; a background session is stopped with `claude stop` (§5); one HQ reaches neither way opens its modal, which says it can't be brought forward or closed from HQ. Starting a session writes the first message to `~/Library/Application Support/HQ/Prompts/<uuid>.md` and types `claude --session-id <uuid> --name '<name>' "$(cat '<path>')"`: fish, zsh and bash all read it. If Ghostty can't be reached, the form stays with its text and the banner says why, with Try Again.

## 9. Markdown and Mermaid

- **Viewer** (`MarkdownView`, Foundation's parser through `HQKit.Markdown`): headings (Title 2, Title 3, Headline), paragraphs keeping single line breaks, lists with nesting, **task lists whose checkboxes tick in place** (`- [ ]` ↔ `- [x]` in the source, one Undo step: in a task's description and a file's view), quotes with a bar, tables, rules, code blocks with Copy, inline code, bold, italic, links (the browser), `[[wikilinks]]` (Obsidian), Mermaid blocks drawn by the bundled mermaid.js as images (`MermaidRenderer`).
- **Editor** (`MarkdownEditor`, an `NSTextView` on TextKit 1): **one look with the viewer** (2026-11-09, T-368): the viewer's fonts and heading sizes (Title 2, Title 3, Headline). **Switching moves no text** (2026-11-10): no inset, the editor takes the rendered text's place and width; each line is as tall as SwiftUI draws it (measured per size, since TextKit's line height differs at some sizes) and as far below the line above as the viewer puts it: 12 pt between blocks (the blank lines between them share it), 4 pt between list items, a heading's room above, a code box's padding taken from the space around its fences. Only what the marks add (their own lines, a longer line that wraps) moves text; a self-test holds sample documents to the viewer's height and a UI check holds the editor to the rendered text's frame. In the task's window only the text turns into the editor: the card stays, with an accent outline while editing, and Done takes Edit's place at the same width; a note keeps its byline, labels and title, the page scrolling with the caret; the marks (`#`, `**`, `_`, backticks, a link's brackets and address, `>`) in the quiet tertiary, list markers and checkboxes secondary, a done item's text secondary, bold and italic drawn, links in the link color, mono only in code (blocks at the viewer's code size, inline code at the text's). Return continues a list (`-`, `1.` counting up, `- [ ]`, `>`) and ends it on an empty item; Tab and ⇧Tab nest a list item under the one before and take it out (by its marker's width; off a list, Tab does what it did); ⌘B, ⌘I (`_`) and ⌘K (a link to a copied address, or the caret where it goes) mark the selection and take the marks off again, before the menus (⌘I is Open outside the editor); an address pasted over words on one line links them; a click on `[ ]` ticks it, one Undo step, the pointing hand over it. A double-click on rendered markdown (a description in the outline or the task's window, a note) opens the editor with the caret on the source under it (`EditOnDoubleClick`). Undo, Find (⌘F, its own find bar; ⌘G, ⇧⌘G), no spell check. Saves when editing ends: on Escape, ⌘Return, or when the user leaves (a file's Cancel is the only way to drop an edit). The same editor serves descriptions (in the outline and the modal), files and a session's first message. Its styling runs on every keystroke; a self-test holds a 3,600-line note under 40 ms.
- **Done items** in the viewer: their text secondary, behind the open ones (2026-11-09).

## 10. Faces

Each session gets a face generated from its session id, the same everywhere (cards, rows, PR rows, chips, modals, Quick Open). The user tells sessions apart by their faces at a glance.

- **One vector family** on a 40 × 40 grid: rounded joins, one stroke weight (1.3 at 40), friendly and calm, not childish, harmonious with macOS colors. A squircle mask (30% continuous corners).
- **Parts**: backgrounds (12 colors in two OKLCH tiers, pastel and deep, none near system orange or red); patterns at large sizes (two-tone diagonal, soft stripes, rings, dots); skin tones (9: three light, three medium, three deep by CIELAB lightness, T-293); face shapes (4); hair (10 styles × 8 colors, two playful); headwear (10: none, beanie with pompom, cap, top hat, beret, party hat, headband, crown, bucket hat, hood); eyes (6); eyewear (6: none, round, square, shades, visor, monocle); facial hair (5); mouths (6); extras (headphones, earrings, freckles, blush); clothes (10 colors).
- **Rules** (`HQKit.FaceSpec`): no hat over a hairstyle it would clip badly, eyes hidden under shades and a visor, features at least 3:1 against skin, skin at least 1.4:1 against the background (otherwise the part is drawn again from the same seed stream).
- **Level of detail**:

| Size | Draws |
|---|---|
| up to 20 pt | solid background, head, hair or headwear silhouette, two eye dots, dark eyewear; strokes at least 1.25 pt |
| 21 to 31 pt | adds eyes, mouth, facial hair, earrings |
| 32 pt and up | everything: patterns, freckles, blush, fine details |

- **Distinct** (T-293, 2026-11-08): a new session's face shares no background and headwear, and no skin tone, with an open session's, and takes the skin group (light, medium, deep) the open sessions show least, so the grid shows every group. Its salt, the first of 16 tries that fits (the group rule gives way first, then the tone), is stored, so a face never changes. **Randomize Face** in a session's menu draws another one at random, the open sessions not looked at, one Undo (T-334).
- **Ended**: the face fades (45%) in its own colors, so it stays recognizable in Closed Sessions.
- **Working**: the head sways from the chin, 8° each way and nods down at each end, one sway every 2 s, each face from its own point so faces side by side don't move together; shoulders and background stay still. Everywhere the face shows (cards, the outline, rows, chips).
- **Click**: every face, anywhere (cards, the outline, PR, file and artifact rows, chips, the modal), shows the pointing hand, and acts on the press (AppKit takes it, so no row waits out a double-click: 2026-11-05). On a card, a click focuses the session's terminal (§5). Elsewhere it shows its session's menu under the face, their left edges lined up: Focus or Resume (an ended one asks "Resume …?" first), Show Details, (on a task's faces) Start Another Session on T-12…, (on a PR's) Start Another Session on registry #418…, Close Session, Randomize Face, Copy, Copy Resume Command, Copy Session ID. Where a task or a PR has no face, its dashed square starts a session.
- **Badge**: an orange (needs the user) or red (failed) disc at the bottom right, 30% of the size (at least 7 pt), ringed with the surface color. Tooltip and VoiceOver label: "<session name>, <state>".

## 11. Notifications

Notifications are events the user reads once; the page keeps showing state: face badges, the orange glow of a session that waits, Reviews' "Waiting for you" (2026-11-06). Selecting or opening an item on the page reads nothing.

- **Needs You, orange**: a session that asks, wants a permission, has a plan ready or failed (red), for as long as it waits; a ping; a due important reminder. The bell (§3), the menu bar icon and the Dock badge count it, and the sky turns warm (§12). A PR waiting for the user's review counts too (2026-11-07, T-319): it stands in Needs You until reviewed.
- **A card glows**: while its session needs the user (orange; red when it failed), its edge and the light around it breathe softly, 0.9 s each way, until the user clicks the card, opens it, focuses it or looks at its terminal (the watch below); then it holds a faint glow while the state lasts. Its next state breathes again. What the user acknowledged is kept, so HQ starting doesn't make it breathe again.
- **A turn end notifies nothing**: the session's card says "Done" lightly (§5), no glow, no blink, until the user opens it or looks at its terminal.
- **Looking at a terminal reads it**: while Ghostty is in front and a card breathes or a done session waits unread on a terminal, HQ reads the focused terminal's tty every 2.5 s (AppleScript off the main thread, only with the Automation grant, never a prompt, nothing while Ghostty is in the back); within a few seconds the card on that tty stops breathing and a done session there is read. A session that asks, wants a permission or has a plan stays orange: it needs an answer, not a look.

### The notification center

- **A sheet** like a file's or a PR's (the large modal, §8). ⌘J, the toolbar's bell, the menu bar icon, Go › Notifications, the Dock menu and a banner open it. Each row is read, done or put Later on its own, never all at once (2026-11-07, §19).
- **Sections**, top to bottom: **Needs You** (the sessions that wait on the user, each with what it asks and Focus, gone once it moves on; the PRs that wait for their review, each with Review and Later, gone once reviewed (T-319); then the unread important rows: pings and due important reminders) · **Updates** (unread update rows, due reminders) · **Later** (reminders and rows put away until a time, with that time, "Tomorrow 9:00") · **Earlier** (what was read or done in the last day; folded by default as a page section folds, a click on its title shows it, remembered; open: the 5 latest, then "Show 7 More"). Needs You and Updates both empty: "All caught up" under a green `checkmark.seal.fill`, nothing more (`AllClear`, as Reviews says "All reviewed"); the reminder editor opens above it.
- **A row**, as macOS draws a notification (2026-11-06, second pass; no unread dot since 2026-11-07, T-320): the session's face, the PR's kind tile, or a reminder tile (an alarm, orange when important), at the row's left padding as in the other lists · a title line: who, bold while unread (the session's name, the PR's "registry #418", "Reminder"; a click opens it), for a PR or an issue its title after it, regular and secondary, the first to truncate (T-360), "3 updates" when several events merged into it, the time on the right, when it happened ("14m ago": a review's or a comment's own time, not when HQ heard of it; in Later, when it comes back) · the text, two lines at rest, **all of it and selectable once the row is selected** (its tooltip has it too, and Copy Text) · its links as chips: a click opens the item over the center; it reads a notification, never completes a reminder. Nothing is ever dimmed.
- **Selection and hover** draw as the other lists' (`rowHighlight`: `Radius.row`, inset `Space.xs + 2` in its box, the accent selection while the center has the keyboard).
- **Actions** float over the row's trailing end on hover and while it's selected, a small lifted bar: **Edit** (reminders) · **Later** (the When picker), or in Later the time, which changes it · **Read**/**Mark as Unread**, or for a reminder **Done**/**Mark as Not Done** · **More** (its context menu: Open, Edit…, Read or Done, Later › its choices, or for a reminder Remind Me › In 1 Hour, This Evening, Tomorrow, Next Week, Pick a Time…; in Later, Bring Back Now; Copy Text, Delete).
- **A row moves at once** (2026-11-09, T-365): read, done, undone, put Later or edited, it goes to its section while the center shows (to Earlier when read or done); a selected one hands the selection to the row after it (else the one before), so E, E, E goes down the list; ⌘Z brings it back. A notification is read once opened; **a reminder is a to-do**, done only with Done (E): a due one stays in Needs You or Updates until it's done or put Later.
- **The When picker**, the one place a time is picked (Later, a reminder's time, a Later row's time): a popover with a field on top ("Tomorrow 9am, in 2h, fri…"), what it reads shown in full as the first choice ("Friday 13 November, 15:00"), then In 1 Hour, This Evening (until 17:00), Tomorrow and Next Week, each with its time on the right ("Sat 9:00"), and Pick Date & Time… (a calendar and a time, Set). ↑ ↓ or the pointer move, Return or a click picks. It reads `16:00`, `9am`, `18h30`, `in 2h`, `tomorrow 9:30`, `mon`, `next week`, ISO dates, and wordier English as macOS reads dates in text ("next friday at 3pm").
- **New Reminder…** (⌃⌘R, + › New Reminder…, the menu bar and Dock menus; 2026-11-07) opens a small sheet of its own (560 × 262 pt), laid out as Start a Session: **Remind me to** (the keyboard in it), **Links** (as New Task…'s, §7: chips with ×, Link…, a copied Slack link on its own, which names the reminder until the user types; T-313, T-333), **When** (a button: the When picker; Tomorrow 9:00 by default), **Important** (a checkbox, on: it needs the user when it comes back, with a banner), then Cancel and **Add Reminder** (Return in the text, or ⌘Return). Added, the sheet goes and what was under it shows again. The center has no form of its own for a new one.
- **Remind Me…** (2026-11-09, T-343) on a task, a PR, a file or an artifact: a task row's alarm under the pointer (beside Add Subtask), the item's context menu, its modal's header and File › Remind Me… open New Reminder… about it: the item linked (its chip short, "T-13", × drops it), its title the words, shown in the field, until the user types theirs; a Slack link on the clipboard doesn't come along. Over a modal, Add Reminder and Cancel go back to it.
- **The reminder editor**, a row, edits one in place: the reminder tile, its text, the time (a button: the When picker; "Now" for one that came back), **Important** (a flag toggle), Cancel, Save. Return saves, Escape cancels. Edit, Return on a reminder that links nothing, or a double-click turn a reminder's row into it.
- **Keys**: ↑ ↓ move, Return (or a double-click) opens the first link (edits a reminder that links nothing), E reads or completes (again: unread, not done), L opens the When picker on the row, ⌫ deletes, ⌘C copies the text.
- **One unread row per source and level**: a new event from a session or a PR updates its row: the latest text, the count plus one, the links merged.
- **A review request stands in Needs You** (T-319), as a waiting session does: the PR's tile, its reference and title on the title line as an update's ("registry #430 Bump tokio to 1.48", T-360) and how long ago the review was asked, "theo asked for your review", then **Later** (the When picker) and **Review** (the PR over the center; Return or a double-click too). Later puts it in Later with its time, then it comes back; its menu has Review, Open on GitHub, Mark Reviewed, Later or Bring Back Now, Copy Link. Reviewing it on GitHub or Mark Reviewed ends it. It counts in the bell, the menu bar and the Dock, and the bell breathes for a new one; no one-off Update repeats it.
- **A reminder shows on what it links** (T-311): a task's, a PR's, a file's or an artifact's row carries a small alarm (`reminder`) before its title while an open reminder links it: orange once due when important, secondary while it waits in Later. Its tooltip says when and what ("Reminder, Tomorrow 9:00: Review the tokio bump"); a click opens the center on that reminder. Done or deleted, it goes. On a task's row the title moves over for it; the lines under the title stay put.
- **Where rows come from**:
  - `hq notify "…"` from a session: Updates. It links the session's open tasks and the files, artifacts and PRs it made since its last notification, or what `--link` names. With `--important`: Needs You, when the user asked to be pinged or the session can't go on without them.
  - Reminders, `hq remind "…" --at <when> [--important]` and New Reminder… (⌃⌘R): in Later until due, then Needs You if important, else Updates. Later on a row puts it there too, and it comes back at its own level.
  - GitHub, all Updates: on the user's open PRs, a new review (approved, changes requested, reviewed) or comment by a person (never a bot, never the user), and checks turning failed. Opened, a review's or a comment's row shows its PR at that review or comment (T-328); a mention or a reply, at its comment. Nothing older than the lookback notifies (Settings › GitHub, 10 days by default; the lookback alone decides since 2026-11-07, T-321): what HQ catches up on when it starts after being off. Event keys are kept 30 days, so nothing notifies twice.
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
| `working` | Claude is working | the accent |
| `failed` | stopped on an error | `systemRed` |
| `doing` | task in progress | `systemYellow` |
| `done` | task done, checks passed, approved | `systemGreen`; words in primary next to a green symbol |
| `blocked` | a Blocked card's edge and reason; the chips of the tasks a task is blocked by | `systemRed`; its words in `failedText` |
| `merged` | PR merged | `systemPurple` |
| idle, ended, todo | quiet | `.secondary`; `.tertiary` only for decoration (it measures under 3:1), never for information |

Tags and projects take a Mac system color (`LabelColor`): one their name gives, or the one the user picks with a right-click in the modal; their chips are **neutral capsules** (`labelFill`, secondary text) with the color only in their mark: a 6 pt dot for a tag, the tinted `shippingbox` for a project. Color never carries meaning alone: every glyph has a shape and a VoiceOver label.

### Type

macOS text styles. Body 13 for titles and rows; Subheadline 11 for second lines, chips and meta (monospaced digits); keys in Subheadline mono (repo and branch lines are Subheadline, not mono); section headers Title 2 bold; the page's day Large Title (bold, then regular); the modal's title Title 1.

### Space and shape

`Space` on the 4 pt grid (`xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · section 32`). Radii: chips 6 (label chips and state pills are capsules), controls 8, rows 10, cards 16, section tiles 7, Quick Open 26; glass controls are capsules; nested corners are concentric (rows sit 6 pt inside a card).

- A row keeps no empty slot for a part it may not have (a face, a key, a dot): the next part moves in, or the slot shows its placeholder (the dashed square) as everywhere else.
- Fixed columns are as wide as their longest real value; the middle grows and truncates with an ellipsis, the edges stay put.
- A control keeps its size in every state (Copy Link as wide with its checkmark as with `link`).
- Glyphs sit centered in their slot at any zoom; controls in a corner sit as far from both edges as the window's own (§8).

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

The pointing hand over everything a click acts on (over the Mac's arrow on push buttons): every button, toggle, pop-up, segmented control and switch while enabled, in the page, the modal, the toolbar and Settings (`handCursors()` on each SwiftUI root gives default-style buttons the hand; the window's own buttons keep the arrow); icons (status, type, pin, close, copy, open on GitHub), faces, chips (links, project, + tag) and checkboxes (`clickable()` in SwiftUI, `trackHandCursor()` in AppKit, a tracking area that follows scrolling). A card's fold chevron is its own button (`HandButton`), not AppKit's disclosure (2026-11-10); a UI check sweeps every AppKit button on the rows for the hand. A card has no grip: it drags from anywhere, under the arrow, as a Finder icon does (2026-11-10). The links on a card get it from their own cursor rects, one per link, the arrow between. The toolbar's items get it from AppKit too (`toolbarClickable()`): SwiftUI's pointer style there comes late and sticks. Rows, cards and text keep the arrow or the I-beam.

## 13. Commands and keys

| Menu | Commands |
|---|---|
| HQ | the system's items, with **Restart HQ** right above Quit HQ (T-336): HQ quits and opens again |
| File | New Task… ⌘N, New Backlog Task… ⌥⌘N, New File… ⌃⌘N, New Session… ⇧⌘N, New Reminder… ⌃⌘R, Remind Me… (the open or selected task, PR, file or artifact, T-343), Quick Open… ⌘K (and ⌘P); Close ⌘W (the modal first, then the window: hidden, Window › HQ ⌘0 brings it back); the open item's way out (Focus or Resume, Obsidian, Browser, on GitHub) ⇧⌘O, Copy Link ⇧⌘C; Import Artifact… |
| Edit | Undo/Redo named after the action, Copy ⌘C (the selected rows, card, PR, file or artifact: their lines, T-358), Find… ⌘F (an editor's find bar while one has the keyboard, else the search field), Find Next ⌘G, Find Previous ⇧⌘G, Jump to Search Field ⌥⌘F (always the toolbar's), Edit File ⌘E |
| View | Show/Hide Descriptions in Tasks, Show/Hide Done in Tasks, Show/Hide Descriptions in the Backlog; Show/Hide Pull Requests, Sessions, Files and Artifacts, Tasks, and the Backlog ⌃⌘B; Refresh Pull Requests, Reviews (Not Approved, Waiting for You, All), Pinned Files and Artifacts Only; Zoom In ⌘+ (and ⌘=), Zoom Out ⌘−, Actual Size, Reload Page ⌘R (an artifact or a PR's page). No toolbar items: the toolbar holds the bell, New and the search, and stays |
| Go | Notifications ⌘J (off while the center shows), Back ⌘[, Mark Reviewed (a PR waiting for the user) |
| Task | Open ⌘I (Space on rows), Mark Done ⌘Return, Status ›, Show/Hide Description ⇧Return (rows), Edit Description ⇧Return (title), Add Subtask, Start Session… ⌥⌘Return, Link…, Block… or Unblock B, Blocked By… ⇧B, After… A (rows), Move to Backlog/Tasks ⇧⌘B, Move Up/Down ⇧↑/⇧↓, Indent/Outdent ⇧→/⇧←, Copy Task (its line), Delete ⌘⌫ |
| Session | Focus (or Resume) ⌘O (off for a running session HQ can't reach), Show Details, Fork Session, Close Session, Randomize Face, Copy Session, Copy Resume Command, Copy Session ID, Start Review Session… (a PR), Closed Sessions (off when there are none) |
| Window, Help | standard; Window › HQ ⌘0 (the window is titled HQ there and in Mission Control); Help › Keyboard Shortcuts opens Settings › Keys |

Task and Session act on the open modal's item, or, with no modal, on the focused outline row or the selected card; File's way out, Copy Link, Mark Reviewed and Start Review Session… act on the open modal's item, else on the PR, file or artifact selected on the page; in a task's modal, Edit Description edits it there, Add Subtask adds to its list, and Open and Show/Hide Description are off. Task's Mark Done, Status, Show/Hide Description, Move, Indent/Outdent and Delete act on every selected row, as the outline's context menu does: Move says where they all go ("Move 2 to Tasks"), Mark Done says Not Done when all are done. Choice menus (Status, Project) check the current value and list None first. Mark Reviewed is undoable, as are a notification's Read, Later and Remove. ⌘P, ⌘= and ⌘Return work with Caps Lock on and from the keypad. Find Next and Previous are on only while a markdown editor has the keyboard. Settings › Keys lists every shortcut. Task items whose keys are also text keys carry their shortcut only while the outline has the keyboard (⌘Return and ⌘⌫ on rows and titles; ⇧Return, ⇧ with arrows on rows), so titles and the markdown editor keep them. The Dock menu: New Task, New Reminder…, Notifications. Tooltips show after 0.25 s (2026-11-10, AppKit's own wait is a second), start with a verb and end with the shortcut: "Mark every notification read (⇧⌘J)"; the bell's starts with what it counts.

## 14. Words

| Term | Means | Not |
|---|---|---|
| Session | one Claude Code conversation | chat, agent, run |
| Needs you | waiting on the user: a session that asks, wants a permission, has a plan or failed; a ping; a due important reminder; a PR waiting for their review | blocked, pending |
| Notification | an event the user reads once, in the notification center | alert, inbox |
| Update | a notification that doesn't need the user: what a session tells them, a review or comment on their PR | news, new |
| Read | a notification the user is done with (Read, E) | seen, dismissed |
| Later | a notification put away until a time; it comes back at its level | snooze |
| Reminder | a notification set for a time, by the user or a session | alarm, todo |
| Working, Idle, Done, Ended | the other session states | busy, finished |
| Focus | bring a session's terminal forward in Ghostty | open in Ghostty |
| Start | a new session in a new Ghostty tab | start in Ghostty |
| Open | a note in Obsidian; a page in the browser; an item in the modal | jump to |
| Resume | start an ended session again in a new Ghostty tab | restart |
| Task · Todo, Doing, Done | a piece of work and its statuses | issue, ticket, card |
| Tasks, Backlog | the two lists: what's on the overview, what's later | board, inbox |
| Project | a larger effort a task belongs to | folder |
| Tag | a `#word` on a task | label |
| File | a note in HQ's Obsidian folder | doc |
| Artifact | a page Claude published on claude.ai | link |

Reasons read as sentences without a subject: "Wants to run Bash", "Asks: …", "Plan ready for review", "Failed: …".

## 15. Setup, health, Settings

- **First launch** shows a setup sheet: Claude plugin (Install), Ghostty access (Allow), Obsidian vault (found, or Choose…), GitHub (`gh` found and signed in, with the account; the fix when it isn't). It closes itself when the first three are green; GitHub is optional.
- **Settings**, one grouped form per tab, 520 pt wide: General (open at login, on from the first launch until the user turns it off; vault), Projects (each project, its chip as the section's header: the folder its sessions start in, Choose…, or the folder its sessions ran in most as a secondary guess; its GitHub repositories, `owner/name`, comma separated; also from a project chip's context menu, "Folder and GitHub…"), Claude (plugin status and Reinstall, last hook event), Ghostty (access status), GitHub (account, last update; Notifications: how far back GitHub events notify, 3 to 30 days), Slack (T-312: the account, a user token pasted and saved in the Keychain, Remove; the scopes it needs; HQ reads a linked message once to name it, never writes to Slack), Keys (every shortcut). Only what works.

## 16. Parts, gallery, sample data

- **DesignKit parts**: `SurfaceModifier` (`.surface()`), `SkyView`, `SectionTile`, `SessionFace`, `SessionGlyph`, `TaskGlyph`, `TypeIcon`, `SessionCard`, `NotificationBell`, `MenuBarIcon`, `RowHighlight` (`.rowHighlight()`), `PRRow`, `OutputChip`, `Chip`, `KeyLabel`, `HeaderButtonStyle`, `HeaderToggleStyle`, `HeaderSearch`, `InlineBanner`, `QuickOpenRow`, `SectionHeader`, `CodeBlock`, `ModalHeader`, `FilterBar`. Each draws every state (rest, hover, pressed, selected, focused, disabled, dragging, drop target) with a forced-state initializer for the gallery.
- **Gallery**: `APP_KIT_GALLERY=1` (parts), `APP_KIT_GALLERY=faces` (120 faces at 16, 22, 40 and 72 pt).
- **Sample data** (`APP_SEED=1`) mirrors the mockup: sessions in every state, tasks with subtasks, tags and projects, descriptions with checkboxes and code, the Backlog, PRs in every state, an issue, files, artifacts, hidden and closed sessions, notifications in every section of the center. `APP_SEED=large`: 500 tasks and 30 sessions.

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
11. **Siblings** (§1.9): the screen beside its nearest siblings shows the same left side, selection shape, gestures (§18), empty state and pickers.
12. **Every state**: each item, in each of its states, has its actions and its whole text somewhere (selected, tooltip, modal); nothing is dimmed and inert.
13. **Edges**: rows with their optional parts missing and their longest values, empty sections, the longest status; no slot kept for a missing part; a control keeps its size in every state (§12).
14. **The user's setup**: a view zoom of about 1.15 (glyphs stay centered), about 1200 pt of content, Reduce Motion on (motion still runs, §12).
15. **Real clicks**: a release has one front UI run with no check skipped (ITERATION.md).
16. **Nothing returns from §19** without the user asking for it.

## 18. Interactions

What each gesture does on each element. Change this table before the code; a new kind of element gets its row here first.

| Element | Click | Double-click | Right-click | Keys and more |
|---|---|---|---|---|
| Task card | selects (one at a time, 2026-11-10) | opens the task (outside its title and description) | its menu: everything the card does | Space or ⌘I opens; Return edits the title; ⇧Return shows or hides its description; ⌘C copies its line; B, ⇧B and A block it, ask what blocks it and what it comes after; a drag from anywhere moves it (onto a task: the drop menu; onto a session card: linked; its line in another app); nothing appears under the pointer (2026-11-10) |
| Task dropped on a task card | — | — | — | a menu: Add as Subtask, Above, Below, Link, Blocked by, After (§7, T-391) |
| Task title | selects the card | edits in place, caret where it landed; the field takes the row's width while edited (T-351) | the card's menu | a press that moves drags the task, as the card does |
| Task description, in the outline | selects the row; its links, checkboxes and chips still act | edits in place, the caret where it landed | the row's menu | Tab from the title edits it; Escape or ⌘Return saves |
| Rendered description in the task's window, a note's page | selects text; links and checkboxes act | edits it, the caret where it landed | the text's menu | ⌘E on a note |
| Checkbox in the markdown editor | ticks or unticks it, one Undo step | the first click ticks it | the editor's menu | — |
| Status glyph | the next status (Todo, Doing, Done, Todo…) | nothing more | the row's menu | ⌥-click: the status menu |
| Task key | copies its line, "Task T-12: Title" | nothing more | the card's menu | |
| Fold chevron, at a card's top right | steps its subtasks: all, only blocking and doing, none | nothing more | the card's menu (Show Subtasks) | ← → step; ⌥← ⌥→ none or all under it |
| Project chip | its menu: None, the projects, New Project… | nothing more | its color (in the modal) | |
| Face on a session card | focuses its terminal (an ended one asks to resume) | nothing more | the card's menu | |
| Face anywhere else | its session's menu, under it | nothing more | its session's menu | on PR rows the dashed square starts a session; a task card with nobody on it shows the plain avatar, a click offers Start Session… |
| Session card | selects | opens its modal | its menu | Return focuses it in Ghostty; Space opens; ⌘C copies its line; dragged among the cards, reorders them; into another app (Ghostty), gives its line |
| PR, file or artifact row | selects | opens its modal | its menu | Return or Space opens; ⌘C copies its line; dragged onto a task, links it |
| Link on a task's card | opens it (several of a kind: a menu to pick one) | nothing more | its menu (several: the same pick menu) | the pointing hand over each; the tooltip names them |
| A blocking task's chip on a card | selects that task and brings it into view, its parents unfolded ("+2": a menu of the others) | nothing more | the card's menu | the pointing hand; its title in the tooltip |
| Notification row | selects; its whole text shows | opens its first link (edits a reminder that links nothing) | its menu | Return opens, E reads or completes, L Later, ⌫ deletes, ⌘C copies |
| A notification's links and name | opens the item over the center (Back returns) | | | |
| Header controls, toolbar and modal buttons | act | | | tooltips name the action and end with its key |

- Where a double-click means nothing more, the click acts on the press: it never waits out the double-click interval (faces, glyphs, keys, chips' controls).
- The pointing hand over everything a click acts on; rows, cards and text keep the arrow or the I-beam (§12, Pointer).
- Everything in a context menu is also in the menu bar, with its key (§13).

## 19. Gone

What HQ had and the user removed, so it doesn't come back by accident. Its names are in `tools/docs-lint.sh`'s retired list.

| Gone | Task | Why |
|---|---|---|
| Folders, the sidebar, the inspector, the view picker, the board | T-46 | one page, everything else in a sheet |
| Comments on tasks | T-42 | too noisy: one current description |
| The Edit button on a description | 2026-11-05 | a double-click edits |
| Several faces on one row | T-213 | one face, the session that matters most |
| Task types on the page and in its menus | T-218 | not used (older notes keep `type:`) |
| Task types in `hq` and its skills (`--type`) | T-220 | not used: sessions set a project, no type |
| Hide on an open session | T-262 | every open session is on the grid |
| Hide Done in the Backlog | T-178 | its Status filter does it |
| Open on GitHub on PR rows | T-191 | in the row's menu and the modal |
| The question on a session card | T-196 | in its tooltip, modal and terminal |
| The task's title on file and artifact rows | T-195 | the date sits on the right instead; the maker is in the tooltip |
| Text under "All reviewed" and "All caught up" | T-172, T-308 | the seal and the title say it |
| "Today" in the toolbar | T-204 | the page's day says it |
| The split arrow on + | T-201 | a menu with no arrow |
| The Review status, Review Next, Mark All Seen, the blue "new" dots and glow | T-294 | events are read once in the notification center; the page shows state |
| Mark All Read | T-310 | each notification is read, done or put Later on its own |
| The unread dot on notification rows | T-320 | it repeated the bold name, the section and the tile |
| The done rule: a done task moving to the Backlog the next morning | T-345 | nothing moves unless the user or a session moves it |
| A folded task's face counting its subtasks' sessions | T-346 | opening a task changed its face; a row shows its own sessions |
| Attaching a background session in a new Ghostty tab (`claude attach`) | T-327 | it didn't work the way the user wants: Focus brings forward a tab that shows it, or says it runs in the background |
| The grip, and carrying a task from the rest of its row to link it | T-348, then T-372 (2026-11-10) | the whole card drags: it moves, a drop on a task asks (Link to among the choices), its line in another app |
| Copy Key and Title ("T-12 Title") | T-358 | Copy gives every item's line: its kind, key and title |
| A notification row keeping its place, read or done, until the center closes | T-365 | the user wants each row in its section at once |
| One card behind each list's rows; subtasks indented 20 pt a level | T-372 | each task is a card and each story a block; a subtask 24 pt in from its parent (2026-11-10) |
| A task dropped on a task's row: its last subtask (by the grip) or linked (carried), at once | T-391 | a menu asks: subtasks, above, below, or which link |
| Buttons under the pointer on a row: + Add Subtask, Remind Me…, Move to Backlog, Delete, the dashed face square, the quiet project box | T-372 (2026-11-10) | a card reads the same under the pointer; the menu and keys have them all |
| The description toggle (`text.alignleft`) after a title | T-372 (2026-11-10) | the description button in the card's corner, beside the chevron (fourth preview); ⇧Return, Show Description in the menu, the list's Descriptions |
| The disclosure triangle on a row's left; the key only under the pointer | T-372 (2026-11-10) | a chevron at the card's top right; the key always, after the glyph |
| A line of link chips under a task's title, whole titles on hover; linked tasks among them | T-372 (2026-11-10) | links at the end of the card's first line, one icon family, a PR's status; linked tasks in the task's window |
| The progress ring on a task with subtasks | T-372 (2026-11-10) | a block's small bar with "2 blocked" and "1/3"; a story's progress line |
| A session's PRs shown on every task the session is on | T-393 (2026-11-10) | a PR shows on the task it's linked to; sessions link it there |
| The lines between tasks: "blocked by" in a gutter on the right, "after" arrows on selection | T-372 (2026-11-10, after the second preview) | a chip per blocking task; selection lights what's related and fades the rest; the task's window lists them; cards reach the section's edges |
| The yellow edge of a doing card; the Blocked and blocked-by glyphs over the status | T-372 (2026-11-10) | too loud: the glyph is always the status, the red edge and the chips say what holds it |
| Quick Look on a task (Space: its description in a popover) | T-372 (2026-11-10, fourth preview) | unclear what it showed: Space opens the task's window again; the description button and ⇧Return show a description |
| Selecting several tasks (⇧-click, ⌘-click) and moving them together | T-391 (2026-11-10, fourth preview) | moving several crashed: one task at a time, back in a later version |
| One fold that hid every subtask (AppKit's disclosure); a folded row opening under a drag | T-372 (2026-11-10) | three modes on the card's own chevron: all, only blocking and doing, none |
| The face at a card's end; nothing for a task with no session | T-372 (2026-11-10, third preview) | a slot at the line's start on every card, as on PR rows; a plain avatar when no session is on it |
| A big card's description line | T-372 (2026-11-10, third preview) | its title and progress only; its description button and ⇧Return show the description |
| Cards parting under a drag (gap feedback) | T-372 (2026-11-10, third preview) | the cards hold still: a line where it lands, a ring on the card it drops onto |
| A monospaced markdown editor in a fixed 160 pt box | T-368 | the editor looks like the rendered text, so switching moves nothing; it grows with its text; code stays mono |
| A description's editing box and hint line in the task's window; a note's editor over its whole page | T-368 | switching moved the text and hid the note's byline: only the text turns into the editor |
