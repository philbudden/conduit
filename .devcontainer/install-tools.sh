#!/usr/bin/env bash
set -euo pipefail

# Install terminal tools for blueberry-k3s GitOps development.
# Versions are pinned to match .github/workflows/validate.yaml.

FLUX_VERSION="v2.4.0"
KUSTOMIZE_VERSION="v5.5.0"
KUBECONFORM_VERSION="v0.6.7"
YQ_VERSION="v4.44.6"
KUBECTL_VERSION="v1.31.4"
HELM_VERSION="v3.16.4"

ARCH="amd64"
BIN="/usr/local/bin"

echo "Installing kubectl ${KUBECTL_VERSION}..."
sudo curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" -o "${BIN}/kubectl"
sudo chmod +x "${BIN}/kubectl"

echo "Installing helm ${HELM_VERSION}..."
curl -sL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" \
  | sudo tar xz --strip-components=1 -C "${BIN}" "linux-${ARCH}/helm"

echo "Installing flux ${FLUX_VERSION}..."
curl -sL "https://github.com/fluxcd/flux2/releases/download/${FLUX_VERSION}/flux_${FLUX_VERSION#v}_linux_${ARCH}.tar.gz" \
  | sudo tar xz -C "${BIN}"

echo "Installing kustomize ${KUSTOMIZE_VERSION}..."
curl -sL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" \
  | sudo tar xz -C "${BIN}"

echo "Installing kubeconform ${KUBECONFORM_VERSION}..."
curl -sL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${ARCH}.tar.gz" \
  | sudo tar xz -C "${BIN}"

echo "Installing yq ${YQ_VERSION}..."
sudo curl -sL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" -o "${BIN}/yq"
sudo chmod +x "${BIN}/yq"

echo "Installing yamllint..."
pip3 install --user yamllint

echo "All tools installed."
