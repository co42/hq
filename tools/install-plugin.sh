#!/bin/zsh
# Installs the hq plugin for every Claude Code session (PLAN.md §7): the marketplace bundled in
# HQ.app, the plugin, and Bash(hq:*) in ~/.claude/settings.json. Run again to update it.
# Undo: claude plugin uninstall hq@hq && claude plugin marketplace remove hq
set -euo pipefail
src=${1:-/Applications/HQ.app/Contents/Resources/Plugin}
claude=$(command -v claude || echo "$HOME/.local/bin/claude")
[[ -f "$src/.claude-plugin/marketplace.json" ]] || { echo "no marketplace at $src: run ./build.sh first"; exit 1; }

# A marketplace added from another copy of HQ.app moves to this one.
known=$(jq -r ".hq.source.path // empty" ~/.claude/plugins/known_marketplaces.json 2>/dev/null || true)
if [[ -n $known && $known != "$src" ]]; then
  "$claude" plugin marketplace remove hq
  known=
fi
if [[ -n $known ]]; then
  "$claude" plugin marketplace update hq
else
  "$claude" plugin marketplace add "$src"
fi
if "$claude" plugin list 2>/dev/null | grep -qE "❯ hq@hq$"; then
  "$claude" plugin update hq@hq
else
  "$claude" plugin install hq@hq --scope user
fi

settings=$HOME/.claude/settings.json
[[ -f $settings ]] || printf '%s\n' '{}' > $settings
if ! jq -e '(.permissions.allow // []) | index("Bash(hq:*)")' $settings >/dev/null; then
  cp $settings $settings.bak-hq
  jq '.permissions.allow = ((.permissions.allow // []) + ["Bash(hq:*)"])' $settings > $settings.tmp-hq
  mv $settings.tmp-hq $settings
fi
echo "hq plugin installed: new Claude sessions report to HQ"
