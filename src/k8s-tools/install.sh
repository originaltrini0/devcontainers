#!/usr/bin/env bash
# Kubernetes GitOps CLIs. Sole owner of these pins; project configs override
# per-option. Self-contained after sync-features.sh vendors lib.sh next to it,
# so this file doubles as features/k8s-tools/src/install.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

opts="${OPTIONS:-}"
ARCH="$(detect_arch)"
KUBECTL_VERSION="$(option_value "$opts" kubectl "${KUBECTL_VERSION:-1.35.2}")"
TALOS_VERSION="$(option_value "$opts" talosctl "${TALOS_VERSION:-1.13.2}")"
FLUX_VERSION="$(option_value "$opts" flux "${FLUX_VERSION:-2.10.0}")"
HELM_VERSION="$(option_value "$opts" helm "${HELM_VERSION:-3.22.1}")"
KUSTOMIZE_VERSION="$(option_value "$opts" kustomize "${KUSTOMIZE_VERSION:-5.8.3}")"
SOPS_VERSION="$(option_value "$opts" sops "${SOPS_VERSION:-3.13.3}")"
AGE_VERSION="$(option_value "$opts" age "${AGE_VERSION:-1.3.2}")"
CILIUM_VERSION="$(option_value "$opts" cilium "${CILIUM_VERSION:-0.20.3}")"
YQ_VERSION="$(option_value "$opts" yq "${YQ_VERSION:-v4.54.3}")"
STEP_VERSION="$(option_value "$opts" step "${STEP_VERSION:-none}")"

download_file "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
  /usr/local/bin/kubectl "${KUBECTL_SHA256:-}"
download_file "https://github.com/siderolabs/talos/releases/download/v${TALOS_VERSION}/talosctl-linux-${ARCH}" \
  /usr/local/bin/talosctl "${TALOS_SHA256:-}"
download_file "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${ARCH}" \
  /usr/local/bin/sops "${SOPS_SHA256:-}"
download_file "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" \
  /usr/local/bin/yq "${YQ_SHA256:-}"

download_extract "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${ARCH}.tar.gz" \
  -C /usr/local/bin flux
download_extract "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" \
  --strip-components=1 -C /usr/local/bin "linux-${ARCH}/helm"
download_extract "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" \
  -C /usr/local/bin kustomize
download_extract "https://github.com/cilium/cilium-cli/releases/download/v${CILIUM_VERSION}/cilium-linux-${ARCH}.tar.gz" \
  -C /usr/local/bin cilium
# The age tarball nests binaries under age/, hence the transform.
download_extract "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${ARCH}.tar.gz" \
  -C /usr/local/bin --transform='s|age/||' "age/age" "age/age-keygen"

if [ "$STEP_VERSION" != "none" ]; then
# smallstep publishes `step_<ver>_<os>_<arch>.tar.gz` (not the older
# `step-cli_<ver>_linux_<arch>` name) with the binary at <dir>/bin/step.
download_extract "https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/step_linux_${STEP_VERSION}_${ARCH}.tar.gz" \
    --strip-components=2 -C /usr/local/bin "step_${STEP_VERSION}/bin/step"
  step version
fi

kubectl version --client
talosctl version --client
flux --version
helm version --short
kustomize version
sops --version | head -n1
age --version
command -v age-keygen
cilium version --client
yq --version
