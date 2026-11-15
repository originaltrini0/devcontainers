#!/bin/bash
set -e

source dev-container-features-test-lib

FLAVOR="${FLAVOR:-terraform}"
VERSION="${VERSION:-1.17.2}"
TFLINT_VERSION="${TFLINT:-0.66.0}"
TERRAFORM_DOCS_VERSION="${TERRAFORM_DOCS:-0.25.1}"
TERRAFORM_LS_VERSION="${TERRAFORM_LS:-0.39.1}"
TRIVY_VERSION="${TRIVY:-0.76.2}"
PRE_COMMIT_VERSION="${PRE_COMMIT:-4.7.0}"

# Here-string match, never a pipe: `cmd | grep -q` races SIGPIPE against the
# writer under pipefail (buildx exit 141).

if [ "${VERSION}" = "none" ]; then
  check "engine skipped when version=none" bash -c "! command -v terraform && ! command -v tofu"
elif [ "${FLAVOR}" = "tofu" ]; then
  check "tofu is pinned" bash -c "grep -qF 'v${VERSION}' <<< \"\$(tofu version 2>&1)\""
  # Exactly one engine: a tofu project must not also get the terraform binary.
  check "terraform is absent under tofu flavor" bash -c "! command -v terraform"
else
  check "terraform is pinned" bash -c "grep -qF 'v${VERSION}' <<< \"\$(terraform version 2>&1)\""
  check "tofu is absent by default" bash -c "! command -v tofu"
fi

if [ "${TFLINT_VERSION}" = "none" ]; then
  check "tflint skipped when none" bash -c "! command -v tflint"
else
  check "tflint is pinned" bash -c "grep -qF '${TFLINT_VERSION}' <<< \"\$(tflint --version 2>&1)\""
fi

if [ "${TERRAFORM_DOCS_VERSION}" = "none" ]; then
  check "terraform-docs skipped when none" bash -c "! command -v terraform-docs"
else
  check "terraform-docs is pinned" bash -c "grep -qF 'v${TERRAFORM_DOCS_VERSION}' <<< \"\$(terraform-docs --version 2>&1)\""
fi

if [ "${TERRAFORM_LS_VERSION}" = "none" ]; then
  check "terraform-ls skipped when none" bash -c "! command -v terraform-ls"
else
  # terraform-ls reports its version without a leading v.
  check "terraform-ls is pinned" bash -c "grep -qF '${TERRAFORM_LS_VERSION}' <<< \"\$(terraform-ls version 2>&1)\""
fi

if [ "${TRIVY_VERSION}" = "none" ]; then
  check "trivy skipped when none" bash -c "! command -v trivy"
else
  check "trivy is pinned" bash -c "grep -qF '${TRIVY_VERSION}' <<< \"\$(trivy --version 2>&1)\""
fi

if [ "${PRE_COMMIT_VERSION}" = "none" ]; then
  check "pre-commit skipped when none" bash -c "! command -v pre-commit"
else
  check "pre-commit is pinned" bash -c "grep -qF '${PRE_COMMIT_VERSION}' <<< \"\$(pre-commit --version 2>&1)\""
fi

reportResults
