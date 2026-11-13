#!/bin/zsh
# Runs a test copy and stops it when its log stays silent too long: a hung run would hold tools/check.sh and its lock
# for ever. It writes where the run was and the main thread's stack into the log, then kills the test copy.
# Usage: tools/watchdog.sh <log> <store> <seconds> command…   (the test copy is the process that has <store> open)
set -u
# Background jobs at full priority: zsh nices them, and macOS then keeps them on the efficiency cores.
setopt no_bg_nice
log=$1 store=$2 limit=$3
shift 3
"$@" &
runner=$!
while kill -0 $runner 2>/dev/null; do
  sleep 1
  [[ -f $log ]] || continue
  (( $(date +%s) - $(stat -f %m $log) < limit )) && continue
  app=$(lsof -t $store 2>/dev/null | head -1)
  {
    print "WATCHDOG silent for ${limit}s after: $(grep -E '^(GROUP|PASS|FAIL|SNAPSHOT)' $log | tail -1)"
    if [[ -n $app ]]; then
      sample $app 2 -file $log.sample >/dev/null 2>&1
      print "the main thread:"
      awk '/Main Thread|com.apple.main-thread/ {on=1} on {print; if (++n > 40) exit}' $log.sample
      kill -9 $app
    fi
  } >> $log
  break
done
wait $runner
