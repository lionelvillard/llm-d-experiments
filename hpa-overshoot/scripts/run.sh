#!/usr/bin/env bash
# End-to-end HPA overshoot experiment.
# Prerequisites: kind, docker, kubectl
# Usage: ./run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-hpa-overshoot}"
IMAGE_NAME="hpa-overshoot:latest"
NAMESPACE="hpa-overshoot"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# --- 1. Create kind cluster ---
log "Creating kind cluster '$CLUSTER_NAME'..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log "Cluster already exists, reusing."
else
    kind create cluster --name "$CLUSTER_NAME" --wait 60s
fi

# --- 2. Build and load image ---
log "Building Docker image..."
cd "$ROOT_DIR"
docker build -t "$IMAGE_NAME" .
log "Loading image into kind..."
kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"

# --- 3. Deploy namespace ---
log "Creating namespace..."
kubectl apply -f manifests/namespace.yaml

# --- 4. Deploy infrastructure ---
log "Deploying RBAC..."
kubectl apply -f manifests/rbac.yaml
log "Deploying Prometheus..."
kubectl apply -f manifests/prometheus.yaml
log "Deploying prometheus-adapter..."
kubectl apply -f manifests/prometheus-adapter.yaml

# --- 6. Wait for infrastructure ---
log "Waiting for Prometheus to be ready..."
kubectl rollout status deployment/prometheus -n "$NAMESPACE" --timeout=120s
log "Waiting for prometheus-adapter to be ready..."
kubectl rollout status deployment/prometheus-adapter -n "$NAMESPACE" --timeout=120s

# --- 7. Wait for external metrics API ---
log "Waiting for external metrics API to be available..."
for i in $(seq 1 30); do
    if kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" &>/dev/null; then
        log "External metrics API is available."
        break
    fi
    if [ "$i" -eq 30 ]; then
        log "ERROR: External metrics API not available after 60s."
        log "Debug: prometheus-adapter logs:"
        kubectl logs -n "$NAMESPACE" -l app=prometheus-adapter --tail=50
        exit 1
    fi
    sleep 2
done

# --- 8. Deploy workload ---
log "Deploying queue-server..."
kubectl apply -f manifests/queue-server.yaml
kubectl rollout status deployment/queue-server -n "$NAMESPACE" --timeout=60s

log "Deploying worker (1 replica)..."
kubectl apply -f manifests/worker.yaml

log "Deploying HPA..."
kubectl apply -f manifests/hpa.yaml

# --- 9. Wait for queue_length metric to appear ---
log "Waiting for queue_length metric to appear in external metrics API..."
for i in $(seq 1 30); do
    if kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/${NAMESPACE}/queue_length" &>/dev/null; then
        log "queue_length metric is available."
        break
    fi
    if [ "$i" -eq 30 ]; then
        log "WARNING: queue_length metric not yet visible. Proceeding anyway."
    fi
    sleep 2
done

# --- 10. Start experiment ---
log "========================================"
log "Starting experiment: deploying load generator (100 req/s)"
log "Expected behavior:"
log "  t~15s: desired ~6     (from 1)"
log "  t~30s: desired ~65    (from 6)"
log "  t~45s: desired ~1053  (from 65)"
log "  t~60s: desired ~22745 (from 1053)"
log "========================================"
kubectl apply -f manifests/load-generator.yaml

# --- 11. Observe ---
log "Starting observer (Ctrl-C to stop)..."
log ""
exec "$SCRIPT_DIR/observe.sh"
