# hq

Native macOS app (SwiftUI, AppKit where needed) that runs the user's day with Claude Code: a one-page cockpit with sessions and their faces, pull requests, and tasks with their Backlog as one outline; files, artifacts, the notification center and everything else open in a sheet over it. Read `PLAN.md` before changing architecture, `DESIGN.md` before touching any view, and `ITERATION.md` when an iteration starts and before each release.

## Rules

- **Never look at, copy or model anything on claude-run**: code, UI, data model, words, skills. hq is built from the user's workflow and these docs only.
- hq never owns a terminal. Sessions run in Ghostty; hq focuses or opens them through AppleScript.
- Tasks and files are notes in the Obsidian vault and stay the source of truth. hq writes only the front matter keys it owns.
- The app is the only writer of its store. The CLI and hooks go through its socket.
- `hq hook` always exits 0, fast, and never opens the app.
- Claude Code's transcript format is internal: read it best effort, never depend on it.
- Views use DesignKit tokens and parts only: no raw colors, radii, durations, fonts or SF Symbol names outside `Sources/HQ/DesignKit/`.
- Work on a branch in this checkout, never in a git worktree. One HQ session works here at a time (2026-11-04): it shares one branch, one build folder, one dev copy and the test files in `/tmp`. Before changing anything, check `hq ls sessions --here` (the sessions in this repository) and `git status`: if another session is working on HQ or the tree has changes that aren't yours, stop and tell the user.
- macOS 27 only (2026-11-05): use any macOS 27 API, no back compatibility. Keep it simple: no feature, setting or abstraction the plan doesn't ask for.
- The repo is public: no employer, colleague or other personal detail in code, docs or commits.

## Working with the user

- A question gets an answer, not a change ("answer no fix"). Act once they say so.
- Do what was asked, no more: fix the data when they ask to fix data, not the app; add no task they didn't ask for (a bug you find goes in your notification).
- A question to them says what it means for them, in their words: never a type, a flag or an internal name they'd have to look up. Ask every open decision at once, each with your recommendation.
- They add subtasks and edit the task while you work: `hq task show` between pieces and take the new ones in.
- Time-box: before a hunt that takes more than a few builds (a perf bisect, profiling rounds), say what you found, what's left and whether it's worth it, and let them choose (T-260).
- They work beside your runs: tests stay in the background; a front run needs their OK, with every check in one run.
- Their setup, which the test copy doesn't have: Reduce Motion on (HQ ignores it), a view zoom of about 1.15, about 1200 pt of content on their half screen, a second screen for test windows. They use the UI; the `hq` command is for sessions.

## Building a UI change

Most of what the user sent back in v1–v9 was one of these. Settle them before writing the view:

1. **Look first.** How two or three of the best native apps do the same thing (Apple's own, then Things, Linear, Raycast…), and what DESIGN.md already says. A new surface gets a plan (an HQ file) and, when it's a new screen or a new way to act, a mockup artifact the user reviews before the build.
2. **Siblings match.** List the parts that do the same job elsewhere: task, PR, file, artifact and notification rows; link chips; faces on cards, rows and chips; header controls; pickers; empty states. Use their DesignKit part and change them together, never one kind alone (DESIGN.md §1.9).
3. **Interactions follow the table** in DESIGN.md §18: what a click, double-click, right-click and key do on each kind of element. Change the table first, then the code.
4. **Less on screen.** At rest a row shows what tells its story; actions show under the pointer or when selected. Read DESIGN.md §19 (what was removed and why) before adding a control. A feature whose use isn't clear is a question for the user, not a build: they'd rather remove it.
5. **Every state works.** Nothing dimmed and inert; every item has its actions in every state, and its whole text readable somewhere (selected, tooltip, modal).
6. **A control that already moved twice**: show two or three options before moving it again (the description toggle moved seven times).
7. **Check it as the user sees it**: the snapshots at 1504 and 756 pt, light and dark; rows with their optional parts missing and their longest values; real clicks for an interaction (ITERATION.md, Release).

## Fixing a bug

- Fix the class, not the instance: find every place with the same pattern (all faces, all rows, all AppKit views hosted the same way, all buttons) and list them in the task's Done when.
- Add a check that fails on the code before the fix: a UI check for an interaction, the self-test for the model, `swift test` for HQKit.
- Not reproduced: say so. Ship a log line on the path and an invariant check that would catch it, and keep the task open until it's seen fixed.
- A task is finished when it works as the user will use it: a real click where the bug was a click, their zoom where it was drawing.

## Docs move with the code

In the same commit as the change: DESIGN.md (how it looks and acts; a decision with its date), PLAN.md (model, architecture, the CLI), README.md (what a user sees), the skills and `hq help` (how sessions use it), the menus and Settings › Keys for a shortcut. A removed feature adds its names to `tools/docs-lint.sh`'s retired list and a line to DESIGN.md §19. `tools/docs-lint.sh` checks commands and retired names; grep the docs for the rest.

## Build and check

bama's template conventions. Its plugin is installed for this checkout (`claude plugin install bama@bama --scope local`; `check.sh` warns when it isn't); a session started without its skills reads them in `~/.claude/plugins/cache/bama/bama/<version>/skills/`:

