#!/usr/bin/env bash
# Common org tooling: gh, glab, jq, ripgrep. Self-contained after sync-features.sh
# vendors lib.sh next to it, so this file doubles as features/common/src/install.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCH="$(detect_arch)"
GH_VERSION="$(option_value "${OPTIONS:-}" gh "${GH_VERSION:-2.104.0}")"
GLAB_VERSION="$(option_value "${OPTIONS:-}" glab "${GLAB_VERSION:-1.130.0}")"
NODE_VERSION="$(option_value "${OPTIONS:-}" node "${NODE_VERSION:-26.13.1}")"

# jq/ripgrep come from the distro repo on every supported base. The Ansible
# upstream image is Fedora (dnf), the rest are Debian/Ubuntu (apt); pkg_install
# in lib.sh dispatches and tolerates broken third-party apt sources — the
# version checks below still fail hard if a tool is missing.
pkg_install jq ripgrep

download_extract "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
  --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_${ARCH}/bin/gh"

# glab releases come from GitLab, not GitHub.
download_extract "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${ARCH}.tar.gz" \
  --strip-components=1 -C /usr/local/bin "bin/glab"

# Kilo Code requirement: local MCP servers (`npx -y <pkg>`) and the
# `npx --yes @kilocode/cli` launcher need node/npm/npx in the container; none
# of our four bases ship them (verified by docker run on base/python/go/ansible).
# nodejs.org tarballs use x64/arm64, not the amd64/arm64 of detect_arch.
if [ "$NODE_VERSION" != "none" ]; then
  NODE_ARCH="$( [ "$ARCH" = amd64 ] && printf 'x64' || printf 'arm64' )"
  download_extract "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" \
    --strip-components=1 -C /usr/local
  # Fedora (ansible dev-tools image) does not ship libatomic, which the
  # official glibc node binary links against; the deb name is libatomic1.
  if command -v ldconfig >/dev/null 2>&1 && ! ldconfig -p | grep -q 'libatomic\.so\.1'; then
    pkg_install libatomic >/dev/null 2>&1 || pkg_install libatomic1
  fi
fi

gh --version
glab --version
jq --version
rg --version
if [ "$NODE_VERSION" != "none" ]; then
  assert_version node "v${NODE_VERSION}" node --version
  npm --version
  npx --version
fi

# HTE root CA (public trust anchor, same cert step-ca exports to ~/.step/certs
# on the host). Baked into the image so curl/git/python and any Node tool via
# NODE_EXTRA_CA_CERTS verify lab.howto.engineer certs without host mounts —
# a bind mount would fail container start wherever the source dir is absent,
# including CI runners. Root CA rotation therefore needs a feature release.
HTE_CA_DIR=/usr/local/share/hte-ca
mkdir -p "$HTE_CA_DIR"
cat > "$HTE_CA_DIR/hte-root-ca.crt" <<'CAEOF'
-----BEGIN CERTIFICATE-----
MIIBqzCCATKgAwIBAgIQTtA3833J+x5TR+PqaMd3pTAKBggqhkjOPQQDAzAWMRQw
EgYDVQQDEwtIVEUgUm9vdCBDQTAeFw0yNjAyMTMyMDU4MDBaFw0zNjAyMTEyMDU4
MDBaMBYxFDASBgNVBAMTC0hURSBSb290IENBMHYwEAYHKoZIzj0CAQYFK4EEACID
YgAEcf8nW2HINYkOUc4RIIR9qsCz615IDgw5IXNLTzIq4/YvC/jK4wxfW4bCemMg
Ttf+cqzv2cesHWQd6NRoH4ddMaiMfdpTcLm5zziS415TAILI8NHSihqXnVkK5D2g
7UYOo0UwQzAOBgNVHQ8BAf8EBAMCAQYwEgYDVR0TAQH/BAgwBgEB/wIBATAdBgNV
HQ4EFgQUOQTHtA5iOSeAesT76hkfTEicV2owCgYIKoZIzj0EAwMDZwAwZAIweMY2
rThMSKmFJ+nPgGXJW+Bi+zyfcbTMuLRZUN9fr5lNFEtF2SDHjfAc6LrPB6RpAjBZ
HZc2mTbBDnlkkx3Y95AFdwXhQJMgbAXd744eLbHHtkiw9Jd4i2enpE3DOg66AYQ=
-----END CERTIFICATE-----
CAEOF

if command -v update-ca-certificates >/dev/null 2>&1; then
  cp "$HTE_CA_DIR/hte-root-ca.crt" /usr/local/share/ca-certificates/hte-root-ca.crt
  update-ca-certificates >/dev/null
  bundle=/etc/ssl/certs/ca-certificates.crt
elif command -v update-ca-trust >/dev/null 2>&1; then
  cp "$HTE_CA_DIR/hte-root-ca.crt" /etc/pki/ca-trust/source/anchors/hte-root-ca.crt
  update-ca-trust extract
  bundle=/etc/pki/tls/certs/ca-bundle.crt
else
  echo "install-common-tools: no distro trust updater found" >&2
  exit 1
fi

# VS Code/Kilo run on Node builds that ignore the distro store on Linux, and
# node exits at startup if NODE_EXTRA_CA_CERTS is missing — ship the bundle
# plus the HTE CA at that exact path.
cat "$bundle" "$HTE_CA_DIR/hte-root-ca.crt" > "$HTE_CA_DIR/node-ca.crt"
