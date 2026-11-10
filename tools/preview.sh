#!/bin/zsh
# Opens the test copy in front, on a copy of your store and vault, to try a build before it's released.
# Your HQ and your notes stay as they are: the preview reads and writes only /tmp/HQ-preview*. It runs
# beside your own HQ; quit it from its menu (HQ › Quit) when you're done.
# Usage: tools/preview.sh              a fresh copy of your data
#        tools/preview.sh --keep       the last preview's data, as you left it
#        tools/preview.sh hq <command> hq on the preview: tools/preview.sh hq task show T-264
set -u
app="${HQ_APP:-$HOME/Library/Developer/HQ/HQ.app}"
store=/tmp/HQ-preview.store
vault=/tmp/HQ-preview-vault
log=/tmp/HQ-preview.log
notes="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes"
[[ -x $app/Contents/MacOS/HQ ]] || { print "preview: no test copy. Run ./build.sh --dev first"; exit 1 }

# hq on the preview never starts one (it would open without the vault copy): it talks to the open preview only.
if [[ ${1:-} == hq ]]; then
  shift
  APP_STORE=$store HQ_VAULT=$vault exec "$app/Contents/MacOS/HQ" "$@" --no-launch
fi

if [[ ${1:-} != --keep || ! -f $store ]]; then
  if [[ -S $store.sock ]] && APP_STORE=$store HQ_VAULT=$vault "$app/Contents/MacOS/HQ" status --no-launch >/dev/null 2>&1; then
    print "preview: one is still open. Quit it (HQ › Quit in the preview's menu), then run this again"
    exit 1
  fi
  rm -f $store $store-shm $store-wal $store.sock $log
  rm -rf $vault $store.d && mkdir -p $vault $store.d
  support="$HOME/Library/Application Support/HQ"
  sqlite3 "$support/HQ.store" ".backup $store"
  # Its notifications, GitHub's and Slack's last answers and the tasks' history, as your HQ has them.
  for file in notifications.json github.json slack.json task-edits.jsonl; do [[ -f $support/$file ]] && cp "$support/$file" $store.d/; done
  cp -R "$notes/hq" $vault/
fi
# GitHub live, read-only: the PRs' states as they are (a test copy otherwise uses fixtures).
open -n "$app" --env APP_STORE=$store --env HQ_VAULT=$vault --env HQ_FOREGROUND=1 --env HQ_GITHUB=live --stdout $log --stderr $log --args -ApplePersistenceIgnoreState YES
print "preview: the test copy is open on a copy of your data (store $store, vault $vault)"
