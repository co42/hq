#!/bin/zsh
# Measures a test copy of HQ: CPU, memory and GPU memory, on copies of your store and vault (read only: the
# originals stay untouched) or on the seed. It runs beside your own HQ.
# Usage: tools/perf.sh [seconds measured, 30] [seconds to settle first, 20]
#          PERF_SEED=1          the seed data
#          PERF_ARCHIVE=10000   with the seed, an Archive of that many tasks (T-471): --check runs with 10,000
#          PERF_BUSY=10         a session's tool calls come in meanwhile, 10 hook events a second
#          PERF_STATES=1        each tool call a question: the session goes from working to waiting and back
#          PERF_SAMPLE=<file>   a call tree of the measured seconds, from sample(1)
#          PERF_OPEN=<title>    opens that note, scrolls it to its end and back, closes it, round after round; prints
#                               each round's times (perf open lines); PERF_OPEN=@center opens the notification center
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
budget_rest_cpu=3        # % at rest, faces swaying and cards breathing (0.1 alone; 1.0 beside the tests, 2026-11-11)
budget_memory=200        # MB at rest (about 90)
budget_peak=200          # MB at any time since launch (about 90; 380 to 540 before 2026-11-06)
budget_gpu=20            # MB of GPU memory at rest (3; 260 to 420 before)
budget_busy_cpu=5        # % with tool calls coming in at 10 a second (1.5; 28 before)
budget_launch=2          # s from opening HQ to its window with the tasks shown (0.4 on the user's store and vault, 2026-11-16)
budget_store=5           # MB of the store and its log after the busy run (the user's held 161 MB of history before it was pruned, 2026-11-16)
budget_center=300        # ms the main thread holds to open the notification center, the median of its opens (160 on the seed, 2026-11-20, T-683)

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

# One run: sets launch, cpu, memory, peak, gpu, store_size and events.
measure() {
  local measure=$1 settle=$2
  rm -f $store $store-shm $store-wal $store.sock $log
  rm -rf $vault && mkdir -p $vault
  local env=(--env APP_STORE=$store --env HQ_VAULT=$vault --env HQ_GITHUB=fixtures --env HQ_LAUNCH_LOG=1)
  [[ -n ${PERF_OPEN:-} ]] && env+=(--env "HQ_PERF_OPEN=$PERF_OPEN")
  if [[ ${PERF_SEED:-0} == 1 ]]; then
    mkdir -p $vault/hq/tasks $vault/hq/files
    env+=(--env APP_SEED=1)
    if [[ -n ${PERF_ARCHIVE:-} ]]; then
      # An Archive of PERF_ARCHIVE tasks, stories of five (T-471): launch reads none of them.
      mkdir -p $vault/hq/tasks/archive
      perl -e 'for my $i (1..$ARGV[0]) { my $n = 100000 + $i; my $story = 100000 + $i - ($i % 5 || 5) + 1;
        my $up = $n == $story ? "archived: 2026-11-01T10:00" : "parent: T-$story";
        open my $f, ">", "$ARGV[1]/T-$n.md" or die;
        print $f "---\ntitle: Archived task $i\nstatus: done\n$up\norder: $i\ndone: 2026-10-20T10:00\n---\nA description.\n"; close $f }' $PERF_ARCHIVE $vault/hq/tasks/archive
    fi
  else
    sqlite3 "$HOME/Library/Application Support/HQ/HQ.store" ".backup $store"
    cp -R "$notes/hq" $vault/
  fi
  local opened=$EPOCHREALTIME
  open -g -n "$app" $env --stdout $log --stderr $log --args -ApplePersistenceIgnoreState YES
  # The test copy is the process with its store open: other test copies may start beside it.
  local pid=""
  for _ in {1..50}; do
    pid=$(lsof -t $store 2>/dev/null | head -1)
    [[ -n $pid ]] && break
    sleep 0.2
  done
  [[ -n $pid ]] || { print "perf: the test copy didn't start"; exit 1 }
  sleep $settle
  # The window with the tasks shown, from the launch marks HQ prints (LaunchLog).
  local shown=$(awk '$1 == "launch" && ($2 == "window" || $2 == "tasks") {n++; if ($3 > t) t = $3} END {if (n == 2) printf "%.3f", t}' $log)
  launch=$(( ${shown:-0} > 0 ? shown - opened : 999 ))
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
        print $n >| /tmp/HQ-perf.busy.new && mv /tmp/HQ-perf.busy.new /tmp/HQ-perf.busy; sleep $(( 1.0 / PERF_BUSY ))
        hook PostToolUse ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo $n\"}"
        print $n >| /tmp/HQ-perf.busy.new && mv /tmp/HQ-perf.busy.new /tmp/HQ-perf.busy; sleep $(( 1.0 / PERF_BUSY ))
      done ) &
    busy=$!
  fi
  local sampler=""
  if [[ -n ${PERF_SAMPLE:-} ]]; then sample $pid $measure -file $PERF_SAMPLE >/dev/null 2>&1 & sampler=$!; fi
  # top's second sample covers the measured seconds.
  cpu=$(top -l 2 -s $measure -pid $pid -stats pid,cpu | awk '/^PID/{n++} n==2 && $1 ~ /^[0-9]+$/ {print $2}')
  [[ -n $sampler ]] && wait $sampler
  [[ -n $cpu ]] || { print "FAIL perf: the test copy ($pid) quit while measured: $log"; exit 1 }
  events=0
  if [[ -n $busy ]]; then
    kill $busy
    local sent=$(cat /tmp/HQ-perf.busy 2>/dev/null)
    events=$(( ${sent:-0} * 2 ))
  fi
  if [[ ${PERF_SEED:-0} == 1 ]]; then
    # The seed's tasks outlive the vault's scans (T-563).
    local seeded=$(APP_AGENT_SOCKET=$store.sock "$app/Contents/MacOS/HQ" ls tasks --all --json 2>/dev/null | jq '.tasks | length' 2>/dev/null)
    (( ${seeded:-0} > 0 )) || { print "FAIL perf: the seed's tasks are gone once the vault was read ($log)"; kill $pid; exit 1 }
  fi
  local summary=$(vmmap --summary $pid 2>/dev/null)
  memory=$(megabytes "$(print -r -- $summary | awk -F: '/^Physical footprint:/ {print $2}')")
  peak=$(megabytes "$(print -r -- $summary | awk -F: '/^Physical footprint \(peak\):/ {print $2}')")
  local graphics=$(footprint $pid 2>/dev/null | awk '/unmapped\) \(graphics\)/ {print $1, $2; exit}')
  gpu=$(megabytes "${graphics:-0 KB}")
  kill $pid
  sleep 0.5
  store_size=$(( ($(stat -f %z $store) + $(stat -f %z $store-wal 2>/dev/null || print 0)) / 1048576.0 ))
}

