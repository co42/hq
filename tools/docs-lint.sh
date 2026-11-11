#!/bin/zsh
# Keeps the docs true to the app: every `hq …` command a doc shows (in backticks or a code block) exists with the
# options it uses (checked against `hq help --json` of the test copy), `hq ls` only gets the filters its kind takes,
# a skill a doc names exists, and no doc uses a retired name.
# Docs: README.md, CLAUDE.md, PLAN.md, DESIGN.md, ITERATION.md, the plugin's skills, `hq help` for every command and
# the hook's start text (Sessions.swift startContext). The HQ section of ~/.claude/CLAUDE.md is read too, as warnings:
# it's the user's file. RELEASE_NOTES.md keeps history and is skipped.
# Usage: tools/docs-lint.sh [files…]      (after ./build.sh --dev, so the help matches this branch)
# Silence one line with a reason: <!-- docs: ok <why> -->. DESIGN.md §19 (Gone) names retired things on purpose.
set -euo pipefail
here=${0:A:h:h}
bin="${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}/Contents/MacOS/HQ"
[[ -x $bin ]] || bin=$(command -v hq)
work=$(mktemp -d -t hq-docs)
trap 'rm -rf $work' EXIT
schema=$work/schema
"$bin" help --json | jq -r '.commands[] | .name + "\t" + ((.inputSchema.properties // {}) | keys | join(" "))' >| $schema

