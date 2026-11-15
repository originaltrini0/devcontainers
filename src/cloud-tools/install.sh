#!/usr/bin/env bash
# Cloud provider CLIs (gcloud/aws/az/pwsh). Sole owner of these pins; project
# configs override per-option. Composable with any stack (e.g. terraform-tools
# + cloud-tools for GCP roots). Self-contained after sync-features.sh vendors
# lib.sh next to it, so this file doubles as src/cloud-tools/install.sh.
# Debian/Ubuntu bases only (the gcloud pin ships via apt); templates use
# base:ubuntu. No engine or stack tooling lives here — see terraform-tools /
# k8s-tools for that.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

opts="${OPTIONS:-}"
ARCH="$(detect_arch)"
AWS_VERSION="$(option_value "$opts" aws "${AWS_VERSION:-2.40.3}")"
AZ_VERSION="$(option_value "$opts" az "${AZ_VERSION:-2.92.0}")"
PWSH_VERSION="$(option_value "$opts" pwsh "${PWSH_VERSION:-7.7.0}")"
GCLOUD_VERSION="$(option_value "$opts" gcloud "${GCLOUD_VERSION:-593.0.0}")"
# AWS CLI v2 signing key (keyserver.ubuntu.com, fetched over HTTPS below).
AWS_SIGNER_FPR="${AWS_SIGNER_FPR:-FB5DB77FD5C118B80511ADA8A6310ACC4672475C}"

# base:ubuntu ships no python3 at all: aws installs one, and the az standalone
# tarball refuses to run without AZ_PYTHON (see the wrapper below).
need_pkgs=0
[ "$AWS_VERSION" = "none" ] && [ "$AZ_VERSION" = "none" ] && [ "$GCLOUD_VERSION" = "none" ] || need_pkgs=1
[ "$need_pkgs" = 1 ] && pkg_install python3 unzip gnupg ca-certificates

# AWS CLI v2: versioned zip + detached .sig from the first-party host. The
# GitHub "latest" URL is mutable; the versioned one keeps the pin real.
if [ "$AWS_VERSION" != "none" ]; then
  case "$ARCH" in
    amd64) aws_arch='x86_64' ;;
    arm64) aws_arch='aarch64' ;;
  esac
  aws_zip="https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}-${AWS_VERSION}.zip"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' EXIT
  download_file "$aws_zip" "$tmp/aws.zip" "${AWS_SHA256:-}"
  curl -fsSL --retry 3 "$aws_zip.sig" -o "$tmp/aws.zip.sig"
  # gpg --homedir refuses a missing dir, so create it first. Import failure is
  # caught by the verify step. Here-string match, never a pipe (lib.sh SIGPIPE
  # note).
  mkdir -p "$tmp/gn"
  chmod 700 "$tmp/gn"
  curl -fsSL --retry 3 \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${AWS_SIGNER_FPR}" \
    | gpg --homedir "$tmp/gn" --import >/dev/null 2>&1
  if ! aws_sig="$(gpg --homedir "$tmp/gn" --verify "$tmp/aws.zip.sig" "$tmp/aws.zip" 2>&1)" \
    || ! grep -qF 'Good signature' <<< "$aws_sig"; then
    echo "install-cloud-tools.sh: aws-cli $AWS_VERSION zip failed signature check: $aws_sig" >&2
    exit 1
  fi
  ( cd "$tmp" && unzip -q aws.zip && ./aws/install >/dev/null )
  trap - EXIT
  rm -rf "$tmp"
fi

