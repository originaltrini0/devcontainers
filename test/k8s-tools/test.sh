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

check "kubectl is pinned" bash -c "kubectl version --client | grep -qF 'v${KUBECTL_VERSION}'"
check "talosctl is pinned" bash -c "talosctl version --client | grep -qF '${TALOS_VERSION}'"
# flux prints `flux version 2.10.0` — no leading v in its output.
check "flux is pinned" bash -c "flux --version | grep -qF '${FLUX_VERSION}'"
check "helm is pinned" bash -c "helm version --short | grep -qF 'v${HELM_VERSION}'"
check "kustomize is pinned" bash -c "kustomize version | grep -qF 'v${KUSTOMIZE_VERSION}'"
check "sops is pinned" bash -c "sops --version | head -n1 | grep -qF '${SOPS_VERSION}'"
check "age is pinned" bash -c "age --version | grep -qF 'v${AGE_VERSION}'"
check "age-keygen installed" bash -c "command -v age-keygen"
check "cilium is pinned" bash -c "cilium version --client | grep -qF '${CILIUM_VERSION}'"
check "yq is pinned" bash -c "yq --version | grep -qF '${YQ_VERSION}'"

if [ "${STEP_VERSION}" = "none" ]; then
  check "step is opt-in (absent by default)" bash -c "! command -v step"
else
  check "step is pinned" bash -c "step version | grep -qF '${STEP_VERSION}'"
fi

reportResults
