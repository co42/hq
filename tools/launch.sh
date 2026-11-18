#!/bin/zsh
# A test copy's launch on copies of your store and vault (or the seed, PERF_SEED=1): its memory every half second,
# and when its window first showed the page. It runs beside your own HQ.
# Usage: tools/launch.sh [seconds, 15]
set -u
zmodload zsh/datetime
seconds=${1:-15}
app="${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}"
store=/tmp/HQ-perf.store
vault=/tmp/HQ-perf-vault
log=/tmp/HQ-perf.log
notes="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes"
rm -f $store $store-shm $store-wal $store.sock $log
rm -rf $vault && mkdir -p $vault
env=(--env APP_STORE=$store --env HQ_VAULT=$vault --env HQ_GITHUB=fixtures --env HQ_LAUNCH_LOG=1)
if [[ ${PERF_SEED:-0} == 1 ]]; then
  mkdir -p $vault/hq/tasks $vault/hq/files
  env+=(--env APP_SEED=1)
else
  sqlite3 "$HOME/Library/Application Support/HQ/HQ.store" ".backup $store"
  cp -R "$notes/hq" $vault/
fi
before=(${(f)"$(pgrep -f "$app/Contents/MacOS/HQ")"})
start=$EPOCHREALTIME
open -g -n "$app" $env --stdout $log --stderr $log --args -ApplePersistenceIgnoreState YES
pid=""
while [[ -z $pid ]]; do
  for p in ${(f)"$(pgrep -f "$app/Contents/MacOS/HQ")"}; do (( ${before[(Ie)$p]} )) || pid=$p; done
done
for _ in {1..$(( seconds * 2 ))}; do
  printf '%5.1f s  %s  graphics %s\n' $(( EPOCHREALTIME - start )) \
    "$(footprint $pid 2>/dev/null | grep -oE 'Footprint: [0-9.]+ [KMG]B')" \
    "$(footprint $pid 2>/dev/null | grep 'unmapped) (graphics)' | awk '{print $1, $2}')"
  sleep 0.5
done
grep "^launch" $log | while read -r _ step at; do printf "%-9s %5.2f s\n" $step $(( at - start )); done
kill $pid
