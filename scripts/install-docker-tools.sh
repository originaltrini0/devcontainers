#!/usr/bin/env bash
# Docker client stack for Docker-outside-of-Docker (DooD): pinned docker CLI,
# compose v2 and buildx talking to the HOST daemon over the socket mount this
# feature declares in its manifest. No dockerd here by design — DinD needs
# --privileged and loses the host layer cache. macOS hosts reach this through
# Docker Desktop's /var/run/docker.sock. Self-contained after sync-features.sh
# vendors lib.sh next to it, so this file doubles as src/docker-tools/install.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

opts="${OPTIONS:-}"
ARCH="$(detect_arch)"
DOCKER_VERSION="$(option_value "$opts" docker "${DOCKER_VERSION:-29.10.0}")"
COMPOSE_VERSION="$(option_value "$opts" compose "${COMPOSE_VERSION:-5.8.0}")"
BUILDX_VERSION="$(option_value "$opts" buildx "${BUILDX_VERSION:-0.39.0}")"
SOCKET_PATH="$(option_value "$opts" socket_path "${SOCKET_PATH:-/var/run/docker-host.sock}")"

# Upstream arch spellings differ per tool: the docker static tarball and
# compose use x86_64/aarch64, buildx uses amd64/arm64. compose ships .sha256
# assets and buildx a checksums.txt, so their digests are pinned per-arch —
# bump the version AND its digest together (a stale digest fails closed).
# The docker static tarball publishes no checksum: pin updates stay manual,
# like the gcloud precedent.
case "$ARCH" in
  amd64)
    docker_arch='x86_64' && buildx_arch='amd64'
    compose_sha='b8840f5008c447f41fce0a57ae3adeab42c89b1eb6e6012524bcabbfb4ffbaf6'
    buildx_sha='5fb31a097304fbf6dd4038649a0decf32c2b9510e4047acd7d68b9d700c46194'
    ;;
  arm64)
    docker_arch='aarch64' && buildx_arch='arm64'
    compose_sha='1a9c918b2fb49b9c87f0018c64b5abd0d30715155e98dc939779fbaee6c414d3'
    buildx_sha='722cdcdfdd6f3fb943fa1ba75102d057feb18ba72aab93b1b0a8cf2b2b48a25f'
    ;;
esac
compose_sha="${COMPOSE_SHA256:-$compose_sha}"
buildx_sha="${BUILDX_SHA256:-$buildx_sha}"

