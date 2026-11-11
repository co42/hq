#!/bin/zsh
# Holds what review held by hand (CLAUDE.md, Rules; DESIGN.md §12):
# - views use DesignKit's tokens: no raw color, font size, SF Symbol name or animation outside Sources/HQ/DesignKit;
# - an `isFlipped` override is nonisolated: AppKit reads it off the main thread when a drag of several items starts;
# - a double-click goes through SelectOpen, never onTapGesture(count: 2).
# Usage: tools/code-lint.sh       Silence one line with a reason: // lint: ok <why>
set -euo pipefail
src=${0:A:h:h}/Sources/HQ
find $src -name '*.swift' -print0 | xargs -0 perl -ne '
  BEGIN { $count = 0 }
  my $kit = $ARGV =~ m{/DesignKit/};
  my $tests = $ARGV =~ m{/(UITest|UITestChecks|SelfTest|Snapshot|SeedData)\.swift$};
  if (!/lint: ok/ && !/^\s*\/\//) {
    my @bad;
    push @bad, "isFlipped must be nonisolated" if /override var isFlipped/ && !/nonisolated/;
    if (!$kit && !$tests) {
      push @bad, "a raw color" if /\b(?:NS)?Color\((?:red|white|hue|srgbRed|calibratedRed):/;
      push @bad, "a raw font size" if /\.(?:system|monospacedSystemFont)\((?:size|ofSize):/;
      push @bad, "an SF Symbol by name" if /(?:systemName|systemSymbolName):\s*"/;
      push @bad, "a raw animation" if /\.(?:easeIn|easeOut|easeInOut|linear|spring|smooth)\(duration:/;
      push @bad, "a double-click outside SelectOpen" if /onTapGesture\(count:\s*2/;
    }
    if (@bad) { $count++; my $l = $_; $l =~ s/^\s+//; print "$ARGV:$.: ", join(", ", @bad), ": $l"; }
  }
  close ARGV if eof;
  END { if ($count) { print "FAIL code-lint: $count lines\n"; exit 1 } print "PASS code-lint\n" }'
