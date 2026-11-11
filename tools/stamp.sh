#!/bin/zsh
# The release gate's stamp: what tools/check.sh --release checked, so ./build.sh installs only a tree that passed.
# Usage: tools/stamp.sh write     after a green check.sh --release (it calls this)
#        tools/stamp.sh verify    exit 0 when the stamp matches the tree as it is now
set -u
here=${0:A:h:h}
stamp=$HOME/Library/Developer/HQ/release-stamp
cd $here
# Everything that goes into the app: its code, resources and plugin.
hash=$(git ls-files -co --exclude-standard -- Sources HQKit/Sources HQKit/Package.swift Package.swift Info.plist.in Resources Vendor plugin .claude-plugin Icon build.sh \
  | sort | while read -r file; do [[ -f $file ]] && shasum -a 256 "$file"; done | shasum -a 256 | cut -d' ' -f1)
case ${1:-verify} in
  write) print "$hash $(date '+%Y-%m-%d %H:%M')" >| $stamp ;;
  verify)
    [[ -f $stamp ]] || { echo "no release stamp: run tools/check.sh --release"; exit 1 }
    read -r stamped when < $stamp
    [[ $stamped == $hash ]] || { echo "the release stamp ($when) is for another tree: run tools/check.sh --release"; exit 1 } ;;
esac
