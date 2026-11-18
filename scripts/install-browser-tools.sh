#!/usr/bin/env bash
# Pinned Google Chrome for Kilo Code browser automation. Kilo's Playwright
# backend launches channel "chrome", which discovers /opt/google/chrome/chrome
# (system Chrome first, then Edge, then the Playwright-downloaded Chromium), so
# a pinned google-chrome-stable is version-independent of Kilo's bundled
# playwright-core. Debian/Ubuntu only: the Ansible/Fedora base has no apt path
# and the feature fails closed there rather than half-installing. Self-contained
# after sync-features.sh vendors lib.sh next to it, so this file doubles as
# src/browser-tools/install.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHROME_VERSION="$(option_value "${OPTIONS:-}" chrome "${CHROME_VERSION:-158.0.8127.36-1}")"

if [ "$CHROME_VERSION" = "none" ]; then
  exit 0
fi

# The pin is interpolated into an apt version selector; allow only the shape
# Google publishes (NNN.N.NNNN.NN-1) — never shell metacharacters.
case "$CHROME_VERSION" in
  *[!0-9.-]*)
    echo "install-browser-tools.sh: invalid chrome pin: $CHROME_VERSION" >&2
    exit 1
    ;;
esac

command -v apt-get >/dev/null 2>&1 || {
  echo "install-browser-tools.sh: Chrome installs from Google's apt repo; Debian/Ubuntu bases only (this base is unsupported, e.g. the Fedora Ansible image)" >&2
  exit 1
}
detect_arch >/dev/null

pkg_install ca-certificates curl gnupg

# Google's Linux signing key, armored into a dedicated keyring (the sources
# entry trusts that keyring only, never the global trusted-keyring dir). The
# key is served from the same host as the packages, so signed-by alone is
# TOFU: pin the primary fingerprint Google publishes at
# google.com/linuxrepositories (mirrors the AWS_SIGNER_FPR precedent in
# install-cloud-tools.sh). Only the primary is checked; signing subkeys
# rotate periodically and inherit from it.
GOOGLE_LINUX_KEY_FPR="${GOOGLE_LINUX_KEY_FPR:-EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796}"
keyring=/etc/apt/keyrings/google-chrome.gpg
mkdir -p /etc/apt/keyrings
keyfile="$(mktemp)"
trap 'rm -f "$keyfile"' EXIT
curl -fsSL --retry 3 https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor >"$keyfile"
key_fpr="$(gpg --show-keys --with-colons "$keyfile" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [ "$key_fpr" != "$GOOGLE_LINUX_KEY_FPR" ]; then
  echo "install-browser-tools.sh: Google signing key fingerprint mismatch: $key_fpr" >&2
  exit 1
fi
chmod 0644 "$keyfile"
mv "$keyfile" "$keyring"
trap - EXIT
echo "deb [arch=amd64,arm64 signed-by=$keyring] https://dl.google.com/linux/chrome/deb/ stable main" \
  > /etc/apt/sources.list.d/google-chrome.list
apt-get update -qq
# Exact apt version only: a pin Google has pulled from the repo fails here
# rather than silently installing "latest" (same fail-closed policy as gcloud).
# The pin governs the image build only — the repo stays enabled for updates,
# so an in-container `apt upgrade` drifts Chrome off the pin by design.
DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends \
  "google-chrome-stable=${CHROME_VERSION}"
apt-get clean
rm -rf /var/lib/apt/lists/*
# Chrome's deb Depends also supply the shared libraries Playwright's bundled
# Chromium fallback needs, so no extra runtime libs are installed here.

assert_version chrome "Google Chrome ${CHROME_VERSION%-*}" google-chrome --version
# The render check runs as root during feature build, which Chrome only allows
# unsandboxed; --disable-dev-shm-usage matches the flag Playwright passes to
# Kilo at runtime (64 MB /dev/shm default on Docker Desktop).
dom="$(timeout 120 google-chrome --headless --no-sandbox --disable-gpu \
  --disable-dev-shm-usage --dump-dom about:blank 2>/dev/null)" \
  || {
  echo "install-browser-tools.sh: headless Chrome render check failed to run" >&2
  exit 1
}
grep -qF '<html>' <<<"$dom" || {
  echo "install-browser-tools.sh: headless Chrome did not render about:blank" >&2
  exit 1
}
