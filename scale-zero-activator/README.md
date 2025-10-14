# Scale Zero Activator Experiments

This repository contains experiments related to the
[Scale to/from Zero Activator](https://github.com/dumb0002/llm-d-activator).

Each experiment deploys two models behind an Istio gateway:
- `meta-llama/Llama-3.1-8B-Instruct`
- `granite/granite3-8B`

The first experiment deploys the models without BBR,
and instead relies on the Gateway API URL rewriting capabilities.

The second experiment deploys the models with BBR.

## Prerequisites

Before running the experiments, ensure you have completed the prerequisites
outlined in the [prereq directory](./prereq/README.md).

Make sure to install the Scale to/from Zero Activator.

You can run this experiment on a local Kubernetes cluster using [kind](https://kind.sigs.k8s.io/).

## Experiment 1: deploying without BBR

### Deploying the models

1. Create the namespace and switch to it:

    ```shell
    kubectl create namespace sza
    kubectl config set-context --current --namespace=sza
    ```

1. Deploy the models and associated resources:

    ```shell
    kubectl apply -f config/
    ```

1. Verify that the models are deployed and ready:

    ```shell
    kubectl get pods
    ```

## Testing the setup

1. Port forward the IP of the gateway:

    ```shell
    kubectl port-forward svc/sza-istio 8080:80
    ```

1. Send a request to the gateway (in a different terminal):

    ```shell
    curl localhost:8080/llama3/v1/chat/completions \
            -H "Content-Type: application/json" \
            -d '{
                    "model": "meta-llama/Llama-3.1-8B-Instruct",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }'
    ```

    ```shell
    curl localhost:8080/granite3/v1/chat/completions \
            -H "Content-Type: application/json" \
            -d '{
                    "model": "granite/granite3-8B",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }'
    ```

## Cleaning up

To clean up the deployed resources, run:

```shell
kubectl delete ns sza
```

## Experiment 2: deploying with BBR

### Deploying BBR

Run the following command to deploy BBR:

```shell
helm install body-based-router \
        --set provider.name=istio \
        --version v1.0.0 \
        oci://registry.k8s.io/gateway-api-inference-extension/charts/body-based-routing
```

### Deploying the models

1. Create the namespace and switch to it:

    ```shell
    kubectl create namespace sza
    kubectl config set-context --current --namespace=sza
    ```

1. Deploy the models and associated resources:

    ```shell
    kubectl apply -f config-with-bbr/
    ```

1. Verify that the models are deployed and ready:

    ```shell
    kubectl get pods
    ```

## Testing the setup

1. Port forward the IP of the gateway:

    ```shell
    kubectl port-forward svc/sza-istio 8080:80
    ```

1. Send a request to the gateway (with bbr) (in a different terminal):

    ```shell
    curl localhost:8080/v1/chat/completions \
            -H "Content-Type: application/json" \
            -d '{
                    "model": "meta-llama/Llama-3.1-8B-Instruct",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }'
    ```

    ```shell
    curl localhost:8080/v1/chat/completions \
            -H "Content-Type: application/json" \
            -d '{
                    "model": "granite/granite3-8B",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }'
    ```
## Cleaning up

To clean up the deployed resources, run:

```shell
kubectl delete ns sza
```
