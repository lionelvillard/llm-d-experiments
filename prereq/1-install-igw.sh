#!/bin/bash

source $(dirname $0)/utils.sh

TMP_DIR=$(mktemp -d)

git clone https://github.com/llm-d/llm-d.git ${TMP_DIR}
cd ${TMP_DIR}
git checkout v0.3
log_success "Cloned llm-d repository."

pushd guides/prereq/gateway-provider > /dev/null
./install-gateway-provider-dependencies.sh # Installs the CRDs
helmfile apply -f istio.helmfile.yaml
popd
log_success "Istio gateway installed."

pushd docs/monitoring > /dev/null
./install-prometheus-grafana.sh
popd
log_success "Prometheus and Grafana installed."
