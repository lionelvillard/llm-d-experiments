#!/bin/bash
set -euo pipefail

source $(dirname "$0")/utils.sh

log_info "Creating Prometheus TLS certificates..."

prometheus_release_name=${1:-prometheus}
prometheus_namespace=${2:-monitoring}
prometheus_secret_name=${3:-prometheus-tls}

# Check if secret exists
if kubectl get secret "$prometheus_secret_name" -n "$prometheus_namespace" &>/dev/null; then
    log_info "Secret '$prometheus_secret_name' exists. Reusing it."
else
    log_info "Secret does not exist, creating new certificate..."
fi

# Ensure temp directory exists
tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout $tmpdir/prometheus-tls.key \
        -out $tmpdir/prometheus-tls.crt \
        -days 365 \
        -subj "/CN=prometheus" \
        -addext "subjectAltName=DNS:${prometheus_release_name}-kube-prometheus-prometheus.${prometheus_namespace}.svc.cluster.local,DNS:${prometheus_release_name}-kube-prometheus-prometheus.${prometheus_namespace}.svc,DNS:${prometheus_release_name}-kube-prometheus-prometheus,DNS:localhost" \
        &> /dev/null


log_info "Creating Kubernetes secret for Prometheus TLS"
kubectl create secret tls $prometheus_secret_name \
    --cert=$tmpdir/prometheus-tls.crt \
    --key=$tmpdir/prometheus-tls.key \
    -n $prometheus_namespace \
    --dry-run=client -o yaml | kubectl apply -f - &> /dev/null

log_success "Prometheus TLS certificates created and stored in secret '$prometheus_secret_name' in namespace '$prometheus_namespace'"
