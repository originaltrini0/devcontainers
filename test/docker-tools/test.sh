#!/bin/bash
set -e

source dev-container-features-test-lib

DOCKER_VERSION="${DOCKER:-29.10.0}"
COMPOSE_VERSION="${COMPOSE:-5.8.0}"
BUILDX_VERSION="${BUILDX:-0.39.0}"

# Here-string match, never a pipe: `cmd | grep -q` races SIGPIPE against the
# writer under pipefail (buildx exit 141).

if [ "${DOCKER_VERSION}" = "none" ]; then
  check "docker skipped when none" bash -c "! command -v docker"
else
  check "docker is pinned" bash -c "grep -qF 'Docker version ${DOCKER_VERSION}' <<< \"\$(docker --version 2>&1)\""
fi

if [ "${COMPOSE_VERSION}" = "none" ]; then
  check "compose skipped when none" bash -c "! docker compose version"
else
  check "compose is pinned" bash -c "grep -qF 'Docker Compose version v${COMPOSE_VERSION}' <<< \"\$(docker compose version 2>&1)\""
fi

if [ "${BUILDX_VERSION}" = "none" ]; then
  check "buildx skipped when none" bash -c "! docker buildx version"
else
  check "buildx is pinned" bash -c "grep -qF 'v${BUILDX_VERSION}' <<< \"\$(docker buildx version 2>&1)\""
fi

# Proves the DooD mount + install-time symlink end to end on hosted runners
# (the GitHub-hosted runner provides /var/run/docker.sock for the bind source).
check "host socket exposed at default client path" bash -c 'test -S /var/run/docker.sock'

reportResults
