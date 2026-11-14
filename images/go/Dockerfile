# The Go compiler comes from the base tag; only the dev toolchain is baked
# here, so a tool bump is a layer cache key rather than a re-download on every
# container create.
ARG GO_VERSION=1.27
FROM mcr.microsoft.com/devcontainers/go:${GO_VERSION}

# install-go-tools.sh ends with `go version` plus a version check per tool, so
# any missing binary fails the build, not a half-provisioned container.
# TARGETARCH lets the script resolve prebuilt release URLs per build platform.
COPY scripts/ /tmp/devcontainers-scripts/
RUN bash /tmp/devcontainers-scripts/install-go-tools.sh \
 && rm -rf /tmp/devcontainers-scripts
