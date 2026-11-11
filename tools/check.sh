#!/bin/zsh
# Every check, in one run, beside your own HQ: the test copy's build, unit tests, lints, self-test, UI test, snapshots
# and their layout, side by side where they can be. Each step's output goes to /tmp/HQ-check/<step>.log.
# Usage: tools/check.sh                 everything, on the release build HQ ships (under 2 minutes)
#        tools/check.sh --fast          the same on a debug build: seconds to build after an edit, while working
#        tools/check.sh --release       everything, the perf budgets, then the stamp ./build.sh asks for
#        CHECK_SKIP=uitest,snap tools/check.sh
#        UITEST_ONLY=outlineKeys APP_SNAPSHOT_PAGES=cockpit tools/check.sh --fast
# A failed build stops the run; any other failure is reported and the run goes on. Exit code 1 when any failed.
set -u
# Background jobs at full priority: zsh nices them, and macOS then keeps them on the efficiency cores.
setopt no_bg_nice
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
touch $logs/started
skip=",${CHECK_SKIP:-},"
mode=default
[[ " $* " == *" --fast "* ]] && mode=fast
[[ " $* " == *" --release "* ]] && mode=release
typeset -a order
started=$SECONDS

# A step runs in the background; its verdict lands in <step>.result. `collect` waits for them, in the order started.
step() {
  local name=$1; shift
  order+=($name)
  if [[ $skip == *",$name,"* ]]; then print "SKIP  $name" >| $logs/$name.result; return 0; fi
  {
    local start=$SECONDS
    if "$@" >| $logs/$name.log 2>&1; then
      print "PASS  $name ($(( SECONDS - start ))s)" >| $logs/$name.result
    else
      print "FAIL  $name ($(( SECONDS - start ))s): $logs/$name.log" >| $logs/$name.result
    fi
  } &
}
collect() { wait }
verdict() { [[ -f $logs/$1.result ]] && grep -q "^PASS\|^SKIP" $logs/$1.result }

cd $here
build=(./build.sh --dev)
[[ $mode == fast ]] && build+=(--debug)
step build $build
step unit swift test --package-path HQKit --scratch-path ~/Library/Developer/HQ/kit-build
step grid-lint tools/grid-lint.sh
step perf-lint tools/perf-lint.sh
step code-lint tools/code-lint.sh
step docs-lint tools/docs-lint.sh
collect
if ! verdict build; then
  cat $logs/build.result; tail -20 $logs/build.log; exit 1
fi
step selftest tools/selftest.sh
step uitest tools/uitest.sh
step snap tools/snap.sh
collect
verdict snap && step layout zsh -c 'swift tools/check-layout.swift /tmp/HQ-shots/*-layout.json'
# The perf budgets measure a test copy at rest: alone.
collect
[[ $mode == release ]] && { step perf tools/perf.sh --check; collect }

# A run-time repair is a defect found at run time: each one the app logged, from any test copy.
repairs=$(grep -h "^  log outline.log: " $logs/uitest.log $logs/snap.log $logs/selftest.log 2>/dev/null | sed 's/^  log outline.log: //' | sort | uniq -c | sort -rn)

failed=0
for name in $order; do
  cat $logs/$name.result
  grep -q "^FAIL" $logs/$name.result && failed=1
done
grep -q "warning:" $logs/build.log && print "WARN  build has warnings: $logs/build.log"
[[ -n $repairs ]] && { print "WARN  the outline repaired itself $(print -r -- $repairs | awk '{n+=$1} END {print n}') times (outline.log):"; print -r -- $repairs | head -8 | sed 's/^/        /' }
for log in uitest selftest snap; do grep -h -E "^(UITEST|SELFTEST|SNAPSHOT) (PASS|FAIL|[0-9]+ images)" $logs/$log.log 2>/dev/null | tail -1; done
# Every failed check by name, and what a test copy that crashed left.
grep -h -E "^(FAIL|SNAPSHOT FAIL|UITEST .* ended without)" $logs/uitest.log $logs/selftest.log $logs/snap.log 2>/dev/null | head -30 | sed 's/^/  /'
tools/crash.sh $logs/started
# The design skills CLAUDE.md and DESIGN.md §17 rely on, installed for this checkout (they once stayed with an old path).
jq -e --arg path "$here" '(.plugins["bama@bama"] // []) | any(.projectPath == $path or .scope == "user")' ~/.claude/plugins/installed_plugins.json >/dev/null 2>&1 \
  || print "WARN  bama's skills aren't installed for $here: claude plugin install bama@bama --scope local"
# Checks don't vanish unseen: a full run lists those the last green full run had and this one hasn't.
names=$HOME/Library/Developer/HQ/check-names
if [[ -z ${UITEST_ONLY:-}${APP_SNAPSHOT_PAGES:-} && $skip == ",," ]]; then
  grep -h -E "^(PASS|FAIL|SKIP) " $logs/uitest.log $logs/selftest.log 2>/dev/null | sed -E 's/^(PASS|FAIL|SKIP) //; s/: .*//; s/ \([0-9]+\)$//' | sort -u >| $logs/names
  if [[ -f $names ]]; then
    gone=$(comm -23 $names $logs/names)
    [[ -n $gone ]] && { print "WARN  $(print -r -- $gone | wc -l | tr -d ' ') checks of the last green run are gone:"; print -r -- $gone | head -10 | sed 's/^/        /' }
  fi
  (( failed )) || cp $logs/names $names
fi
print "TOTAL $(( SECONDS - started ))s ($mode)"

if (( ! failed )) && [[ $mode == release ]]; then
  tools/stamp.sh write
  print "STAMP the release gate passed: ./build.sh may install this tree"
fi
exit $failed
