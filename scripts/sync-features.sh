#!/usr/bin/env bash
# Vendor scripts/lib.sh (plus each feature's canonical installer) into every
# feature src/ so each feature stays self-contained (the CLI packages only
# src/). CI runs --check and fails on drift. The feature list is derived from
# src/ so a new feature can never slip past the gate; the installer convention
# is scripts/install-<feature>-tools.sh.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

for src_dir in "$ROOT"/src/*/; do
  feature="$(basename "$src_dir")"
  installer=""
  for candidate in "install-${feature}.sh" "install-${feature}-tools.sh"; do
    [ -f "$ROOT/scripts/$candidate" ] && installer="$ROOT/scripts/$candidate" && break
  done
  if [ -z "$installer" ] && [ -f "$src_dir/install.sh" ]; then
    echo "sync-features.sh: $src_dir install.sh has no canonical scripts/install-${feature}{,-tools}.sh" >&2
    exit 1
  fi
  pairs="$ROOT/scripts/lib.sh:$src_dir/lib.sh"
  [ -f "$installer" ] && pairs="$pairs $installer:$src_dir/install.sh"
  for pair in $pairs; do
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
