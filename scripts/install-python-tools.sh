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

uv --version
ruff --version
pytest --version
