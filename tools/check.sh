#!/bin/zsh
# Every check, in one run, beside your own HQ: the test copy's build, unit tests, lints, self-test, UI test, snapshots
# and their layout. Each step's output goes to /tmp/HQ-check/<step>.log; the summary says which failed.
# Usage: tools/check.sh                 everything (a few minutes)
#        tools/check.sh --release       and the perf budgets (tools/perf.sh --check): before ./build.sh
#        CHECK_SKIP=uitest,snap tools/check.sh
# A failed build stops the run; any other failure is reported and the run goes on. Exit code 1 when any failed.
set -u
here=${0:A:h:h}
logs=/tmp/HQ-check
# Two runs share the test copy and /tmp: one at a time. A lock whose run is gone is stale. build.sh --dev waits too.
lock=/tmp/HQ-check.lock
if ! mkdir $lock 2>/dev/null; then
  owner=$(cat $lock/pid 2>/dev/null)
  if [[ -n $owner ]] && kill -0 $owner 2>/dev/null; then echo "another tools/check.sh runs (pid $owner)"; exit 1; fi
  rm -rf $lock && mkdir $lock
fi
print $$ >| $lock/pid
trap 'rm -rf $lock' EXIT
export HQ_CHECK_RUN=1
rm -rf $logs && mkdir -p $logs
skip=",${CHECK_SKIP:-},"
typeset -a summary
failed=0

step() {
  local name=$1; shift
  [[ $skip == *",$name,"* ]] && { summary+=("SKIP  $name"); return 0; }
  local start=$SECONDS
  if "$@" >| $logs/$name.log 2>&1; then
    summary+=("PASS  $name ($(( SECONDS - start ))s)")
  else
    summary+=("FAIL  $name ($(( SECONDS - start ))s): $logs/$name.log")
    failed=1
    return 1
  fi
}

cd $here
step build ./build.sh --dev || { print -l $summary; tail -20 $logs/build.log; exit 1 }
grep -q "warning:" $logs/build.log && summary+=("WARN  build has warnings: $logs/build.log")
step unit swift test --scratch-path ~/Library/Developer/HQ/test-build
step grid-lint tools/grid-lint.sh
step perf-lint tools/perf-lint.sh
step docs-lint tools/docs-lint.sh
step selftest tools/selftest.sh
step uitest tools/uitest.sh
step snap tools/snap.sh && step layout zsh -c 'swift tools/check-layout.swift /tmp/HQ-shots/*-layout.json'
[[ " $* " == *" --release "* ]] && step perf tools/perf.sh --check

print -l $summary
grep -h -E "^(UITEST|SELFTEST) " $logs/uitest.log $logs/selftest.log 2>/dev/null
(( failed )) && exit 1
exit 0