- **`tools/check.sh` is the gate**: the test copy's release build, HQKit's tests, the grid, perf and docs lints, the self-test, the UI test, snapshots and their layout, side by side, with a summary of what passed and every failed check by name. 2 minutes at most, build included: a slower run fails (`FAIL time`), and its step times say which grew; `--fast` builds debug (seconds after an edit) while you work; `--release` adds the perf budgets, beside the tests, and writes the stamp `./build.sh` needs to install. Run it before saying anything works, and read its summary: never judge a check through `| tail` or `| grep`, which hide its exit code. A line the outline writes to outline.log fails it: a defect found at run time (a check that makes one on purpose names it in `AppLog.expected`). Its WARN lines count: checks gone since the last green run, a crash report. While it runs, `build.sh --dev` refuses: a new test copy mid-run mixes two builds in one result.
- `./build.sh --dev [--debug]` installs the test copy (`~/Library/Developer/HQ/HQ.app`) that the tools run. `./build.sh` installs the user's `/Applications/HQ.app` and links `~/.local/bin/hq`: only for a release (ITERATION.md), then tell the user to restart HQ. Never quit or restart their HQ yourself. Trust `build.sh` over SourceKit's diagnostics, which go stale for this package.
- `tools/snap.sh` writes light and dark PNGs of every screen to `/tmp/HQ-shots/` as `<page>-<width>-<mode>.png`, at 1504 and 756 pt wide. Look at every one you touched. `APP_SNAPSHOT_PAGES=a,b`, `APP_SNAPSHOT_MODES=dark`, `APP_KIT_GALLERY=1` (the parts gallery), `APP_DEBUG_TOOLBAR=1`. Glass and toolbar color are judged only on foreground captures.
- `tools/selftest.sh` (the model), `tools/uitest.sh` (real clicks and keys into test copies: the groups that time the main thread alone, the rest in five shards; `UITEST_ONLY=group` runs one copy), `swift test --package-path HQKit` (HQKit is its own package: a second, no app build), `tools/grid-lint.sh`, `tools/perf-lint.sh`, `tools/docs-lint.sh`, `swift tools/check-layout.swift /tmp/HQ-shots/*-layout.json`, `tools/crash.sh` (the newest crash report's stack).
  - All run beside the user's HQ and in the background: a test copy has no Dock icon, keeps its window behind the user's and never takes the focus. Snapshots then show an inactive window, and real table clicks SKIP. `HQ_FOREGROUND=1` runs them in front, only when the user is away or says yes, and refuses a locked screen.
  - A test copy has its own preferences, emptied at launch (`Prefs`), its own store, vault and log, and no motion (`Motion.still`; the `storyFlow` group keeps it). A watchdog stops one that stays silent 45 s and writes its main thread's stack into its log.
  - A test copy's window opens on the user's second screen when one is connected, narrowed and shortened to fit it (snapshots there show a page's top 950 pt), and lets real clicks through to their windows. Test runs never reach Ghostty: they record the calls in `ghosttyLog`.
  - UI checks: each group starts on the same seed (`scenario`), adds what it needs and passes alone or in any shard; `check` waits until its condition holds, `settle()` until the windows hold still (before a check that something did *not* happen), a click until its anchor shows (a missing one fails); `wait` only for what is measured in time; look a row's cell up again after every action; a check's condition looks up what it judges (a value read before the check never changes while it polls); a flaky check is fixed at its cause, never retried around; a perf check measures a median with margin.
- `tools/perf.sh` measures a test copy at rest on copies of the user's store and vault (`PERF_BUSY=10`, `PERF_STATES=1`, `PERF_SAMPLE=<file>`); `tools/launch.sh` traces a launch's memory and timing. `tools/perf.sh --check` holds the seed to budgets: part of `check.sh --release`.
- A change under `plugin/` reaches Claude sessions only after a version bump in `plugin/.claude-plugin/plugin.json` and `tools/install-plugin.sh` (`build.sh` reminds you); sessions already running keep the old skills.
- Snapshots, seed data and the self-test only run with `APP_STORE` in `/tmp`. Never touch the real store or the real vault in tests: `HQ_VAULT` points them at a copy.

## Shell traps seen here

- No heredocs: write the file with Write or `printf`; `git commit -F <file>`.
- zsh: noclobber (`>|` to overwrite), no word splitting of `$var` (use arrays), quote globs.
- Text with non-ASCII characters (›, ·, curly quotes) is edited with the Edit tool; perl and sed only with ASCII patterns, then `git diff --stat`: a wide character makes perl re-encode the whole file.
- perl `s|…|…|` with `\|` in the pattern: the escaped delimiter becomes alternation and the text lands at the top of the file. Use `s{…}{…}` or `s/…/…/`.
- No command that waits on stdin with nothing to read (`cat > file`, `python3 -`).
- `sips --cropOffset` crops from the center.

## Track this work in HQ

Working on HQ, use HQ for the work itself, so it gets used daily. Keep this session in the HQ folder, the work as tasks (`hq` skill), and plans and reports as files (`hq-files` skill). Note what was awkward with the CLI or the skills, and fix it.

bama skills to use: `mac-design`, `design-system`, `layout-grid`, `ux-design`, `swift-swiftui`, `os-integrations`, `agent-cli`, `performance`, `build-and-verify`, `test-mac-app`, `app-icon`. Not its `clone`, `research`, `user-stories` or `improve-loop` flows: the work lives in HQ's tasks, iteration by iteration.
