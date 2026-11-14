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
# The devcontainer CLI exports options as UPPERCASE env vars and only sets
# $OPTIONS in some runtimes, so check both before the default.
option_value() {
  local opts="$1" key="$2" default="$3" pair env
  for pair in $opts; do
    if [ "${pair%%=*}" = "$key" ]; then
      printf '%s' "${pair#*=}"
      return
    fi
  done
  env="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]' | sed 's/[-.]/_/g')"
  if [ -n "${!env:-}" ]; then
    printf '%s' "${!env}"
    return
  fi
  printf '%s' "$default"
}

# Distro package install across the bases our features land on:
# Debian/Ubuntu (apt), Fedora incl. the Ansible dev-tools image (dnf/
# microdnf/rpm-ostree), plus apk/yum for completeness.
pkg_install() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq || true
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends "$@"
    rm -rf /var/lib/apt/lists/*
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q "$@"
  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y "$@"
  elif command -v rpm-ostree >/dev/null 2>&1; then
    rpm-ostree install "$@"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$@"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q "$@"
  else
    echo "pkg_install: no supported package manager found" >&2
    return 1
  fi
}