# socketPath/username are interpolated into the generated entrypoint below;
# reject anything that could break out of its quoting at bake time.
case "$SOCKET_PATH" in
  /*) ;;
  *) echo "install-docker-tools.sh: socket_path must be an absolute path: $SOCKET_PATH" >&2 && exit 1 ;;
esac
case "$SOCKET_PATH" in
  *[!A-Za-z0-9._/-]*) echo "install-docker-tools.sh: socket_path has unsafe characters: $SOCKET_PATH" >&2 && exit 1 ;;
esac

if [ "$DOCKER_VERSION" != "none" ] || [ "$COMPOSE_VERSION" != "none" ] || [ "$BUILDX_VERSION" != "none" ]; then
  # socat backs the init forwarding for host sockets this image's group model
  # cannot reuse (root-owned, as on Docker Desktop).
  pkg_install ca-certificates curl socat
fi

plugin_dir=/usr/local/lib/docker/cli-plugins
mkdir -p "$plugin_dir" /usr/local/share

# The static tarball also ships dockerd/containerd — extract only the client
# binary (mirrors the age member-selection pattern); the daemon is the host's.
# --transform is GNU tar, fine on the Debian/Ubuntu-family bases.
if [ "$DOCKER_VERSION" != "none" ]; then
  download_extract "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz" \
    -C /usr/local/bin --transform='s|docker/||' "docker/docker"
fi

# compose v2 and buildx are CLI plugins: outside a cli-plugins dir the
# `docker compose` / `docker buildx` verbs simply do not exist.
if [ "$COMPOSE_VERSION" != "none" ]; then
  download_file "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${docker_arch}" \
    "${plugin_dir}/docker-compose" "$compose_sha"
fi
if [ "$BUILDX_VERSION" != "none" ]; then
  download_file "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${buildx_arch}" \
    "${plugin_dir}/docker-buildx" "$buildx_sha"
fi

# DooD plumbing owned here. Permission model (security-reviewed): the bound
# host socket inode is NEVER chmod'd/chown'd — access comes only from the
# container-local docker group or a socat-forwarded, container-owned socket at
# /var/run/docker.sock. See README "Docker model".
username="${_REMOTE_USER:-vscode}"
[[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] || {
  echo "install-docker-tools.sh: invalid remote user name: $username" >&2
  exit 1
}
if [ "$SOCKET_PATH" != "/var/run/docker.sock" ]; then
  # A missing bind target fails container creation, so seed a placeholder file
  # (the host socket replaces it at create time) and symlink the default client
  # path at it; the symlink resolves as soon as the real socket is bound.
  mkdir -p "$(dirname "$SOCKET_PATH")" /var/run
  [ -e "$SOCKET_PATH" ] || touch "$SOCKET_PATH"
  ln -sf "$SOCKET_PATH" /var/run/docker.sock
fi

init_script=/usr/local/share/docker-tools-init.sh
if [ "$username" = "root" ] || ! getent passwd "$username" > /dev/null 2>&1; then
  echo "install-docker-tools.sh: no non-root user '$username' found; entrypoint will NOT grant socket access to a remote user" >&2
  printf '%s\n' '#!/bin/sh' 'exec "$@"' > "$init_script"
else
  getent group docker > /dev/null 2>&1 || groupadd --system docker
  usermod -aG docker "$username"
  # The feature entrypoint runs in a /bin/sh -c wrapper and _REMOTE_USER exists
  # only at feature-build time, so bake the username and socket path now; the
  # script itself must stay POSIX-sh and non-fatal when no socket is present
  # (e.g. a host without Docker running).
  tee "$init_script" > /dev/null << EOF
#!/bin/sh
# Generated by docker-tools install.sh. Gives the remote user access to the
# bound host socket every start without touching its inode: when the socket's
# GID already matches the container-local docker group, membership is ensured;
# otherwise (root-owned GID 0 as on Docker Desktop, unknown/foreign GID, or a
# groupmod that the running process could not pick up) the client path is
# served by a socat forward to a container-local socket we own.
username="${username}"
socket="${SOCKET_PATH}"
client="/var/run/docker.sock"

sudoIf() {
  if [ "\$(id -u)" -ne 0 ]; then sudo "\$@"; else "\$@"; fi
}

if [ ! -S "\$socket" ]; then
  echo "docker-tools: no daemon socket at \$socket; skipping init" >&2
  exec "\$@"
fi

gid="\$(stat -c '%g' "\$socket" 2>/dev/null)" || exec "\$@"
docker_gid="\$(getent group docker 2>/dev/null | cut -d: -f3)"

if [ "\$socket" = "\$client" ]; then
  # User-supplied socket at the client path (socket_path override with a
  # matching devcontainer.json mount): move the container-local docker group
  # to the socket GID; new exec sessions pick it up. Host inode untouched.
  if [ -n "\$gid" ] && [ "\$gid" != "0" ] && [ "\$docker_gid" != "\$gid" ]; then
    if [ -z "\$docker_gid" ]; then
      sudoIf groupadd -g "\$gid" docker
    elif awk -F: -v g="\$gid" 'BEGIN { f = 0 } \$3 == g { f = 1 } END { exit !f }' /etc/group; then
      sudoIf groupmod -g "\$gid" docker
    else
      echo "docker-tools: gid \$gid already in use; docker access needs sudo or a different socket_path" >&2
    fi
  fi
  id -nG "\$username" 2>/dev/null | grep -qw docker || sudoIf usermod -aG docker "\$username"
  exec "\$@"
fi

if [ "\$gid" != "\$docker_gid" ] || [ "\$docker_gid" = "0" ]; then
  [ -L "\$client" ] && sudoIf rm -f "\$client"
  if [ ! -S "\$client" ]; then
    sudoIf socat "UNIX-LISTEN:\$client,fork,mode=660,user=\$username" "UNIX-CONNECT:\$socket" >/tmp/docker-tools-socat.log 2>&1 &
    i=0
    while [ "\$i" -lt 20 ] && [ ! -S "\$client" ]; do
      sleep 0.1
      i=\$((i + 1))
    done
  fi
fi
id -nG "\$username" 2>/dev/null | grep -qw docker || sudoIf usermod -aG docker "\$username"

# Entry-script chaining: hand off to the container's original command.
exec "\$@"
EOF
fi
chmod 0755 "$init_script"
chown root:root "$init_script"

# Client-only asserts: the build never needs a daemon — `docker compose` and
# `docker buildx` resolve through cli-plugins, so a missing binary or plugin
# fails here rather than in a project's CI.
[ "$DOCKER_VERSION" = "none" ] || assert_version docker "Docker version ${DOCKER_VERSION}" docker --version
[ "$COMPOSE_VERSION" = "none" ] || assert_version compose "Docker Compose version v${COMPOSE_VERSION}" docker compose version
[ "$BUILDX_VERSION" = "none" ] || assert_version buildx "v${BUILDX_VERSION}" docker buildx version
