#!/bin/zsh
# Flags a read of the disk, a wait on a process or a question to macOS on the main thread: each can stall HQ for seconds
# (a note iCloud moved off the Mac, a busy Ghostty). Such work goes in nonisolated code, Task.detached or a queue, and
# its result shows behind a LoadingLine (DESIGN.md, Loading). Test code (SelfTest, UITest, Snapshot, SeedData) is left out.
# HQKit's readers count as reads: transcripts, git, Claude's session records, a page's title (T-683). A DispatchQueue.main or MainActor block is the main thread, even inside off-main code.
# Usage: tools/io-lint.sh [folder]      (default: Sources/HQ)
# Silence one line with a reason: // io: ok <why>
set -euo pipefail
dir=${1:-${0:A:h:h}/Sources/HQ}
find "$dir" -name '*.swift' ! -name 'SelfTest*' ! -name 'UITest*' ! -name 'Snapshot*' ! -name 'SeedData*' -print0 | xargs -0 perl -ne '
  BEGIN { $count = 0 }
  if ($. == 1) { $depth = 0; @blocks = () }
  my $code = $_; $code =~ s{//.*}{}; $code =~ s/"(?:[^"\\]|\\.)*"/""/g;
  # A block that runs off the main thread, or back on it inside one, until its braces close: [depth, off main].
  if ($code =~ /DispatchQueue\.main\.async|MainActor\.(?:run|assumeIsolated)|\@MainActor/) { push @blocks, [$depth, 0] }
  elsif ($code =~ /\bnonisolated\b|Task\.detached|readDiskText|\.async(?:After)?\s*(?:\(|\{)|NoteWriter\.run/) { push @blocks, [$depth, 1] }
  my $off = @blocks && $blocks[-1][1];
  if (!$off && !/io: ok/ && $code =~ /(String\(contentsOf|Data\(contentsOf|contentsOfFile|contentsOfDirectory|waitUntilExit|readDataToEndOfFile|AEDeterminePermissionToAutomateTarget|Ghostty\.access\(|pluginInstalled\(\)|Vault\.body\(|enumerator\(at|ClaudeModel\.usage\(|GitInfo\.(?:describe|origin)\(|TranscriptTitle\.(?:read|lastRename)\(|TranscriptInterrupt\.read\(|ClaudeSessionFile\.idleSince\(|title\(ofPage)/) {
    my $api = $1; $count++; my $l = $_; $l =~ s/^\s+//; print "$ARGV:$.: $api: $l";
  }
  $depth += () = $code =~ /\{/g;
  $depth -= () = $code =~ /\}/g;
  pop @blocks while @blocks && $depth <= $blocks[-1][0];
  close ARGV if eof;
  END { if ($count) { print "FAIL io-lint: $count lines read the disk or wait on the main thread\n"; exit 1 } print "PASS io-lint\n" }'
