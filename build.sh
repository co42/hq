#!/bin/zsh
# Builds HQ and installs it to /Applications/HQ.app, where Spotlight finds it.
# Build products live in ~/Library/Developer/HQ, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
#        ./build.sh --dev      install the test copy only (tools/*.sh use it); combine with --debug
#        ./build.sh --force "why"   install a tree tools/check.sh --release hasn't passed, and say why
set -euo pipefail
here=${0:A:h}
name="HQ"
# HQ_BUILD_DIR and HQ_DEV_APP: a build folder and a test copy of your own, to build beside another run.
scratch="${HQ_BUILD_DIR:-$HOME/Library/Developer/$name/build}"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

# A running tools/check.sh tests the test copy: replacing it mid-run mixes two builds in one result.
if [[ " $* " == *" --dev "* && -z "${HQ_CHECK_RUN:-}" && -z "${HQ_DEV_APP:-}" && -d /tmp/HQ-check.lock ]] && kill -0 "$(cat /tmp/HQ-check.lock/pid 2>/dev/null)" 2>/dev/null; then
  echo "build refused: tools/check.sh is testing the test copy; wait for it, or stop it"
  exit 1
fi
# Your HQ gets only a tree the release gate passed (its stamp); --force "why" installs another, out loud.
if [[ " $* " != *" --dev "* ]]; then
  if [[ " $* " == *" --force "* ]]; then
    why=${@[$(( ${@[(i)--force]} + 1 ))]:-}
    [[ -n "$why" && "$why" != --* ]] || { echo "--force needs a reason: ./build.sh --force \"why\""; exit 1; }
    echo "installing without the release gate: $why"
  elif ! "$here/tools/stamp.sh" verify; then
    echo "install refused: tools/check.sh --release hasn't passed for this tree; or ./build.sh --force \"why\""
    exit 1
  fi
fi
build=(swift build -c $config --package-path "$here")
# The release test copy compiles file by file, in parallel and incrementally: 35 s cold against 110 s for one whole module,
# which keeps tools/check.sh under its 2 minutes after a large change. Your HQ keeps the whole-module build. Only SwiftPM's
# native build system takes the flag, and it warns it's deprecated: that one warning is left out.
if [[ " $* " == *" --dev "* && $config == release ]]; then
  scratch="${HQ_BUILD_DIR:-$HOME/Library/Developer/$name/gate-build}"
  build+=(--build-system native -Xswiftc -no-whole-module-optimization)
fi
build+=(--scratch-path "$scratch")
$build 2>&1 | grep -E "error|warning|Build complete" | grep -v -e "^\[" -e "--build-system native. has been deprecated" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile: a second build shows its errors. With none,
# the newer files only had their dates bumped (a checkout, a merge) and SwiftPM had nothing to relink.
stale=$(find "$here/Sources" "$here/HQKit/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  errors=$($build 2>&1 | sed $'s/\e\\[[0-9;]*m//g' | grep -E "error:" | head -20 || true)
  if [[ -n "$errors" ]]; then
    echo "build failed: binary is older than $stale"
    print -r -- "$errors"
    exit 1
  fi
  touch "$bin"
fi

# --dev installs a copy for tests (~/Library/Developer/HQ/HQ.app), leaving the user's /Applications/HQ.app and the hq link alone.
dev=0
[[ " $* " == *" --dev "* ]] && dev=1
if (( dev )); then app="${HQ_DEV_APP:-$HOME/Library/Developer/$name/$name.app}"; else app="/Applications/$name.app"; fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
# The version: RELEASE_NOTES.md's top entry (`## v17 · 2026-11-20 · …` is 17). The test copy says -dev; an install
# says -unreleased unless that entry is dated, the tree is committed and the gate wasn't forced.
top=$(grep -m1 '^## v' "$here/RELEASE_NOTES.md" || true)
version=${${top#\#\# v}%% *}
[[ -n "$version" ]] || version=0
if (( dev )); then
  version+="-dev"
elif [[ " $* " == *" --force "* || ! "$top" =~ ' · [0-9]{4}-[0-9]{2}-[0-9]{2}' ]] \
  || [[ -n "$(git -C "$here" status --porcelain)" ]]; then
  version+="-unreleased"
fi
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__VERSION__/$version/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon and the accent: Icon/ -> Resources/Assets.car + AppIcon.icns, rebuilt when Icon/ changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh" || echo "warning: the icon did not compile (tools/make_icon.sh); installing without it"
  fi
  [[ -f "$car" ]] && cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
# mermaid.js (Vendor/mermaid, MIT) draws diagrams in markdown.
cp -R "$here/Vendor/mermaid" "$app/Contents/Resources/Mermaid"
# The Claude Code plugin and its installer, so Setup › Install works from the app alone.
mkdir -p "$app/Contents/Resources/Plugin"
cp -R "$here/.claude-plugin" "$here/plugin" "$app/Contents/Resources/Plugin/"
cp "$here/tools/install-plugin.sh" "$app/Contents/Resources/Plugin/install.sh"
# Claude Code runs the plugin from a copy per version: a change here reaches sessions after a version bump and an update.
installed=$(jq -r '.plugins["hq@hq"][0].version // empty' ~/.claude/plugins/installed_plugins.json 2>/dev/null)
bundled=$(jq -r .version "$here/plugin/.claude-plugin/plugin.json")
if [[ -n $installed && $installed != "$bundled" ]]; then
  echo "hq plugin $bundled is bundled but $installed is installed: run tools/install-plugin.sh"
elif [[ -n $installed ]] && ! diff -rq "$here/plugin" ~/.claude/plugins/cache/hq/hq/$installed >/dev/null 2>&1; then
  echo "plugin/ changed since $installed was installed: bump its version in plugin/.claude-plugin/plugin.json, then run tools/install-plugin.sh"
fi
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"
(( dev )) && exit 0
# A new bundle at the same path: Spotlight reindexes it.
mdimport "$app" >/dev/null 2>&1 || true
# The CLI: the app binary under a short name on PATH (bama agent-cli skill).
mkdir -p "$HOME/.local/bin"
ln -sf "$app/Contents/MacOS/$name" "$HOME/.local/bin/hq"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
