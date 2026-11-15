#!/bin/bash
# Scenario: OpenTofu engine. Feature options reach the installer but not the
# test-exec environment, so export the same values the scenario sets and reuse
# test.sh's flavor-aware assertions (tofu pinned, terraform absent, tools).
set -e
export FLAVOR=tofu VERSION=1.13.9
. "$(dirname "${BASH_SOURCE[0]}")/test.sh"
