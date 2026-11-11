#!/bin/zsh
# What sessions asked of hq and what it refused, mined from Claude Code's transcripts (~/.claude/projects) since a date:
# the failures table of a release (ITERATION.md, Release), as outline.log is the outline's. It prints hq commands and
# hq's own messages only, as markdown to paste into an HQ file.
# Usage: tools/hq-usage.sh [--since 2026-11-10]      (default: the last 7 days)
set -euo pipefail
since=$(date -v-7d +%Y-%m-%d)
[[ ${1:-} == --since && -n ${2:-} ]] && since=$2
files=(${(f)"$(find ~/.claude/projects -name '*.jsonl' -newermt $since 2>/dev/null)"})
(( ${#files} )) || { print "No transcript since $since."; exit 0 }

# Each Bash call that ran hq, and each tool result with an hq or jq error, keyed by the call's id.
extract='
  def hq: "(^|[^A-Za-z0-9_./-])hq\\s+[a-z-]";
  select((.timestamp // "") >= $since) | . as $l
  | if .type == "assistant" then
      (.message.content // [])[]? | select(type == "object" and .type == "tool_use" and .name == "Bash")
      | select((.input.command // "") | test(hq))
      | {k: "use", id, cmd: .input.command, sid: ($l.sessionId // "")}
    elif .type == "user" and (.message.content | type) == "array" then
      .message.content[] | select(type == "object" and .type == "tool_result")
      | (.content | if type == "array" then map(.text? // "") | join("\n") else tostring end) as $t
      | select($t | test("(^|\n)hq: |jq: error"))
      # What hq says on stderr: an error, a retired name, a needless flag, an older HQ. Its help starts with "hq:" too.
      | {k: "res", id: .tool_use_id, jq: ($t | test("jq: error")),
         hq: [$t | split("\n")[] | select(startswith("hq: ")) | .[4:] | select(test("^(drive the app|same as installed)") | not)]}
    else empty end'

report='
  def short: gsub("\\s+"; " ") | .[0:110];
  def calls: [scan("hq\\s+[a-z][^|;&)\n]*")];
  def call: calls[0] // . | short;
  # The invocation an error is about: the one with its task key or flag, else the first.
  def call($line): [$line | scan("T-[0-9]+|--[a-z-]+")] as $t | ([calls[] | select(. as $c | any($t[]; . as $k | $c | contains($k)))][0] // calls[0] // "") | short;
  def name: [scan("(?:^|[^A-Za-z0-9_./-])hq\\s+([a-z-]+)(?:\\s+([a-z-]+))?")][]
    | select(.[0] | IN("ctx", "status", "ls", "task", "file", "project", "notification", "session", "artifact", "notify", "remind", "help", "hook", "link", "tag", "show"))
    | if (.[0] | IN("task", "file", "project", "notification", "session", "artifact")) and .[1] != null then "\(.[0]) \(.[1])" else .[0] end;
  def cause: gsub("T-[0-9]+"; "T-n") | gsub("“[^”]*”"; "“…”") | gsub("\\b[0-9A-F]{8}\\b"; "<id>") | gsub("https?://\\S+"; "<url>") | .[0:120];
  (map(select(.k == "use")) | INDEX(.id)) as $uses
  | (map(select(.k == "use"))) as $calls
  | [.[] | select(.k == "res" and $uses[.id] != null) | . + {cmd: $uses[.id].cmd, sid: $uses[.id].sid}] as $failed
  | "# hq usage since \($since)\n",
    "\($calls | length) Bash calls ran hq in \($calls | map(.sid) | unique | length) sessions; \($failed | map(select(.hq | length > 0)) | length) got an hq error, \($failed | map(select(.jq)) | length) a jq error.\n",
    "## Failures\n", "| hq said | Times | Sessions | Example |", "|---|---|---|---|",
    ([$failed[] | . as $f | .hq[] | {cause: cause, line: ., sid: $f.sid, cmd: $f.cmd}] | group_by(.cause) | sort_by(-length)[]
      | "| \(.[0].cause | gsub("\\|"; "\\\\|")) | \(length) | \(map(.sid) | unique | length) | `\(.[0].line as $line | .[0].cmd | call($line) | gsub("[|`]"; "·"))` |"),
    "\n## jq on hq'\''s JSON\n",
    ([$failed[] | select(.jq) | .cmd | call] | unique | .[0:8][] | "- `\(gsub("`"; "·"))`"),
    "\n## Commands\n", "| Command | Calls |", "|---|---|",
    ([$calls[] | .cmd | name] | group_by(.) | map({name: .[0], n: length}) | sort_by(-.n)[] | "| \(.name) | \(.n) |")'

for file in $files; do jq -c --arg since $since "$extract" $file 2>/dev/null || true; done \
  | jq -rs --arg since $since "$report"