# Azure CLI: standalone tarball from the GitHub release (the MS apt repo is
# unpinned). Flat layout (bin/az + libexec/); the binary runs on the host
# interpreter, so the PATH entry is a wrapper that pins AZ_PYTHON for every
# invocation — verified on resolute, where python3 is not baked.
if [ "$AZ_VERSION" != "none" ]; then
  case "$ARCH" in
    amd64) az_arch='x86_64' ;;
    arm64) az_arch='arm64' ;;
  esac
  mkdir -p /opt/azure-cli
  download_extract "https://github.com/Azure/azure-cli/releases/download/azure-cli-${AZ_VERSION}/azure-cli-${AZ_VERSION}-linux-${az_arch}.tar.gz" \
    -C /opt/azure-cli
  chmod 0755 /opt/azure-cli/bin/az
  printf '%s\n' '#!/bin/sh' 'for p in /usr/bin/python3 /usr/local/bin/python3; do' \
    '[ -x "$p" ] && exec env AZ_PYTHON="$p" /opt/azure-cli/bin/az "$@"' 'done' \
    'echo "az: no python3 found for AZ_PYTHON" >&2; exit 1' > /usr/local/bin/az
  chmod 0755 /usr/local/bin/az
fi

# PowerShell: self-contained tarball (bundles ICU — verified on resolute).
if [ "$PWSH_VERSION" != "none" ]; then
  case "$ARCH" in
    amd64) pwsh_arch='x64' ;;
    arm64) pwsh_arch='arm64' ;;
  esac
  mkdir -p /opt/powershell/7
  download_extract "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-${pwsh_arch}.tar.gz" \
    -C /opt/powershell/7
  chmod 0755 /opt/powershell/7/pwsh
  ln -sf /opt/powershell/7/pwsh /usr/local/bin/pwsh
fi

# Google Cloud SDK ships apt-only. Google publishes no dists for current
# Ubuntu releases (resolute/noble 404 on 2026-11-15), so pick the newest dist
# whose Release actually resolves and soft-match the pin against madison —
# exact-version installs are the only way to defeat "latest" here.
if [ "$GCLOUD_VERSION" != "none" ]; then
  command -v apt-get > /dev/null || {
    echo "install-cloud-tools.sh: gcloud requires a Debian/Ubuntu base" >&2
    exit 1
  }
  . /etc/os-release
  keyring=/usr/share/keyrings/cloud.google.gpg
  curl -fsSL --retry 3 https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o "$keyring"
  gc_codename=''
  for c in "${VERSION_CODENAME:-}" noble jammy; do
    [ -n "$c" ] || continue
    if curl -fsIL "https://packages.cloud.google.com/apt/dists/cloud-sdk-$c/Release" > /dev/null 2>&1; then
      gc_codename="$c"
      break
    fi
  done
  [ -n "$gc_codename" ] || {
    echo "install-cloud-tools.sh: no usable cloud-sdk apt dist found" >&2
    exit 1
  }
  echo "deb [signed-by=$keyring] https://packages.cloud.google.com/apt cloud-sdk-$gc_codename main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
  pkg_install apt-utils
  apt-get update -qq
  gc_pkg="$(apt-cache madison google-cloud-cli \
    | awk -F'|' -v v="$GCLOUD_VERSION" '{ gsub(/ /, "", $2); if ($2 ~ "^"v"([-.]|$)") { print $2; exit } }')"
  [ -n "$gc_pkg" ] || {
    echo "install-cloud-tools.sh: gcloud $GCLOUD_VERSION not in apt dist $gc_codename; newest available:" >&2
    apt-cache madison google-cloud-cli | head -n 5 >&2
    exit 1
  }
  DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends "google-cloud-cli=$gc_pkg"
fi

# Fail the build on any missing/mismatched binary (assert_version from lib.sh).
[ "$AWS_VERSION" = "none" ] || assert_version aws "aws-cli/$AWS_VERSION" aws --version
# az prints JSON; match the versioned key so core/telemetry lines cannot mask drift.
[ "$AZ_VERSION" = "none" ] || assert_version az "\"azure-cli\": \"$AZ_VERSION\"" az version
[ "$PWSH_VERSION" = "none" ] || assert_version pwsh "$PWSH_VERSION" pwsh --version
# gcloud reports drift loudly, but an apt dist that silently drops a version
# while keeping the epoch still needs the explicit needle check.
[ "$GCLOUD_VERSION" = "none" ] || assert_version gcloud "Google Cloud SDK $GCLOUD_VERSION" gcloud version
