FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# TARGETARCH is set automatically by Docker BuildKit (amd64 or arm64).
# Versions are pinned to match .github/workflows/validate.yaml.
ARG TARGETARCH=amd64

# Install yamllint
RUN apt-get update \
    && apt-get install -y --no-install-recommends yamllint \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl v1.31.4
RUN curl -sL "https://dl.k8s.io/release/v1.31.4/bin/linux/${TARGETARCH}/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Install helm v3.16.4
RUN curl -sL "https://get.helm.sh/helm-v3.16.4-linux-${TARGETARCH}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "linux-${TARGETARCH}/helm"

# Install flux v2.4.0
RUN curl -sL "https://github.com/fluxcd/flux2/releases/download/v2.4.0/flux_2.4.0_linux_${TARGETARCH}.tar.gz" \
    | tar xz -C /usr/local/bin

# Install kustomize v5.5.0
RUN curl -sL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.5.0/kustomize_v5.5.0_linux_${TARGETARCH}.tar.gz" \
    | tar xz -C /usr/local/bin

# Install kubeconform v0.6.7
RUN curl -sL "https://github.com/yannh/kubeconform/releases/download/v0.6.7/kubeconform-linux-${TARGETARCH}.tar.gz" \
    | tar xz -C /usr/local/bin

# Install yq v4.44.6
RUN curl -sL "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_linux_${TARGETARCH}" \
        -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq
