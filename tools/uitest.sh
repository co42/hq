#!/bin/zsh
# Drives a test copy of HQ with real key and mouse events (Sources/HQ/UITest.swift) on a fresh store and
# vault in /tmp. Exit code 0 when every check passed. Its window comes forward for about a minute:
# leave the keyboard and mouse alone meanwhile. It runs beside your own HQ.
set -u
store=/tmp/HQ-ui.store
vault=/tmp/HQ-ui-vault
log=/tmp/HQ-ui.log
rm -f $store $store-shm $store-wal $store.sock $log
rm -rf $vault && mkdir -p $vault/hq/tasks $vault/hq/files
# A foreground run is launched active: on macOS 26 an app can't take the focus once it runs.
flags=(-n -W)
[[ ${HQ_FOREGROUND:-0} == 1 ]] || flags=(-g $flags)
open $flags "${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}" --env APP_STORE=$store --env HQ_VAULT=$vault --env UITEST_VERBOSE=${UITEST_VERBOSE:-0} --env HQ_FOREGROUND=${HQ_FOREGROUND:-0} --env UITEST_ONLY=${UITEST_ONLY:-} --stdout $log --stderr $log --args --uitest -ApplePersistenceIgnoreState YES
cat $log
grep -q "^UITEST PASS" $log
