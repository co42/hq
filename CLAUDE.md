# hq

Native macOS app (SwiftUI, AppKit where needed) that runs the user's day with Claude Code: a one-page cockpit with sessions and their faces, pull requests, and tasks with their Backlog as one outline; files, artifacts and everything else open in a sheet over it. Read `PLAN.md` before changing architecture and `DESIGN.md` before touching any view.

## Rules

- **Never look at, copy or model anything on claude-run**: code, UI, data model, words, skills. hq is built from the user's workflow and these docs only.
- hq never owns a terminal. Sessions run in Ghostty; hq focuses or opens them through AppleScript.
- Tasks and files are notes in the Obsidian vault and stay the source of truth. hq writes only the front matter keys it owns.
- The app is the only writer of its store. The CLI and hooks go through its socket.
- `hq hook` always exits 0, fast, and never opens the app.
- Claude Code's transcript format is internal: read it best effort, never depend on it.
- Views use DesignKit tokens and parts only: no raw colors, radii, durations, fonts or SF Symbol names outside `Sources/HQ/DesignKit/`.
- Work on a branch in this checkout, never in a git worktree. One HQ session works here at a time (2026-11-04): it shares one branch, one build folder, one dev copy and the test files in `/tmp`. Before changing anything, check `hq ls sessions --tag hq` and `git status`: if another session is working on HQ or the tree has changes that aren't yours, stop and tell the user.
- macOS 27 only (2026-11-05): use any macOS 27 API, no back compatibility. Keep it simple: no feature, setting or abstraction the plan doesn't ask for.

## Build and check

bama's template conventions (install the bama plugin: `/plugin marketplace add daveebbelaar/bama`, then `/plugin install bama@bama`):

- `./build.sh --dev [--debug]` installs the test copy (`~/Library/Developer/HQ/HQ.app`) that the tools below run: use it while working. `./build.sh` installs the user's `/Applications/HQ.app` and links `~/.local/bin/hq`: only when a version is ready, then tell the user to restart HQ. Never quit or restart their HQ yourself.
- A version that ships (merged into main, then `./build.sh`) gets its entry at the top of `RELEASE_NOTES.md`, in the same commit or right after: what changed for the user, by area, fixes last; the plugin's version when it changed. A release with no features is a point release (v7.1).
- `tools/snap.sh` writes light and dark PNGs of every screen to `/tmp/HQ-shots/` as `<page>-<width>-<mode>.png`, at 1504 and 756 pt wide. Look at every one you touched. It runs beside the user's HQ. `APP_SNAPSHOT_PAGES=a,b`, `APP_SNAPSHOT_MODES=dark`, `APP_KIT_GALLERY=1` (the parts gallery), `APP_DEBUG_TOOLBAR=1`.
- `tools/selftest.sh` (the model), `tools/uitest.sh` (real clicks and keys into a test copy; add a check for every interaction bug you fix), `swift test --scratch-path ~/Library/Developer/HQ/test-build`, `tools/grid-lint.sh`, `swift tools/check-layout.swift /tmp/HQ-shots/*-layout.json`. All run beside the user's HQ and in the background: a test copy has no Dock icon, keeps its window behind the user's and never takes the focus, so the user keeps working (snapshots then show an inactive window, and real table clicks SKIP). `HQ_FOREGROUND=1` runs them in front, only when the user is away or says yes: put every check you need in one run and ask first. A test copy's window opens on the user's second screen when one is connected, snapshots included, narrowed and shortened to fit it (snapshots there show a page's top 950 pt), and lets real clicks through to their windows (`ignoresMouseEvents`; the tests' events are posted in-process). Test runs never reach Ghostty: they record the calls in `ghosttyLog`.
- `tools/perf.sh` measures a test copy at rest on copies of the user's store and vault (CPU, memory, GPU memory; `PERF_BUSY=10` with tool calls coming in, `PERF_STATES=1` with state changes, `PERF_SAMPLE=<file>` for a call tree); `tools/launch.sh` traces a launch's memory and timing. Run them before and after a change that could cost CPU or memory. `tools/perf.sh --check` holds the seed to budgets (CPU at rest and with tool calls coming in, memory, its peak, GPU memory), exits 1 over any and adds a line to `~/Library/Developer/HQ/perf-history.tsv`: run it before every `./build.sh`. `tools/perf-lint.sh` flags per-frame redraws and drawing through SwiftUI's GPU renderer (DESIGN.md §12, Motion).
- A change under `plugin/` reaches Claude sessions only after a version bump in `plugin/.claude-plugin/plugin.json` and `tools/install-plugin.sh` (`build.sh` reminds you).
- Edit text with non-ASCII characters (›, ·, curly quotes) with the Edit tool, not perl or sed: a wide character makes perl re-encode the whole file.
- Snapshots, seed data and the self-test only run with `APP_STORE` in `/tmp`. Never touch the real store or the real vault in tests: `HQ_VAULT` points them at a copy.
- A UI change is done when the build is clean, the grid checks and the perf lint pass, and the snapshots pass DESIGN.md §12.

## Track this work in HQ

Working on HQ, use HQ for the work itself, so it gets used daily. Keep this session in the HQ folder, the work as tasks (`hq-tasks` skill), and plans and reports as files (`hq-files` skill). A session started before the hq plugin has neither its hooks nor its skills: read `plugin/skills/*/SKILL.md` and report the session by hand (`hq hook` with a SessionStart event), or resume it. Note what was awkward with the CLI or the skills, and fix it.

bama skills to use: `mac-design`, `design-system`, `layout-grid`, `ux-design`, `swift-swiftui`, `os-integrations`, `agent-cli`, `performance`, `build-and-verify`, `test-mac-app`, `app-icon`. Not its `clone`, `research`, `user-stories` or `improve-loop` flows: `PLAN.md` is the backlog.
