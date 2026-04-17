#!/usr/bin/env bash
# Polls HPA and queue state, outputs CSV.
# Usage: ./observe.sh
# Environment:
#   OBSERVE_INTERVAL  poll interval in seconds (default: 5)
#   OBSERVE_OUTPUT    file to append CSV lines to (default: stdout only)

set -euo pipefail

INTERVAL="${OBSERVE_INTERVAL:-5}"
NAMESPACE="hpa-overshoot"
START=$(date +%s)

header="Timestamp,Elapsed,QueueLength,DesiredReplicas,CurrentReplicas,ReadyReplicas"
if [ -n "${OBSERVE_OUTPUT:-}" ]; then
    echo "$header" | tee "$OBSERVE_OUTPUT"
else
    echo "$header"
fi

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))

    # Queue length from external metrics API.
    QUEUE=$(kubectl get --raw \
        "/apis/external.metrics.k8s.io/v1beta1/namespaces/${NAMESPACE}/queue_length" 2>/dev/null \
        | grep -o '"value":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "N/A")

    # HPA status.
    HPA_JSON=$(kubectl get hpa worker -n "$NAMESPACE" -o json 2>/dev/null || echo "{}")
    DESIRED=$(echo "$HPA_JSON" | jq -r '.status.desiredReplicas // "N/A"' 2>/dev/null || echo "N/A")
    CURRENT=$(echo "$HPA_JSON" | jq -r '.status.currentReplicas // "N/A"' 2>/dev/null || echo "N/A")

    # Deployment ready replicas.
    READY=$(kubectl get deployment worker -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    [ -z "$READY" ] && READY="0"

    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    LINE="${TS},${ELAPSED},${QUEUE},${DESIRED},${CURRENT},${READY}"

    if [ -n "${OBSERVE_OUTPUT:-}" ]; then
        echo "$LINE" | tee -a "$OBSERVE_OUTPUT"
    else
        echo "$LINE"
    fi

    sleep "$INTERVAL"
done
