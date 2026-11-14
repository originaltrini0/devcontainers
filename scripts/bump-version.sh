#!/usr/bin/env bash
# Keep the release version in lockstep across feature manifests, template
# refs, and the README. Tool pins are NOT touched here — Renovate owns those.
#
# Usage:
#   bump-version.sh X.Y.Z    rewrite all owned refs to X.Y.Z (then commit+tag)
#   bump-version.sh --check  CI: assert everything already agrees

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Matches ghcr.io/originaltrini0/devcontainers/<name>:<X.Y.Z> in any file.
REF_RE='(ghcr\.io/originaltrini0/devcontainers/(common|k8s-tools|python|go):)[0-9]+\.[0-9]+\.[0-9]+'
VER_RE='^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$'

check() {
  local version='' fail=0 v
  for f in src/*/devcontainer-feature.json; do
    v="$(jq -r '.version' "$f")"
    if [ -z "$version" ]; then version="$v"; elif [ "$version" != "$v" ]; then
      echo "drift: $f version $v != $version" >&2; fail=1
    fi
  done
  [ -n "$version" ] || { echo "no feature manifests found" >&2; exit 1; }
  # Template image refs for python/go must match the same release line.
  while IFS= read -r ref; do
    v="${ref##*:}"
    if [ "$v" != "$version" ]; then
      echo "drift: template image ref $ref != feature version $version" >&2; fail=1
    fi
  done < <(grep -rhoE 'ghcr\.io/originaltrini0/devcontainers/(python|go):[0-9]+\.[0-9]+\.[0-9]+' templates/ || true)
  # Feature refs must too.
  while IFS= read -r ref; do
    v="${ref##*:}"
    if [ "$v" != "$version" ]; then
      echo "drift: template feature ref $ref != $version" >&2; fail=1
    fi
  done < <(grep -rhoE 'ghcr\.io/originaltrini0/devcontainers/(common|k8s-tools):[0-9]+\.[0-9]+\.[0-9]+' templates/ README.md || true)
  if [ "$fail" = 0 ]; then
    echo "bump-version.sh: consistent at $version"
  fi
  return "$fail"
}

if [ "${1:-}" = "--check" ]; then
  check
  exit $?
fi

version="${1:-}"
[[ "$version" =~ $VER_RE ]] || { echo "usage: bump-version.sh X.Y.Z | --check" >&2; exit 2; }

# Never move a release line backwards; tags are the publish trigger.
if git tag -l 'v*' | grep -qx "v$version"; then
  echo "tag v$version already exists" >&2; exit 1
fi
latest="$(git tag -l 'v*' | sed 's/^v//' | sort -V | tail -n1 || true)"
if [ -n "$latest" ] && [ "$(printf '%s\n%s\n' "$version" "$latest" | sort -V | head -n1)" = "$version" ]; then
  echo "$version must be greater than the current tag v$latest" >&2; exit 1
fi

check || echo "bump-version.sh: overwriting an inconsistent state" >&2

# BSD sed takes -i's suffix positionally; temp+mv is portable to macOS.
in_place() { # <sed-script> <file>
  sed -E "$1" "$2" > "$2.bump.tmp" && mv "$2.bump.tmp" "$2"
}
for f in src/common/devcontainer-feature.json src/k8s-tools/devcontainer-feature.json; do
  in_place "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$version\"/" "$f"
done
grep -rlE "$REF_RE" templates README.md | while IFS= read -r f; do
  in_place "s#$REF_RE#\1$version#g" "$f"
done

cat <<EOF

Version line is now $version. Release checklist:
  1. Re-run lockfiles: devcontainer up --workspace-folder templates/python \
       --remove-existing-container (or per project after migration)
  2. git add -A && git commit -m "release: $version" && git tag v$version
  3. git push && git push origin v$version   # CI builds, publishes, aliases
  4. First release of a NEW package (go, k8s-tools): toggle its GHCR
     visibility to public in the org settings UI — workflow-created packages
     default to private.
  Rollback: revert project refs to the previous exact tag + lockfile.
EOF
