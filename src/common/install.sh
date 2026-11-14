#!/usr/bin/env bash
# Common org tooling: gh, glab, jq, ripgrep. Self-contained after sync-features.sh
# vendors lib.sh next to it, so this file doubles as features/common/src/install.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCH="$(detect_arch)"
GH_VERSION="$(option_value "${OPTIONS:-}" gh "${GH_VERSION:-2.104.0}")"
GLAB_VERSION="$(option_value "${OPTIONS:-}" glab "${GLAB_VERSION:-1.130.0}")"

# Third-party apt sources baked into base images (e.g. the unsigned yarn repo
# in devcontainers/python) fail the whole `apt-get update` with NO_PUBKEY.
# Successful repos still write their lists, and jq/ripgrep come from the
# distro main repo, so a failing extra repo must not abort the install; the
# install itself (and the version checks below) still fail hard if the real
# repo lists are missing.
apt-get update -qq || true
DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends jq ripgrep
rm -rf /var/lib/apt/lists/*

download_extract "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
  --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_${ARCH}/bin/gh"

# glab releases come from GitLab, not GitHub.
download_extract "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${ARCH}.tar.gz" \
  --strip-components=1 -C /usr/local/bin "bin/glab"

gh --version
glab --version
jq --version
rg --version
