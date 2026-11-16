#!/bin/zsh
# Flags a read of the disk, a wait on a process or a question to macOS on the main thread: each can stall HQ for seconds
# (a note iCloud moved off the Mac, a busy Ghostty). Such work goes in nonisolated code, Task.detached or a queue, and
# its result shows behind a LoadingLine (DESIGN.md, Loading). Test code (SelfTest, UITest, Snapshot, SeedData) is left out.
# Usage: tools/io-lint.sh [folder]      (default: Sources/HQ)
# Silence one line with a reason: // io: ok <why>
set -euo pipefail
dir=${1:-${0:A:h:h}/Sources/HQ}
find "$dir" -name '*.swift' ! -name 'SelfTest*' ! -name 'UITest*' ! -name 'Snapshot*' ! -name 'SeedData*' -print0 | xargs -0 perl -ne '
  BEGIN { $count = 0 }
  if ($. == 1) { $depth = 0; @safe = () }
  my $code = $_; $code =~ s{//.*}{}; $code =~ s/"(?:[^"\\]|\\.)*"/""/g;
  # Code that runs off the main thread, until its braces close.
  push @safe, $depth if $code =~ /\bnonisolated\b|Task\.detached|readDiskText|\.async\s*\{|NoteWriter\.run/;
  if (!@safe && !/io: ok/ && $code =~ /(String\(contentsOf|Data\(contentsOf|contentsOfFile|contentsOfDirectory|waitUntilExit|readDataToEndOfFile|AEDeterminePermissionToAutomateTarget|Ghostty\.access\(|pluginInstalled\(\)|Vault\.body\(|enumerator\(at)/) {
    my $api = $1; $count++; my $l = $_; $l =~ s/^\s+//; print "$ARGV:$.: $api: $l";
  }
  $depth += () = $code =~ /\{/g;
  $depth -= () = $code =~ /\}/g;
  pop @safe while @safe && $depth <= $safe[-1];
  close ARGV if eof;
  END { if ($count) { print "FAIL io-lint: $count lines read the disk or wait on the main thread\n"; exit 1 } print "PASS io-lint\n" }'
