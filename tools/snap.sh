#!/bin/zsh
# Snapshots of every page in light and dark, at 1504 and 756 pt wide, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages, the four passes side by side
#        APP_SNAPSHOT_PAGES=sessions,settings tools/snap.sh
#        SNAP_PASSES=1 tools/snap.sh   one process for all, one pass after another
# Runs the binary directly, so screencapture uses your terminal's Screen Recording permission.
# It runs beside your own HQ: a test run opens its window through Window › HQ. Exit code 1 when a page failed.
set -u
# Background jobs at full priority: zsh nices them, and macOS then keeps them on the efficiency cores.
setopt no_bg_nice
app="${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}/Contents/MacOS/HQ"
# SNAP_DIR: another folder for the images, and stores named after it, to run beside another run.
shots=${SNAP_DIR:-/tmp/HQ-shots}
tools=${0:A:h}
rm -rf $shots && mkdir -p $shots

# One pass: its own store (seed data only fills an empty store), its widths and modes.
pass() {
  local name=$1 widths=$2 modes=$3 settings=$4
  local store=$shots-$name.store
  rm -f $store $store-shm $store-wal
  # Saved window state is ignored, never deleted: it belongs to your own HQ too.
  APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots APP_SNAPSHOT_WIDTHS=$widths APP_SNAPSHOT_MODES=$modes APP_SNAPSHOT_SETTINGS=$settings \
    $tools/watchdog.sh $shots-$name.log $store 45 $app -ApplePersistenceIgnoreState YES >| $shots-$name.log 2>&1
}

typeset -a pids names
if [[ ${SNAP_PASSES:-4} == 1 || -n ${APP_KIT_GALLERY:-} ]]; then
  pass all ${APP_SNAPSHOT_WIDTHS:-1504,756} ${APP_SNAPSHOT_MODES:-light,dark} 1 & pids+=($!); names+=(all)
else
  for width in 1504 756; do
    for mode in light dark; do
      [[ -n ${APP_SNAPSHOT_MODES:-} && ,$APP_SNAPSHOT_MODES, != *,$mode,* ]] && continue
      [[ -n ${APP_SNAPSHOT_WIDTHS:-} && ,$APP_SNAPSHOT_WIDTHS, != *,$width,* ]] && continue
      # Settings once, with the first pass.
      pass $width-$mode $width $mode $(( ${#pids} == 0 )) & pids+=($!); names+=($width-$mode)
    done
  done
fi
failed=0
for i in {1..${#pids}}; do
  wait ${pids[$i]} || failed=1
  cat $shots-${names[$i]}.log
  grep -q "^SNAPSHOT done" $shots-${names[$i]}.log || { echo "SNAPSHOT FAIL pass ${names[$i]} ended without its last line"; failed=1; }
done
echo "SNAPSHOT $(command ls $shots/*.png 2>/dev/null | wc -l | tr -d ' ') images in $shots"
exit $failed
