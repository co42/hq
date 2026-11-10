#!/bin/zsh
# Keeps the docs true to the app: every `hq …` command a doc shows (in backticks or a code block) exists with the
# options it uses (checked against `hq help --json` of the test copy), and no doc uses a retired name.
# Docs: README.md, CLAUDE.md, PLAN.md, DESIGN.md and the plugin's skills; RELEASE_NOTES.md keeps history and is skipped.
# Usage: tools/docs-lint.sh [files…]      (after ./build.sh --dev, so the help matches this branch)
# Silence one line with a reason: <!-- docs: ok <why> -->. DESIGN.md §19 (Gone) names retired things on purpose.
set -euo pipefail
here=${0:A:h:h}
bin="${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}/Contents/MacOS/HQ"
[[ -x $bin ]] || bin=$(command -v hq)
files=("$@")
(( $# )) || files=("$here"/{README,CLAUDE,PLAN,DESIGN,ITERATION}.md "$here"/plugin/skills/*/SKILL.md)
schema=$(mktemp -t hq-help)
trap 'rm -f $schema' EXIT
"$bin" help --json | jq -r '.commands[] | .name + "\t" + ((.inputSchema.properties // {}) | keys | join(" "))' >| $schema

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
)

SCHEMA=$schema RETIRED=${(pj:\t:)retired} perl -ne '
  BEGIN {
    open my $s, "<", $ENV{SCHEMA} or die;
    while (<$s>) { chomp; my ($n, $o) = split /\t/; $cmd{$n} = { map { $_ => 1 } split / /, ($o // "") }; }
    %two = map { $_ => 1 } qw(task project file artifact notification session);
    %kinds = map { $_ => 1 } qw(sessions tasks prs files artifacts projects notifications);
    %moves = map { $_ => 1 } qw(todo doing done backlog);
    @retired = split /\t/, $ENV{RETIRED};
    $count = 0;
  }
  sub bad { my ($what) = @_; $count++; my $l = $_; $l =~ s/^\s+//; $l = substr($l, 0, 160); chomp $l; print "$ARGV:$.: $what: $l\n"; }
  $fence = !$fence if /^\s*```/;
  $gone = /^## 19\. Gone/ ? 1 : /^## / ? 0 : $gone;
  if (!/docs: ok/) {
    for (my $i = 0; !$gone && $i < @retired; $i += 2) { bad("\"$retired[$i]\" is retired, now $retired[$i+1]") if index($_, $retired[$i]) >= 0; }
    my @spans = $fence ? (s/\s#\s.*//r) : (/`([^`]*)`/g);
    for my $span (@spans) {
      while ($span =~ /(?:^|[\s(|;&])hq\s+([a-z][a-z-]*)(?:\s+([a-z][a-z-]*))?((?:\s+(?!hq\s)\S+)*)/g) {
        my ($w1, $w2, $rest) = ($1, $2 // "", $3 // "");
        next if $w1 =~ /^(help|plugin|skill|skills|app|command)$/;
        my $name = $two{$w1} ? "$w1 $w2" : $w1;
        $rest = " $w2$rest" unless $two{$w1};
        if (!$cmd{$name}) { bad("hq $name is no command") unless $two{$w1} && $w2 eq ""; next; }
        for my $flag ($rest =~ /(?:^|[\s\[|])--([a-z][a-z-]*)/g) {
          bad("hq $name has no --$flag") unless $cmd{$name}{$flag} || $flag eq "json";
        }
        if ($name eq "ls" && $rest =~ /^\s+([a-z]+)\b/ && !$kinds{$1}) { bad("hq ls lists no $1") }
        if ($name eq "task move" && $rest =~ /^\s+\S+\s+([a-z]+)\b/ && !$moves{$1}) { bad("hq task move takes no $1") }
      }
    }
  }
  if (eof) { close ARGV; $fence = 0; $gone = 0; }
  END { if ($count) { print "FAIL docs-lint: $count lines out of date\n"; exit 1 } print "PASS docs-lint\n" }
' "${files[@]}"
