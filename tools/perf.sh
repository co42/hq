#!/bin/zsh
# Measures a test copy of HQ: CPU, memory and GPU memory, on copies of your store and vault (read only: the
# originals stay untouched) or on the seed. It runs beside your own HQ.
# Usage: tools/perf.sh [seconds measured, 30] [seconds to settle first, 20]
#          PERF_SEED=1          the seed data
#          PERF_BUSY=10         a session's tool calls come in meanwhile, 10 hook events a second
#          PERF_STATES=1        each tool call a question: the session goes from working to waiting and back
#          PERF_SAMPLE=<file>   a call tree of the measured seconds, from sample(1)
#        tools/perf.sh --check  the budgets below, on the seed: at rest, then with tool calls coming in. Exit code 1
#                               over any. Each run adds a line to ~/Library/Developer/HQ/perf-history.tsv.
set -u
zmodload zsh/datetime
app="${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}"
store=/tmp/HQ-perf.store
vault=/tmp/HQ-perf-vault
log=/tmp/HQ-perf.log
notes="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes"
perf_history="$HOME/Library/Developer/HQ/perf-history.tsv"

# Budgets for --check: loose enough for any machine, tight enough to catch a redraw loop or SwiftUI's GPU renderer.
budget_rest_cpu=1        # % at rest, faces swaying and cards breathing (0.1 on 2026-11-06)
budget_memory=200        # MB at rest (about 90)
budget_peak=200          # MB at any time since launch (about 90; 380 to 540 before 2026-11-06)
budget_gpu=20            # MB of GPU memory at rest (3; 260 to 420 before)
budget_busy_cpu=5        # % with tool calls coming in at 10 a second (1.5; 28 before)

# "88.9M", "3136 KB", "1.2 GB": megabytes.
megabytes() {
  local value=${1//[^0-9.]/} unit=${1//[0-9. ]/}
  [[ -z $value ]] && value=0
  case $unit in
    K*) print $(( value / 1024.0 ));;
    G*) print $(( value * 1024.0 ));;
    *) print $(( value * 1.0 ));;
  esac
}

# One run: sets cpu, memory, peak, gpu and events.
measure() {
  local measure=$1 settle=$2
  rm -f $store $store-shm $store-wal $store.sock $log
  rm -rf $vault && mkdir -p $vault
  local env=(--env APP_STORE=$store --env HQ_VAULT=$vault --env HQ_GITHUB=fixtures)
  if [[ ${PERF_SEED:-0} == 1 ]]; then
    mkdir -p $vault/hq/tasks $vault/hq/files
    env+=(--env APP_SEED=1)
  else
    sqlite3 "$HOME/Library/Application Support/HQ/HQ.store" ".backup $store"
    cp -R "$notes/hq" $vault/
  fi
  local before=(${(f)"$(pgrep -f "$app/Contents/MacOS/HQ")"})
  open -g -n "$app" $env --stdout $log --stderr $log --args -ApplePersistenceIgnoreState YES
  local pid="" p
  for _ in {1..50}; do
    for p in ${(f)"$(pgrep -f "$app/Contents/MacOS/HQ")"}; do (( ${before[(Ie)$p]} )) || pid=$p; done
    [[ -n $pid ]] && break
    sleep 0.2
  done
  [[ -n $pid ]] || { print "perf: the test copy didn't start"; exit 1 }
  sleep $settle
  local busy=""
  if [[ -n ${PERF_BUSY:-} ]]; then
    hook() { print -r -- "{\"hook_event_name\":\"$1\",\"session_id\":\"perf-busy\",\"cwd\":\"/tmp\"$2}" | APP_AGENT_SOCKET=$store.sock "$app/Contents/MacOS/HQ" hook >/dev/null 2>&1 }
    hook SessionStart ',"source":"startup"'
    hook UserPromptSubmit ',"prompt":"Busy"'
    local tool=Bash
    [[ ${PERF_STATES:-0} == 1 ]] && tool=AskUserQuestion
    print 0 >| /tmp/HQ-perf.busy
    ( n=0; while true; do
        n=$((n + 1))
        hook PreToolUse ",\"tool_name\":\"$tool\",\"tool_input\":{\"command\":\"echo $n\"}"
        print $n >| /tmp/HQ-perf.busy; sleep $(( 1.0 / PERF_BUSY ))
        hook PostToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo $n\"}"
        print $n >| /tmp/HQ-perf.busy; sleep $(( 1.0 / PERF_BUSY ))
      done ) &
    busy=$!
  fi
  local sampler=""
  if [[ -n ${PERF_SAMPLE:-} ]]; then sample $pid $measure -file $PERF_SAMPLE >/dev/null 2>&1 & sampler=$!; fi
  # top's second sample covers the measured seconds.
  cpu=$(top -l 2 -s $measure -pid $pid -stats pid,cpu | awk '/^PID/{n++} n==2 && $1 ~ /^[0-9]+$/ {print $2}')
  [[ -n $sampler ]] && wait $sampler
  events=0
  if [[ -n $busy ]]; then
    kill $busy
    events=$(( $(cat /tmp/HQ-perf.busy) * 2 ))
  fi
  local summary=$(vmmap --summary $pid 2>/dev/null)
  memory=$(megabytes "$(print -r -- $summary | awk -F: '/^Physical footprint:/ {print $2}')")
  peak=$(megabytes "$(print -r -- $summary | awk -F: '/^Physical footprint \(peak\):/ {print $2}')")
  local graphics=$(footprint $pid 2>/dev/null | awk '/unmapped\) \(graphics\)/ {print $1, $2; exit}')
  gpu=$(megabytes "${graphics:-0 KB}")
  kill $pid
}