# What sessions read besides the docs: each command's help, and the hook's start text, as code.
files=("$@")
if (( ! $# )); then
  # Its usage and example lines read as code, the rest as prose (its `hq …` in backticks).
  jq -r '.commands[].name' < <("$bin" help --json) | while read -r name; do "$bin" help ${=name}; done \
    | perl -pe 's/^((?:  hq |Example: ).*)$/```\n$1\n```/' >| $work/hq-help
  { print '```'; sed -n '/func startContext/,/^    }/p' "$here/Sources/HQ/Sessions.swift" | grep -o '"[^"]*"' | tr -d '"'; print '```' } >| $work/start-text
  files=("$here"/{README,CLAUDE,PLAN,DESIGN,ITERATION}.md "$here"/plugin/skills/*/SKILL.md $work/hq-help $work/start-text)
fi
skills=(${(f)"$(command ls "$here/plugin/skills")"})

# Names the app no longer has, and what replaced them.
retired=(
  'Review Next' 'the notification center (⌘J)'
  'Mark All Seen' 'the notification center'
  'Show Reviewed' 'the Reviews filter'
  'Unfiled' 'projects'
  'hq ls folders' 'hq ls projects'
  'blue dot' 'nothing: v9 removed them'
  '--reason' 'hq notify'
  'Open in Ghostty' 'Focus'
  'Start in Ghostty' 'Start'
  'Hidden and Closed' 'Closed Sessions'
  'Mark All Read' 'nothing: each notification on its own (T-310)'
  'the next morning' 'nothing: no task moves on its own (T-345)'
  'Done rule' 'nothing: no task moves on its own (T-345)'
  'claude attach' 'nothing: HQ never attaches a background session (T-327)'
  '--type' 'nothing: tasks have no type (T-220)'
  'Copy Key and Title' 'Copy: the kind, key and title of an item (T-358)'
  'Read in place' 'a row moves at once (T-365)'
  'its grip moves' 'a drag from anywhere on the card (T-372)'
  'progress ring' 'a block'"'"'s small bar, a story'"'"'s progress line (T-372)'
  'Quick Look' 'Space opens the task; its description button shows a description (T-372)'
  'hq-tasks' 'the hq skill: plugin 0.10.0 merged them'
  'under the task'"'"'s row' 'on the task'"'"'s card (v13)'
  'Exit code 4' 'nothing: hq opens HQ, sessions never met it'
)

lint='
  BEGIN {
    open my $s, "<", $ENV{SCHEMA} or die;
    while (<$s>) { chomp; my ($n, $o) = split /\t/; $cmd{$n} = { map { $_ => 1 } split / /, ($o // "") }; }
    %two = map { $_ => 1 } qw(task project file artifact notification session);
    %kinds = map { $_ => 1 } qw(sessions tasks prs files artifacts projects notifications reminders);
    %moves = map { $_ => 1 } qw(todo doing done backlog);
    %skill = map { $_ => 1 } split / /, $ENV{SKILLS};
    # The filters each kind of hq ls takes; --limit and --offset go with any.
    %filters = (sessions => "all here", tasks => "overview backlog parent project tag all", prs => "all", notifications => "all", reminders => "all");
    @retired = split /\t/, $ENV{RETIRED};
    $count = 0;
  }
  sub bad {
    my ($what) = @_; $count++; my $l = $_; $l =~ s/^\s+//; $l = substr($l, 0, 160); chomp $l;
    my $file = $ARGV; $file =~ s{.*/hq-docs[^/]*/}{};
    print(($ENV{WARN} ? "WARN " : "") . "$file:$.: $what: $l\n");
  }
  $fence = !$fence if /^\s*```/;
  $gone = /^## 19\. Gone/ ? 1 : /^## / ? 0 : $gone;
  if (!/docs: ok/) {
    for (my $i = 0; !$gone && $i < @retired; $i += 2) { bad("\"$retired[$i]\" is retired, now $retired[$i+1]") if index($_, $retired[$i]) >= 0; }
    while (/`?\b(hq(?:-[a-z]+)*)`?\s+skills?\b/g) { bad("no skill $1") unless $skill{$1} }
    my @spans = $fence ? (s/\s#\s.*//r) : (/`([^`]*)`/g);
    for my $span (@spans) {
      while ($span =~ /(?:^|[\s(|;&:])hq\s+([a-z][a-z-]*)(?:\s+([a-z][a-z-]*))?((?:\s+(?!hq\s)\S+)*)/g) {
        my ($w1, $w2, $rest) = ($1, $2 // "", $3 // "");
        next if $w1 =~ /^(help|plugin|skill|skills|app|command)$/;
        my $name = $two{$w1} ? "$w1 $w2" : $w1;
        $rest = " $w2$rest" unless $two{$w1};
        if (!$cmd{$name}) { bad("hq $name is no command") unless $two{$w1} && $w2 eq ""; next; }
        my @flags = $rest =~ /(?:^|[\s\[|])--([a-z][a-z-]*)/g;
        for my $flag (@flags) { bad("hq $name has no --$flag") unless $cmd{$name}{$flag} || $flag eq "json"; }
        if ($name eq "ls" && $rest =~ /^\s+([a-z]+)\b/) {
          my $kind = $1;
          if (!$kinds{$kind}) { bad("hq ls lists no $kind") }
          else {
            my %takes = map { $_ => 1 } (split(/ /, $filters{$kind} // ""), "limit", "offset", "json");
            for my $flag (@flags) { bad("hq ls $kind takes no --$flag") if $cmd{ls}{$flag} && !$takes{$flag}; }
          }
        }
        if ($name eq "task move" && $rest =~ /^\s+\S+\s+([a-z]+)\b/ && !$moves{$1}) { bad("hq task move takes no $1") }
      }
    }
  }
  if (eof) { close ARGV; $fence = 0; $gone = 0; }
  END {
    exit 0 if $ENV{WARN};
    if ($count) { print "FAIL docs-lint: $count lines out of date\n"; exit 1 }
    print "PASS docs-lint\n";
  }
'
export SCHEMA=$schema RETIRED=${(pj:\t:)retired} SKILLS=${(j: :)skills}
# The user's global HQ section: told, never failed on.
global=~/.claude/CLAUDE.md
if (( ! $# )) && [[ -f $global ]]; then
  sed -n '/^# HQ$/,/^# [^H]/p' $global | sed '$d' >| $work/global-CLAUDE.md
  [[ -s $work/global-CLAUDE.md ]] && WARN=1 perl -ne "$lint" $work/global-CLAUDE.md
fi
perl -ne "$lint" "${files[@]}"
