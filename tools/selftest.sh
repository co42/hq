#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
# It starts through LaunchServices (open -n), so it also runs while your own HQ is open.
set -u
# SELFTEST_RUN=name: its own store and log, to run beside another.
store=/tmp/HQ-${SELFTEST_RUN:-self}.store
log=/tmp/HQ-${SELFTEST_RUN:-self}.log
rm -f $store $store-shm $store-wal $store.sock $log
"${0:A:h}/watchdog.sh" $log $store 45 open -g -n -W "${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}" --env APP_STORE=$store --env HQ_FOREGROUND=${HQ_FOREGROUND:-0} --stdout $log --stderr $log --args --selftest
cat $log
grep -q "^SELFTEST PASS" $log
