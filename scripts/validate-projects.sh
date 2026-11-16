#!/usr/bin/env bash
# Allowlist check for devcontainer refs — a small contract, not a manifest.
# Asserts every image/feature ref in each scanned devcontainer.json belongs to
# the sanctioned stack set and (unless --allow-missing/--offline) that our own
# pinned ghcr tags actually exist in the registry.
#
# Usage: validate-projects.sh [--dirs DIR [DIR...]] [--allow-missing] [--offline]
#   --dirs           workspace roots containing */.devcontainer/devcontainer.json
#                    (default: $HOME/code/projects and this repo's templates/)
#   --allow-missing  our ghcr refs may be unpublished (PRs before a release)
#   --offline        skip registry existence checks entirely

set -euo pipefail

ALLOW_MISSING=0
OFFLINE=0
DIRS=()
args=("$@")
i=0
while [ "$i" -lt "${#args[@]}" ]; do
  case "${args[$i]}" in
    --allow-missing) ALLOW_MISSING=1 ;;
    --offline) OFFLINE=1 ;;
    --dirs)
      i=$((i + 1))
      while [ "$i" -lt "${#args[@]}" ] && [[ "${args[$i]}" != --* ]]; do
        DIRS+=("${args[$i]}")
        i=$((i + 1))
      done
      continue ;;
    *) echo "validate-projects.sh: unknown argument ${args[$i]}" >&2; exit 2 ;;
  esac
  i=$((i + 1))
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "${#DIRS[@]}" -gt 0 ] || DIRS=("$HOME/code/projects" "$ROOT/templates")

command -v python3 > /dev/null || { echo "validate-projects.sh: python3 is required" >&2; exit 2; }

# devcontainer.json is JSONC; strip // comments that are outside strings.
parse_refs() {
  python3 - "$1" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'"[^"]*"|//[^\n]*',
              lambda m: m.group(0) if m.group(0).startswith('"') else '', text)
data = json.loads(text)
if data.get("image"):
    print(data["image"])
for ref in (data.get("features") or {}):
    print(ref)
PY
}

# Owned refs must be exact X.Y.Z — never major/latest aliases (reproducibility).
OURS='^ghcr\.io/originaltrini0/devcontainers/(python|go|common|k8s-tools|terraform-tools|cloud-tools):(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$'
ALLOWED_UPSTREAM=(
  '^mcr\.microsoft\.com/devcontainers/base:ubuntu$'
  '^ghcr\.io/ansible/community-ansible-dev-tools:v[0-9]+\.[0-9]+\.[0-9]+$'
)
# Local feature paths only appear in CI's rewritten throwaway copies.
LOCAL='^(\.{1,2}/|/).*'

fail=0
checked=0
for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || { echo "skip missing dir $dir" >&2; continue; }
  while IFS= read -r cfg; do
    case "$cfg" in */.ansible/collections/*) continue ;; esac
    refs="$(parse_refs "$cfg")"
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      checked=$((checked + 1))
      if [[ "$ref" =~ $LOCAL ]]; then
        continue
      fi
      if [[ "$ref" =~ $OURS ]]; then
        owner=ours
      else
        owner=upstream
        ok=0
        for pattern in "${ALLOWED_UPSTREAM[@]}"; do
          [[ "$ref" =~ $pattern ]] && ok=1
        done
        if [ "$ok" = "0" ]; then
          echo "DENY  $cfg  $ref (not in the allowed stack set)" >&2
          fail=1
          continue
        fi
      fi
      [ "$owner" = ours ] || continue
      [ "$OFFLINE" = 1 ] && continue
      if [ "$ALLOW_MISSING" = 1 ]; then
        docker manifest inspect "$ref" > /dev/null 2>&1 \
          || echo "note  $ref not published yet (allowed on this run)"
      elif ! docker manifest inspect "$ref" > /dev/null 2>&1; then
        echo "MISS  $cfg  $ref (pinned tag not found in ghcr)" >&2
        fail=1
      fi
    done <<< "$refs"
  # maxdepth 6: grouped library repos (terraform-modules/<repo>/.devcontainer)
  # nest one level deeper than flat projects. .kilo holds transient agent
  # worktree state, not project configs, so it is pruned from the sweep.
  done < <(find "$dir" -mindepth 3 -maxdepth 6 -path '*/.kilo' -prune -o -path '*/.devcontainer/devcontainer.json' -print | sort)
done

echo "validate-projects.sh: checked $checked refs, $([ "$fail" = 0 ] && echo OK || echo FAILURES)"
exit "$fail"
