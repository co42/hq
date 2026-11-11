#!/bin/zsh
# Drives test copies of HQ with real key and mouse events (Sources/HQ/UITest.swift), each on a fresh store and vault in
# /tmp. Exit code 0 when every check passed. It runs beside your own HQ, behind your windows.
# Usage: tools/uitest.sh                        every group: the two that time the main thread alone, then the rest in
#                                               four test copies side by side
#        UITEST_ONLY=outlineKeys,modal tools/uitest.sh    those groups, in one test copy
#        UITEST_SHARDS=1 tools/uitest.sh        every group in one test copy, one after the other
#        HQ_FOREGROUND=1 tools/uitest.sh        in front, for the real clicks: one test copy (only one app can be in front)
set -u
# Background jobs at full priority: zsh nices them, and macOS then keeps them on the efficiency cores.
setopt no_bg_nice
app=${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}
tools=${0:A:h}
# A foreground run is launched active: on macOS 26 an app can't take the focus once it runs.
# Behind a locked screen its real clicks reach nothing, so it would only report them as failed.
if [[ ${HQ_FOREGROUND:-0} == 1 ]] && ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked | grep -q '<true/>'; then
  echo "UITEST FAIL the screen is locked: a front run needs it unlocked, and the user away from the keyboard"
  exit 1
fi

# One test copy: its store, vault and log (/tmp/HQ-<run>.*), the groups it runs (or all but some), a slowdown for its waits.
one() {
  local run=$1 only=$2 except=$3 slowdown=$4
  local store=/tmp/HQ-$run.store vault=/tmp/HQ-$run-vault log=/tmp/HQ-$run.log
  rm -f $store $store-shm $store-wal $store.sock $log
  rm -rf $vault && mkdir -p $vault/hq/tasks $vault/hq/files
  local flags=(-n -W)
  [[ ${HQ_FOREGROUND:-0} == 1 ]] || flags=(-g $flags)
  $tools/watchdog.sh $log $store 45 open $flags $app --env APP_STORE=$store --env HQ_VAULT=$vault --env UITEST_VERBOSE=${UITEST_VERBOSE:-0} \
    --env HQ_FOREGROUND=${HQ_FOREGROUND:-0} --env UITEST_ONLY=$only --env UITEST_EXCEPT=$except --env UITEST_SLOWDOWN=$slowdown \
    --env UITEST_TIMES=${UITEST_TIMES:-0} --env HQ_MOTION=${HQ_MOTION:-0} --stdout $log --stderr $log --args --uitest -ApplePersistenceIgnoreState YES
}

if [[ -n ${UITEST_ONLY:-} || ${UITEST_SHARDS:-4} == 1 || ${HQ_FOREGROUND:-0} == 1 ]]; then
  # UITEST_RUN=name: its own store, vault and log (/tmp/HQ-<name>.*), to run beside another.
  run=${UITEST_RUN:-ui}
  one $run "${UITEST_ONLY:-}" "" 1
  cat /tmp/HQ-$run.log
  grep -q "^UITEST PASS" /tmp/HQ-$run.log
  exit $?
fi

# The groups that time the main thread run alone; the others in shards of about the same length (GROUP lines give
# each group's time). The last shard takes every group the others don't name, new ones included.
alone=idle,performance
shards=(
  outlineKeys,grid,modal,menuBar,singleSessionFace,prFaces
  storyFlow,typingKeepsRows,pageSelection,lateChecks
  slackLinks,rowControls,foldedParentOpens,outlineDrops
)
one ui-0 $alone "" 1
typeset -a runs=(ui-0) pids
for i in {1..${#shards}}; do
  one ui-$i ${shards[$i]} "" 1.5 & pids+=($!); runs+=(ui-$i)
done
one ui-$(( ${#shards} + 1 )) "" ${(j:,:)shards},$alone 1.5 & pids+=($!); runs+=(ui-$(( ${#shards} + 1 )))
wait $pids

checks=0 failures=0 skips=0 missing=0
for run in $runs; do
  log=/tmp/HQ-$run.log
  print "== $run"
  cat $log
  verdict=$(grep -E "^UITEST (PASS|FAIL) " $log | tail -1)
  if [[ -z $verdict ]]; then
    missing=1
    print "UITEST $run ended without its verdict"
    continue
  fi
  # "UITEST PASS 120 checks, 3 skipped" or "UITEST FAIL 2 of 120 checks, 3 skipped"
  words=(${=verdict})
  if [[ ${words[2]} == PASS ]]; then checks=$(( checks + words[3] )); else failures=$(( failures + words[3] )); checks=$(( checks + words[5] )); fi
  [[ $verdict =~ '([0-9]+) skipped' ]] && skips=$(( skips + match[1] ))
done
skipped=""
(( skips )) && skipped=", $skips skipped"
if (( failures || missing )); then
  print "UITEST FAIL $failures of $checks checks$skipped$( (( missing )) && print -n ', a test copy ended without its verdict')"
  exit 1
fi
print "UITEST PASS $checks checks$skipped"