if [[ ${1:-} == --check ]]; then
  failed=0
  verdict() {   # name, value, budget, unit
    if (( $2 > $3 )); then failed=1; printf 'FAIL %s: %.1f %s, over %s\n' $1 $2 $4 $3
    else printf 'PASS %s: %.1f %s (budget %s)\n' $1 $2 $4 $3; fi
  }
  export PERF_SEED=1 PERF_ARCHIVE=10000
  unset PERF_BUSY PERF_STATES PERF_SAMPLE
  measure 15 10
  rest_cpu=$cpu rest_memory=$memory rest_peak=$peak rest_gpu=$gpu
  verdict "launch to the window with its tasks, 10,000 archived" $launch $budget_launch s
  verdict "CPU at rest" $rest_cpu $budget_rest_cpu %
  verdict "memory at rest" $rest_memory $budget_memory MB
  verdict "memory peak since launch" $rest_peak $budget_peak MB
  verdict "GPU memory at rest" $rest_gpu $budget_gpu MB
  PERF_BUSY=10 measure 15 10
  verdict "CPU with tool calls coming in ($(( events / 15 )) a second)" $cpu $budget_busy_cpu %
  verdict "store size after the busy run" $store_size $budget_store MB
  # Opening a sheet over the page: the notification center, as a banner click opens it.
  PERF_OPEN=@center measure 8 6
  center=$(grep -h "center round" $log | sed -E "s/.*open stall ([0-9]+) ms.*/\1/" | sort -n | awk '{v[NR]=$1} END {print NR ? v[int((NR + 1) / 2)] : 9999}')
  verdict "opening the notification center (median)" $center $budget_center ms
  mkdir -p ${perf_history:h}
  [[ -f $perf_history ]] || print "date\tcommit\trest cpu %\tmemory MB\tpeak MB\tgpu MB\tbusy cpu %" >| $perf_history
  commit=$(git -C ${0:A:h:h} rev-parse --short HEAD 2>/dev/null)$(git -C ${0:A:h:h} diff --quiet 2>/dev/null || print +)
  printf '%s\t%s\t%.1f\t%.0f\t%.0f\t%.1f\t%.1f\n' "$(date '+%Y-%m-%d %H:%M')" $commit $rest_cpu $rest_memory $rest_peak $rest_gpu $cpu >> $perf_history
  (( failed )) && { print "FAIL perf: over budget (history: $perf_history)"; exit 1 }
  print "PASS perf (history: $perf_history)"
  exit 0
fi

measure ${1:-30} ${2:-20}
printf 'launch %.2f s  cpu %s%%  memory %.0f MB (peak %.0f MB)  GPU memory %.1f MB  store %.1f MB' $launch $cpu $memory $peak $gpu $store_size
(( events )) && printf '  busy: %s hook events sent' $events
print
