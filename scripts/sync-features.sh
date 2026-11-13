#!/usr/bin/env bash
# Vendor scripts/lib.sh into every feature src/ so each feature stays
# self-contained (the CLI packages only src/). CI runs --check and fails on drift.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

for src_dir in "$ROOT"/features/*/src; do
  feature="$(basename "$(dirname "$src_dir")")"
  target="$src_dir/lib.sh"
  if [ "$CHECK" = "1" ]; then
    if ! cmp -s "$ROOT/scripts/lib.sh" "$target"; then
      echo "sync-features.sh: $target is out of date; run scripts/sync-features.sh" >&2
      exit 1
    fi
  else
    cp "$ROOT/scripts/lib.sh" "$target"
    echo "vendored lib.sh into features/$feature/src/"
  fi
done
