# llm-d Installation Instructions

This directory contains installation scripts for `llm-d` and incubating projects.

## Quick installation with Helmfile on a KIND cluster

To quickly install `llm-d`, run the following commands:

```bash
$ ./infra/scripts/setup-kind-cluster.sh
$ helmfile sync --environment kind -f infra/helmfile.yaml.gotmpl
```

## Monitoring

Port-forward prometheus to access the metrics UI:

```bash
kubectl --namespace monitoring port-forward svc/prometheus-operated 9090:9090
```
