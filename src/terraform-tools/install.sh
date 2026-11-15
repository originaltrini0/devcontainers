#!/usr/bin/env bash
# Terraform/OpenTofu CLI + ecosystem tooling. Sole owner of these pins;
# project configs override per-option. Self-contained after sync-features.sh
# vendors lib.sh next to it, so this file doubles as src/terraform-tools/install.sh.
# No cloud CLIs here — gcloud/aws/az/pwsh belong to the cloud-tools feature.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

opts="${OPTIONS:-}"
ARCH="$(detect_arch)"
# Flavor resolves through option_value so the CLI-exported FLAVOR env channel
# works (OPTIONS is not guaranteed) — but the key is `flavor`, so an ambient
# TERRAFORM/TOFU env var can never switch engines.
FLAVOR="$(option_value "$opts" flavor terraform)"
VERSION="$(option_value "$opts" version "${VERSION:-1.17.2}")"
TFLINT_VERSION="$(option_value "$opts" tflint "${TFLINT_VERSION:-0.66.0}")"
TERRAFORM_DOCS_VERSION="$(option_value "$opts" terraform-docs "${TERRAFORM_DOCS_VERSION:-0.25.1}")"
TERRAFORM_LS_VERSION="$(option_value "$opts" terraform-ls "${TERRAFORM_LS_VERSION:-0.39.1}")"
TRIVY_VERSION="$(option_value "$opts" trivy "${TRIVY_VERSION:-0.76.2}")"
PRE_COMMIT_VERSION="$(option_value "$opts" pre-commit "${PRE_COMMIT_VERSION:-4.7.0}")"

# Zipped binaries (terraform, terraform-ls, tflint) need unzip on the base.
pkg_install unzip

# The engine: exactly one CLI providing `terraform`-compatible commands.
# 'none' is an explicit skip (e.g. a docs-only module workspace).
if [ "$VERSION" != "none" ]; then
  case "$FLAVOR" in
    terraform)
      download_unzip "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${ARCH}.zip" \
        /usr/local/bin "${TERRAFORM_SHA256:-}"
      ;;
    tofu)
      download_extract "https://github.com/opentofu/opentofu/releases/download/v${VERSION}/tofu_${VERSION}_linux_${ARCH}.tar.gz" \
        -C /usr/local/bin tofu
      ;;
    *)
      echo "install-terraform-tools.sh: unknown flavor '$FLAVOR' (want terraform|tofu)" >&2
      exit 1
      ;;
  esac
fi

if [ "$TFLINT_VERSION" != "none" ]; then
  # tflint zips omit the leading v and version in the asset name.
  download_unzip "https://github.com/Terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${ARCH}.zip" \
    /usr/local/bin "${TFLINT_SHA256:-}"
fi

if [ "$TERRAFORM_DOCS_VERSION" != "none" ]; then
  download_file "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${ARCH}.tar.gz" \
    /tmp/terraform-docs.tar.gz "${TERRAFORM_DOCS_SHA256:-}"
  tar -xzf /tmp/terraform-docs.tar.gz -C /usr/local/bin terraform-docs
  chmod 0755 /usr/local/bin/terraform-docs
  rm -f /tmp/terraform-docs.tar.gz
fi

if [ "$TERRAFORM_LS_VERSION" != "none" ]; then
  download_unzip "https://releases.hashicorp.com/terraform-ls/${TERRAFORM_LS_VERSION}/terraform-ls_${TERRAFORM_LS_VERSION}_linux_${ARCH}.zip" \
    /usr/local/bin "${TERRAFORM_LS_SHA256:-}"
fi

if [ "$TRIVY_VERSION" != "none" ]; then
  # trivy asset names are Linux-64bit / Linux-ARM64, unlike every other pin.
  case "$ARCH" in
    amd64) trivy_arch='64bit' ;;
    arm64) trivy_arch='ARM64' ;;
  esac
  download_extract "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${trivy_arch}.tar.gz" \
    -C /usr/local/bin trivy
fi

if [ "$PRE_COMMIT_VERSION" != "none" ]; then
  # base:ubuntu is PEP 668 externally-managed; bare pip is refused there, so
  # pre-commit gets its own venv symlinked into PATH. Ubuntu ships venv's
  # ensurepip separately, hence python3-venv.
  pkg_install python3 python3-venv
  python3 -m venv /opt/pre-commit
  "/opt/pre-commit/bin/pip" install --quiet --no-cache-dir "pre-commit==${PRE_COMMIT_VERSION}"
  ln -sf /opt/pre-commit/bin/pre-commit /usr/local/bin/pre-commit
fi

# Fail the build on any missing/mismatched binary (assert_version from lib.sh).
if [ "$VERSION" != "none" ]; then
  case "$FLAVOR" in
    terraform) assert_version terraform "v$VERSION" terraform version ;;
    tofu) assert_version tofu "v$VERSION" tofu version ;;
  esac
fi
[ "$TFLINT_VERSION" = "none" ] || assert_version tflint "$TFLINT_VERSION" tflint --version
[ "$TERRAFORM_DOCS_VERSION" = "none" ] || assert_version terraform-docs "v$TERRAFORM_DOCS_VERSION" terraform-docs --version
# terraform-ls reports its version without a leading v.
[ "$TERRAFORM_LS_VERSION" = "none" ] || assert_version terraform-ls "$TERRAFORM_LS_VERSION" terraform-ls version
[ "$TRIVY_VERSION" = "none" ] || assert_version trivy "$TRIVY_VERSION" trivy --version
[ "$PRE_COMMIT_VERSION" = "none" ] || assert_version pre-commit "$PRE_COMMIT_VERSION" pre-commit --version
