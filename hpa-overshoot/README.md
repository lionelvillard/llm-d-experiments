# HPA Overshoot Experiment

Self-contained experiment that demonstrates how Kubernetes HPA with external `Value`
metrics creates a factorial feedback loop when scaling pods with slow startup times.

See [spec.md](spec.md) for the full analysis.

## Prerequisites

- [kind](https://kind.sigs.k8s.io/)
- [docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Quick Start

```bash
cd docs/design/hpa-overshoot
make run
```

This creates a kind cluster, builds and loads the image, deploys all components,
starts the load generator, and begins observing. Press Ctrl-C to stop.

## Experiment Parameters

| Parameter | Value |
|---|---|
| Incoming request rate | 100 req/s |
| Processing rate per pod | 10 req/s |
| Steady-state pods needed | 10 |
| HPA targetValue | 250 items |
| HPA sync period | 15s (default) |
| Pod startup time | 60s (startup probe) |

## Expected Results

The observer outputs CSV with columns:
`Timestamp, Elapsed, QueueLength, DesiredReplicas, CurrentReplicas, ReadyReplicas`

Expected progression (HPA formula: `desired = ceil(currentReplicas * queue / 250)`):

| ~Elapsed | Queue | Desired | Why |
|----------|-------|---------|-----|
| 15s | ~1350 | ~6 | `ceil(1 * 1350/250)` |
| 30s | ~2700 | ~65 | `ceil(6 * 2700/250)` |
| 45s | ~4050 | ~1053 | `ceil(65 * 4050/250)` |
| 60s | ~5400 | ~22745 | `ceil(1053 * 5400/250)` |

The kind cluster will not actually schedule 22k pods, but HPA's `desiredReplicas`
will reflect the computed value, demonstrating the factorial overshoot.

## Step-by-Step

Run individual steps if you prefer more control:

```bash
make kind-create       # Create kind cluster
make build             # Build Docker image
make kind-load         # Load image into kind
make deploy-infra      # Deploy Prometheus + prometheus-adapter + RBAC
make deploy-workload   # Deploy queue-server, worker, HPA
make start             # Deploy load generator (experiment begins)
make observe           # Start observer (Ctrl-C to stop)
```

## Architecture

```
Load Generator (100 req/s) --POST /enqueue--> Queue Server --GET /metrics--> Prometheus
                                                  ^                              |
                                             POST /dequeue              prometheus-adapter
                                                  |                              |
                                            Worker Pods          external metrics API (queue_length)
                                         (10 req/s each,                         |
                                          60s startup)                          HPA
                                                ^                         (targetValue: 250)
                                                |                                |
                                                +---------- scales --------------+
```

## Cleanup

```bash
make clean
```

This deletes the namespace, cluster-scoped RBAC resources, and the kind cluster.

## Troubleshooting

Check if the external metrics API is working:
```bash
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/hpa-overshoot/queue_length"
```

Check prometheus-adapter logs:
```bash
kubectl logs -n hpa-overshoot -l app=prometheus-adapter
```

Check HPA status:
```bash
kubectl describe hpa worker -n hpa-overshoot
```

Check Prometheus targets:
```bash
kubectl port-forward -n hpa-overshoot svc/prometheus 9090:9090
# Then open http://localhost:9090/targets
```
