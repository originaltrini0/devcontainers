#!/usr/bin/env bash
# Go dev toolchain, image-build-time installs (layer cache key, not per-create
# downloads). Run from a Dockerfile that has the Go compiler on PATH.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCH="${TARGETARCH:-$(detect_arch)}"
GOLANGCI_LINT_VERSION="${GOLANGCI_LINT_VERSION:-2.15.0}"

# golangci-lint ships a prebuilt binary; go install would burn minutes.
download_extract "https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${ARCH}.tar.gz" \
  --strip-components=1 -C /usr/local/bin "golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${ARCH}/golangci-lint"

export GOBIN=/usr/local/bin GOFLAGS=-trimpath
go install "golang.org/x/tools/gopls@v0.24.0"
go install "github.com/go-delve/delve/cmd/dlv@v1.27.2"
go install "honnef.co/go/tools/cmd/staticcheck@v0.8.2"
go install "mvdan.cc/gofumpt@v0.12.0"
go install "golang.org/x/tools/cmd/goimports@v0.52.0"
go install "golang.org/x/vuln/cmd/govulncheck@v1.9.0"
go install "github.com/rakyll/gotest@v0.0.7"
go install "github.com/air-verse/air@v1.67.4"

go version
gopls version
dlv version
staticcheck --version
gofumpt --version
govulncheck -test.version
air --version
golangci-lint --version
