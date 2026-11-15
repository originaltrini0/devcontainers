#!/bin/bash
set -e

source dev-container-features-test-lib

KUBECTL_VERSION="${KUBECTL:-1.35.2}"
TALOS_VERSION="${TALOSCTL:-1.13.2}"
FLUX_VERSION="${FLUX:-2.10.0}"
HELM_VERSION="${HELM:-3.22.1}"
KUSTOMIZE_VERSION="${KUSTOMIZE:-5.8.3}"
SOPS_VERSION="${SOPS:-3.13.3}"
AGE_VERSION="${AGE:-1.3.2}"
CILIUM_VERSION="${CILIUM:-0.20.3}"
YQ_VERSION="${YQ:-v4.54.3}"
STEP_VERSION="${STEP:-none}"

# Here-string match, never a pipe: `cmd | grep -q` races SIGPIPE against the
# writer under pipefail (buildx exit 141).

check "kubectl is pinned" bash -c "grep -qF 'v${KUBECTL_VERSION}' <<< \"\$(kubectl version --client 2>&1)\""
check "talosctl is pinned" bash -c "grep -qF '${TALOS_VERSION}' <<< \"\$(talosctl version --client 2>&1)\""
# flux prints `flux version 2.10.0` — no leading v in its output.
check "flux is pinned" bash -c "grep -qF '${FLUX_VERSION}' <<< \"\$(flux --version 2>&1)\""
check "helm is pinned" bash -c "grep -qF 'v${HELM_VERSION}' <<< \"\$(helm version --short 2>&1)\""
check "kustomize is pinned" bash -c "grep -qF 'v${KUSTOMIZE_VERSION}' <<< \"\$(kustomize version 2>&1)\""
check "sops is pinned" bash -c "grep -qF '${SOPS_VERSION}' <<< \"\$(sops --version 2>&1)\""
check "age is pinned" bash -c "grep -qF 'v${AGE_VERSION}' <<< \"\$(age --version 2>&1)\""
check "age-keygen installed" bash -c "command -v age-keygen"
check "cilium is pinned" bash -c "grep -qF '${CILIUM_VERSION}' <<< \"\$(cilium version --client 2>&1)\""
check "yq is pinned" bash -c "grep -qF '${YQ_VERSION}' <<< \"\$(yq --version 2>&1)\""

if [ "${STEP_VERSION}" = "none" ]; then
  check "step is opt-in (absent by default)" bash -c "! command -v step"
else
  check "step is pinned" bash -c "grep -qF '${STEP_VERSION}' <<< \"\$(step version 2>&1)\""
fi

reportResults
