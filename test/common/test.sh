#!/bin/bash
set -e

source dev-container-features-test-lib

GH_VERSION="${GH:-2.104.0}"
GLAB_VERSION="${GLAB:-1.130.0}"

check "gh is pinned" bash -c "gh --version | head -n1 | grep -qF '$GH_VERSION'"
check "glab is pinned" bash -c "glab --version | grep -qF '$GLAB_VERSION'"
check "jq works" bash -c "echo '{\"ok\":true}' | jq -e .ok"
check "ripgrep works" bash -c "printf 'foo\\n' | rg -c foo | grep -qx 1"

reportResults
