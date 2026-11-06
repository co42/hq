#!/bin/zsh
# Snapshots of every page in light and dark, at 1504 and 756 pt wide, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=sessions,settings tools/snap.sh
# Runs the binary directly, so screencapture uses your terminal's Screen Recording permission.
# It runs beside your own HQ: a test run opens its window through Window › HQ.
set -u
app="${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}/Contents/MacOS/HQ"
store=/tmp/HQ-test.store
shots=/tmp/HQ-shots
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots
# Saved window state is ignored, never deleted: it belongs to your own HQ too.
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app -ApplePersistenceIgnoreState YES
