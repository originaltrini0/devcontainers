#!/usr/bin/env bash
# Python image tooling: pinned uv, ruff, pytest via pip into the image Python.
# Kept separate from the per-project venv; these are the global smoke-check tools.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

UV_VERSION="${UV_VERSION:-0.13.8}"
RUFF_VERSION="${RUFF_VERSION:-0.17.5}"
PYTEST_VERSION="${PYTEST_VERSION:-9.2.0}"

python3 -m pip install --no-cache-dir --upgrade \
  "uv==${UV_VERSION}" "ruff==${RUFF_VERSION}" "pytest==${PYTEST_VERSION}"

# The base image's pipx py-utils venv ships an older pytest whose shim sits
# ahead of /usr/local/bin on PATH; drop it so the pinned install wins.
rm -f /usr/local/py-utils/bin/pytest /usr/local/py-utils/bin/py.test

# Explicit paths: the stale shim on PATH would otherwise satisfy the check.
uv --version
ruff --version
/usr/local/bin/pytest --version
