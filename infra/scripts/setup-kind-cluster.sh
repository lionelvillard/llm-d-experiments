#!/bin/bash
set -euo pipefail

source "$(dirname "$0")"/utils.sh

echo "setting up kind cluster 'llm-d'... "
if kind create cluster --name llm-d --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF
then
  log_success "kind cluster created"
else
  log_success "reusing existing kind cluster 'llm-d'"
fi

kubectl config use-context kind-llm-d

echo "configuring GPU labels and capacity on kind cluster nodes..."

nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $nodes; do
  kubectl label node "$node" "nvidia.com/gpu.product=NVIDIA-H100-80GB-HBM3" --overwrite
  kubectl label node "$node" "nvidia.com/gpu.count=8" --overwrite
  kubectl label node "$node" "nvidia.com/gpu.memory=81559" --overwrite

  # Patch node to add GPU capacity
  kubectl patch node "$node" --subresource=status --type=json -p='[
    {
      "op": "add",
      "path": "/status/capacity/nvidia.com~1gpu",
      "value": "8"
    },
    {
      "op": "add",
      "path": "/status/allocatable/nvidia.com~1gpu",
      "value": "8"
    }
  ]'

done

log_success "GPU labels and capacity configured on kind cluster nodes"
