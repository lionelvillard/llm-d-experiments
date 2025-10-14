# Prerequisites

This directory contains prerequisite instructions for the experiments in this repository.

## llm-d

The recommended way to install `llm-d` is to follow the quickstart instructions in the [llm-d repository](https://github.com/llm-d/llm-d/blob/main/guides/QUICKSTART.md).

Or you can use the provided scripts in this directory to install
the Inference Gateway Extension Istio implementation and llm-d.

1. (Optional) Create a local Kubernetes cluster using [kind](https://kind.sigs.k8s.io/):

```bash
./0-create-kind.sh
```

1. Install the Inference Gateway Extension Istio implementation

```bash
./1-install-igw.sh
```

1. (Optional) Install the body-based router

```bash
./2-install-bbr.sh
```

1. (Optional) Uninstall llm-d and the Inference Gateway Extension Istio implementation

```bash
./2-uninstall-llm-d.sh
```
