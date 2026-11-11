# Iterations

How a version of HQ goes from the user's list to their `/Applications`. Read it when an iteration starts and again before each release: every step here is one the user had to ask for at least twice (T-324).

## The story

- An iteration is a story task, "HQ - Iteration vN" (project HQ), and its subtasks are the work. The user adds subtasks while you work, terse and in their words: `hq task show` the story between tasks and take the new ones in.
- Only the user adds to an iteration, or says yes to a proposal. A bug you find on the way goes in your notification, or becomes a task in Tasks when they asked you to note it.
- Order: what changes how the work is done (a doc, a check) first, then what blocks the user's day (a crash, something unusable), then the rest grouped by area, so each group ships as a batch they can try.

## Start

1. `hq ls sessions --here` and `git status`: no other session in this repository, a clean tree. Otherwise stop and tell the user.
2. A branch `vN` from `main`, in this checkout.
3. The story to doing; read every subtask; set each one's project.
4. `tools/check.sh` once before changing anything: a check that already fails isn't yours, but say so.
5. Every subtask that adds a surface or changes how something looks or acts gets its questions answered before code (CLAUDE.md, Building a UI change). Ask the user every open question at once, each with your recommendation, in a sentence they can answer without opening the code.

## Each task

- Doing when you start it, before reading its code; each subtask too.
- Its Done when lists every place the change applies (all the rows, all the faces, all the buttons), not only the one the user named.
- Finished means: its check fails on the code before and passes after; the docs say what the app now does (same commit); `tools/check.sh` passes. The task stays doing: the user moves it to done once they've tried it.

## Release (a batch the user can try)

1. `tools/check.sh --release`: build, unit tests, lints (grid, perf, docs), self-test, UI test, snapshots and layout, perf budgets. Read its summary, not the tools' output through a pipe. Green, it writes the stamp `./build.sh` checks; a red check blocks the release (v13 shipped on one), and `./build.sh --force "why"` is the user's call, never yours. Its WARN lines are bugs too: a run-time repair, a check gone, a crash report.
2. The snapshots of every page you touched, 1504 and 756 pt, light and dark (DESIGN.md §17).
3. Real clicks: a background UI run skips them, and every release so far shipped with a dozen skipped. One front run per release (`HQ_FOREGROUND=1 tools/uitest.sh`), with the user's OK and the screen unlocked, every check you need in it, 0 skipped.
4. The `hq` commands and skills: true to the app, nothing missing, nothing said twice, short. `hq help` matches. A change under `plugin/`: version bump, `tools/install-plugin.sh`.
5. The docs: DESIGN.md, PLAN.md, README.md, the skills, and the HQ section of the user's `~/.claude/CLAUDE.md` when how sessions work changed. A removed feature's names go to `tools/docs-lint.sh`'s retired list and DESIGN.md §19.
6. `RELEASE_NOTES.md`: a new entry on top, by area, what changed for the user, fixes last, the plugin's version when it changed. A release with no features is a point release (v9.1).
7. Ask, then commit (conventional, no Claude attribution), merge into `main`, `./build.sh`. Push only when the user says so.
8. The user's real logs since the last release: `~/Library/Logs/HQ/outline.log` and `vault.log`, and the crash reports (`tools/crash.sh`; all of them: `command ls -t ~/Library/Logs/DiagnosticReports/HQ-*.ips`). A repair in real use is a bug the tests missed: a task for it. A crash is read from its stack before any workaround. And what sessions tried with `hq` and didn't get: `tools/hq-usage.sh --since <the last release's date>`.
9. `hq notify`: what changed, what to try first, "restart HQ", and "new sessions get plugin 0.x" when it changed. Never quit or restart their HQ yourself.
10. A message to share, when the user asks for one: short, easy to scan, the most important change first, the release notes linked. The user sends it.

## Close

When the user says the iteration is over (they did at v7 and v9):

1. What isn't done moves under the next iteration's story: `hq task edit T-n --parent T-m`.
2. The rest of its subtasks to done: `hq task move T-n done`.
3. The story to the Backlog, done: `hq task move T-n done --list backlog`.
