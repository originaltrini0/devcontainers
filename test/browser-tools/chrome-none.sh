#!/bin/bash
set -e

source dev-container-features-test-lib

# Feature options do not reach the test-exec environment, so this scenario
# asserts the chrome=none outcome with a fixed expectation rather than via
# $CHROME. Keyring/repo absence proves the skip exits before any apt setup.
check "chrome absent when chrome=none" bash -c "! command -v google-chrome"
check "no chrome install leftovers" bash -c "! test -e /opt/google/chrome/chrome"
check "no apt repo or keyring configured" bash -c "! test -e /etc/apt/sources.list.d/google-chrome.list && ! test -e /etc/apt/keyrings/google-chrome.gpg"

reportResults
