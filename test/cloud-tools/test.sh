#!/bin/bash
set -e

source dev-container-features-test-lib

AWS_VERSION="${AWS:-2.40.3}"
AZ_VERSION="${AZ:-2.92.0}"
PWSH_VERSION="${PWSH:-7.7.0}"
GCLOUD_VERSION="${GCLOUD:-593.0.0}"

# Here-string match, never a pipe: `cmd | grep -q` races SIGPIPE against the
# writer under pipefail (buildx exit 141).

if [ "${AWS_VERSION}" = "none" ]; then
  check "aws skipped when none" bash -c "! command -v aws"
else
  check "aws is pinned" bash -c "grep -qF 'aws-cli/${AWS_VERSION}' <<< \"\$(aws --version 2>&1)\""
fi

if [ "${AZ_VERSION}" = "none" ]; then
  check "az skipped when none" bash -c "! command -v az"
else
  # `--output tsv` puts the versions on one tab-separated line, so the needle
  # is a plain string — an embedded double-quote needle does not survive the
  # test lib's check() (the JSON needle is still asserted by the installer's
  # build-time assert_version, which gates every build).
  check "az is pinned" bash -c "grep -qxF '${AZ_VERSION}' <<< \"\$(az version --output tsv 2>&1 | cut -f1)\""
fi

if [ "${PWSH_VERSION}" = "none" ]; then
  check "pwsh skipped when none" bash -c "! command -v pwsh"
else
  check "pwsh is pinned" bash -c "grep -qF '${PWSH_VERSION}' <<< \"\$(pwsh --version 2>&1)\""
fi

if [ "${GCLOUD_VERSION}" = "none" ]; then
  check "gcloud skipped when none" bash -c "! command -v gcloud"
else
  check "gcloud is pinned" bash -c "grep -qF 'Google Cloud SDK ${GCLOUD_VERSION}' <<< \"\$(gcloud version 2>&1)\""
fi

reportResults
