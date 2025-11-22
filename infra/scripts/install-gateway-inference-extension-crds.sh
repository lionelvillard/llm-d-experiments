#!/bin/bash
set -euo pipefail

source "$(dirname "$0")"/utils.sh

gateway_version=${1:-v1.1.0}
ext_version=${2:-v1.1.0}

log_info "Using Gateway API CRDs (version: $gateway_version)"
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/"${gateway_version}"/standard-install.yaml

log_info "Installing Gateway API Inference Extension CRDs (version: $ext_version)"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/"${ext_version}"/manifests.yaml
