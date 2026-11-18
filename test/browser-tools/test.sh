#!/bin/bash
set -e

source dev-container-features-test-lib

CHROME_VERSION="${CHROME:-158.0.8127.36-1}"

# Here-string match, never a pipe: `cmd | grep -q` races SIGPIPE against the
# writer under pipefail (buildx exit 141).

if [ "${CHROME_VERSION}" = "none" ]; then
  check "chrome skipped when none" bash -c "! command -v google-chrome"
else
  # apt pin carries the -N release suffix; `--version` reports it stripped.
  want="${CHROME_VERSION%-*}"
  check "chrome is pinned" bash -c "grep -qF 'Google Chrome ${want}' <<< \"\$(google-chrome --version 2>&1)\""
  # --headless/--disable-dev-shm-usage match the installer's render check;
  # --no-sandbox mirrors the Playwright/Kilo default launch and is required
  # when the harness runs the check as root. The token page rules out
  # Chrome's own error pages satisfying a generic '<html>' match.
  check "headless render (default sandbox-disabled launch)" bash -c "grep -qF kilorendok <<< \"\$(timeout 120 google-chrome --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --dump-dom 'data:text/html,<h1>kilorendok</h1>' 2>/dev/null)\""
  # Launch as the remote user with the real sandbox first; records whether a
  # container flag was needed (see nonroot-launch.sh).
  check "non-root launch renders (sandbox mode in log)" bash "$(dirname "${BASH_SOURCE[0]}")/nonroot-launch.sh"
fi

reportResults
