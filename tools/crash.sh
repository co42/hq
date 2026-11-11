#!/bin/zsh
# The newest HQ crash report, if it came after a given moment: its exception and the crashed thread's top frames.
# Usage: tools/crash.sh                 the newest report
#        tools/crash.sh /tmp/marker     only one newer than that file (a test run touches it as it starts)
# Read the stack before working around a crash (CLAUDE.md, Fixing a bug).
set -u
reports=(~/Library/Logs/DiagnosticReports/HQ-*.ips(N.om))
(( ${#reports} )) || exit 0
newest=${reports[1]}
[[ $# -ge 1 && -e $1 && ! $newest -nt $1 ]] && exit 0
print "CRASH $newest"
tail -n +2 $newest | jq -r '"  \(.exception.type) \(.exception.signal // "") \(.termination.indicator // "")",
  (.threads[] | select(.triggered) | .frames[0:14][] | "    \(.symbol // "?")")'
