#!/bin/bash
# Invoked by test.sh. Launches Chrome as the container's remote user. The
# features-test harness usually runs tests as that user already, so runuser
# elevation is only taken when the harness runs as root. Tries the real
# sandbox first (no --no-sandbox); Docker's default seccomp denies the setuid
# sandbox's namespace move, so on blocked runtimes we fall back to
# sandbox-disabled — that is Kilo/Playwright's default launch
# (chromiumSandbox false), i.e. the shipped path. The gate is page render;
# the log records which mode was needed so CI proves the flag story.
set -u

if [ "$(id -u)" = 0 ]; then
  user="${REMOTE_USER:-}"
  { [ -n "$user" ] && id "$user" > /dev/null 2>&1; } || user=vscode
  id "$user" > /dev/null 2>&1 || { echo "no remote user (tried '${REMOTE_USER:-}', vscode)"; exit 1; }
  # runuser keeps root's HOME, so Chrome would try to create its profile
  # under /root as the remote user; hand it the user's real home.
  home="$(getent passwd "$user" | cut -d: -f6)"
  launcher=(runuser -u "$user" -- env HOME="$home" google-chrome)
else
  # Already the non-root remote user; no elevation possible or needed.
  user="$(id -un)"
  launcher=(google-chrome)
fi

render() {
  local out
  # Flags match the installer's render check; the token page rules out
  # Chrome's own error pages satisfying a generic '<html>' match.
  out="$(timeout 120 "${launcher[@]}" --headless --disable-gpu --disable-dev-shm-usage "$@" --dump-dom 'data:text/html,<h1>kilorendok</h1>' 2>&1)" || {
    last_output="$out"
    return 1
  }
  grep -qF kilorendok <<< "$out"
}

if render; then
  echo "non-root launch: real sandbox OK as $user (no container flag needed)"
elif render --no-sandbox; then
  echo "non-root launch: sandbox blocked by runtime as $user (real sandbox needs --cap-add=SYS_ADMIN); --no-sandbox render OK, matching the Playwright/Kilo default"
else
  echo "non-root launch: FAILED as $user even with --no-sandbox"
  echo "last chrome output: ${last_output:-<none>}"
  exit 1
fi