if [[ ${1:-} == --check ]]; then
  failed=0
  verdict() {   # name, value, budget, unit
    if (( $2 > $3 )); then failed=1; printf 'FAIL %s: %.1f %s, over %s\n' $1 $2 $4 $3
    else printf 'PASS %s: %.1f %s (budget %s)\n' $1 $2 $4 $3; fi
  }
  export PERF_SEED=1
  unset PERF_BUSY PERF_STATES PERF_SAMPLE
  measure 20 20
  rest_cpu=$cpu rest_memory=$memory rest_peak=$peak rest_gpu=$gpu
  verdict "CPU at rest" $rest_cpu $budget_rest_cpu %
  verdict "memory at rest" $rest_memory $budget_memory MB
  verdict "memory peak since launch" $rest_peak $budget_peak MB
  verdict "GPU memory at rest" $rest_gpu $budget_gpu MB
  PERF_BUSY=10 measure 20 20
  verdict "CPU with tool calls coming in ($(( events / 20 )) a second)" $cpu $budget_busy_cpu %
  mkdir -p ${perf_history:h}
  [[ -f $perf_history ]] || print "date\tcommit\trest cpu %\tmemory MB\tpeak MB\tgpu MB\tbusy cpu %" >| $perf_history
  commit=$(git -C ${0:A:h:h} rev-parse --short HEAD 2>/dev/null)$(git -C ${0:A:h:h} diff --quiet 2>/dev/null || print +)
  printf '%s\t%s\t%.1f\t%.0f\t%.0f\t%.1f\t%.1f\n' "$(date '+%Y-%m-%d %H:%M')" $commit $rest_cpu $rest_memory $rest_peak $rest_gpu $cpu >> $perf_history
  (( failed )) && { print "FAIL perf: over budget (history: $perf_history)"; exit 1 }
  print "PASS perf (history: $perf_history)"
  exit 0
fi

measure ${1:-30} ${2:-20}
printf 'cpu %s%%  memory %.0f MB (peak %.0f MB)  GPU memory %.1f MB' $cpu $memory $peak $gpu
(( events )) && printf '  busy: %s hook events sent' $events
print
