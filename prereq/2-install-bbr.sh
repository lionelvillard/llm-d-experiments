#!/bin/bash

source $(dirname $0)/utils.sh

helm install body-based-router \
--set provider.name=istio \
--version v1.0.0 \
oci://registry.k8s.io/gateway-api-inference-extension/charts/body-based-routing


log_success "Body-based router installed."
