#!/bin/zsh
# Flags what keeps HQ busy while nothing happens, or wakes SwiftUI's GPU renderer, which holds about 250 MB for
# seconds after each use (DESIGN.md §12, Motion): per-frame redraws (TimelineView, display links, phaseAnimator,
# keyframeAnimator, repeatForever) and drawing through that renderer (Canvas, MeshGradient, drawingGroup,
# ImageRenderer). What loops goes on Core Animation; a drawing made once goes through ImageRenderer.render into a
# CGContext, on the CPU.
# Usage: tools/perf-lint.sh [folder]      (default: Sources)
# Silence one line with a reason: // perf: ok <why>
set -euo pipefail
dir=${1:-${0:A:h:h}/Sources}
find "$dir" -name '*.swift' -print0 | xargs -0 perl -ne '
  BEGIN { $count = 0 }
  if (!/perf: ok/ && !/^\s*\/\//) {
    my @bad;
    for my $api (qw(TimelineView Canvas MeshGradient phaseAnimator keyframeAnimator repeatForever drawingGroup displayLink CADisplayLink ImageRenderer)) {
      push @bad, $api if /\b$api\b/;
    }
    if (@bad) { $count++; my $l = $_; $l =~ s/^\s+//; print "$ARGV:$.: ", join(", ", @bad), ": $l"; }
  }
  close ARGV if eof;
  END { if ($count) { print "FAIL perf-lint: $count lines redraw on their own or draw on the GPU\n"; exit 1 } print "PASS perf-lint\n" }'
