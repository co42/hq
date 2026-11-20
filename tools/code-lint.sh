#!/bin/zsh
# Holds what review held by hand (CLAUDE.md, Rules; DESIGN.md §12):
# - views use DesignKit's tokens: no raw color, font size, SF Symbol name or animation outside Sources/HQ/DesignKit;
# - an `isFlipped` override is nonisolated: AppKit reads it off the main thread when a drag of several items starts;
# - a double-click goes through SelectOpen or opensOnDoubleClick, never onTapGesture(count: 2), which counts a click on a control inside;
# - the pointing hand only over a link in text (LinkText, a table's cells), as macOS does; no cursor rects, which go stale as the
#   page scrolls (DESIGN.md §12).
# - markdown shows and is edited through MarkdownSurface, MarkdownField and MarkdownLine only, so every place looks and edits
#   alike (T-469 item 8, DESIGN.md §9).
# - a small control shows the hover plate (`.hoverPlate`, `PlateButtonStyle`, `HoverPlateView`): no hand-made hover fill outside
#   a row, and the plate's colors only in HoverPlate (DESIGN.md §12, Hover).
# - nothing outside Setup that makes macOS ask for a permission (posting CGEvents untrusted does): a test copy never prompts.
# - the clipboard through Pasteboard.board, which a test run keeps its own: a test never reads or overwrites the user's.
# Usage: tools/code-lint.sh       Silence one line with a reason: // lint: ok <why>
set -euo pipefail
src=${0:A:h:h}/Sources/HQ
find $src -name '*.swift' -print0 | xargs -0 perl -ne '
  BEGIN { $count = 0 }
  my $kit = $ARGV =~ m{/DesignKit/};
  my $tests = $ARGV =~ m{/(UITest|UITestChecks|SelfTest|Snapshot|SeedData)\.swift$};
  my $markdown = $ARGV =~ m{/Views/Markdown(?:Surface|View|Editor)\.swift$|/(?:UITest|SelfTest)[^/]*\.swift$};
  my $textLink = $ARGV =~ m{/(?:LinkText|MarkdownTable)\.swift$};
  if (!/lint: ok/ && !/^\s*\/\//) {
    my @bad;
    push @bad, "isFlipped must be nonisolated" if /override var isFlipped/ && !/nonisolated/;
    push @bad, "a cursor rect: use a tracking area" if /\b(?:addCursorRect|resetCursorRects)\b/;
    push @bad, "a pointing hand outside a text link" if !$textLink && $ARGV !~ m{/(?:UITest|SelfTest)[^/]*\.swift$} && /\bpointingHand\b|\.pointerStyle\(/;
    if (!$markdown) {
      push @bad, "markdown outside MarkdownSurface" if /\b(?:MarkdownView|MarkdownEditor)\(/;
      push @bad, "a multi-line field: use MarkdownField" if /axis:\s*\.vertical/;
    }
    push @bad, "a call that can prompt for a permission outside Setup" if $ARGV !~ m{/Setup\.swift$} && /\b(?:CGRequestPostEventAccess|CGRequestListenEventAccess|CGRequestScreenCaptureAccess|kAXTrustedCheckOptionPrompt|AXIsProcessTrustedWithOptions)\b|\.post\(tap:|\.postToPid\(/;
    push @bad, "the system pasteboard: use Pasteboard.board" if /\bNSPasteboard\.general\b/;
    push @bad, "the plate color outside HoverPlate" if /\bInk\.plate(?:Pressed)?NS\b/ && $ARGV !~ m{/(?:HoverPlate|Tokens)\.swift$};
    push @bad, "a notification text: use MarkdownLine" if $ARGV =~ m{/NotificationCenter\.swift$} && /\bText\((?:text|notice\.text)\)/;
    if (!$kit && !$tests) {
      push @bad, "a raw color" if /\b(?:NS)?Color\((?:red|white|hue|srgbRed|calibratedRed):/;
      push @bad, "a raw font size" if /\.(?:system|monospacedSystemFont)\((?:size|ofSize):/;
      push @bad, "an SF Symbol by name" if /(?:systemName|systemSymbolName):\s*"/;
      push @bad, "a raw animation" if /\.(?:easeIn|easeOut|easeInOut|linear|spring|smooth)\(duration:/;
      push @bad, "a double-click outside SelectOpen: use opensOnDoubleClick" if /onTapGesture\(count:\s*2/;
      push @bad, "a hover fill on a control: use .hoverPlate" if /\bInk\.hoverFill\b/ && !/Radius\.row/;
    }
    if (@bad) { $count++; my $l = $_; $l =~ s/^\s+//; print "$ARGV:$.: ", join(", ", @bad), ": $l"; }
  }
  close ARGV if eof;
  END { if ($count) { print "FAIL code-lint: $count lines\n"; exit 1 } print "PASS code-lint\n" }'
