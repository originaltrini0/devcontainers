#!/usr/bin/env bash
# Vendor scripts/lib.sh into every feature src/ so each feature stays
# self-contained (the CLI packages only src/). CI runs --check and fails on drift.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# feature<TAB>canonical installer (empty = feature script not written yet)
FEATURES=$'common\tinstall-common-tools.sh\nk8s-tools\t'

printf '%s\n' "$FEATURES" | while IFS=$'\t' read -r feature installer; do
  src_dir="$ROOT/src/$feature"
  for pair in "$ROOT/scripts/lib.sh:$src_dir/lib.sh" ${installer:+"$ROOT/scripts/$installer:$src_dir/install.sh"}; do
    source_file="${pair%%:*}"
    target="${pair#*:}"
    if [ "$CHECK" = "1" ]; then
      if ! cmp -s "$source_file" "$target"; then
        echo "sync-features.sh: $target is out of date; run scripts/sync-features.sh" >&2
        exit 1
      fi
    else
      cp "$source_file" "$target"
      chmod 0755 "$target"
      echo "vendored $(basename "$source_file") into src/$feature/"
    fi
  done
done
