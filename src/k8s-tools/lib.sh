#!/usr/bin/env bash
# Shared installer helpers. Vendored into features/*/src/ by sync-features.sh;
# do not edit the copies.

set -euo pipefail

detect_arch() {
  local arch="${TARGETARCH:-$(uname -m)}"
  case "$arch" in
    amd64 | x86_64) printf 'amd64' ;;
    arm64 | aarch64) printf 'arm64' ;;
    *)
      echo "lib.sh: unsupported architecture: $arch" >&2
      return 1
      ;;
  esac
}

sha256_of() { sha256sum "$1" | awk '{print $1}'; }

# download_file URL DEST [SHA256]
# The checksum is optional because not every upstream publishes one; where a
# pin does, pass it via the corresponding *_SHA256 option.
download_file() {
  local url="$1" dest="$2" expected="${3:-}"
  curl -fsSL --retry 3 "$url" -o "$dest"
  if [ -n "$expected" ]; then
    local actual
    actual="$(sha256_of "$dest")"
    if [ "$actual" != "$expected" ]; then
      echo "lib.sh: checksum mismatch for $url (got $actual)" >&2
      return 1
    fi
  fi
  chmod 0755 "$dest"
}

# download_extract URL [TAR ARGS...] — pipe an archive release straight into tar.
download_extract() {
  local url="$1"
  shift
  curl -fsSL --retry 3 "$url" | tar -xz "$@"
}

add_safe_directory() {
  local dir="${1:?usage: add_safe_directory DIR}"
  git config --global --add safe.directory "$dir"
}

# option_value "key=value ..." KEY DEFAULT — resolve a feature option.
option_value() {
  local opts="$1" key="$2" default="$3" pair
  for pair in $opts; do
    if [ "${pair%%=*}" = "$key" ]; then
      printf '%s' "${pair#*=}"
      return
    fi
  done
  printf '%s' "$default"
}
