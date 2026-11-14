# Global ARG must precede FROM — an ARG after FROM is a no-op for the base tag.
ARG PYTHON_VERSION=3.13
FROM mcr.microsoft.com/devcontainers/python:1-${PYTHON_VERSION}-bookworm

# install-python-tools.sh ends with `uv --version` / `ruff --version` /
# `pytest --version`, so a missing binary fails the build.
COPY scripts/ /tmp/devcontainers-scripts/
RUN bash /tmp/devcontainers-scripts/install-python-tools.sh \
 && rm -rf /tmp/devcontainers-scripts
