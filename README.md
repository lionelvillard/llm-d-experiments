# llm-d Experiments

This repository contains experiments and examples related to
[llm-d](https://github.com/llm-d/llm-d) and
[incubating projects](https://github.com/llm-d-incubation).


## Quickstart

Follow the instructions in the [llm-d installation
instructions](infra/README.md) to set up a local KIND cluster with `llm-d` installed.


## Install models

To install models, run the following command:

```bash
kustomize build config/overlays/kind | kubectl apply -f -
```


## Access the model service


### Direct access to vllm

Port-forward the vllm pod to access it directly:

```bash
kubectl port-forward pods/granite-3-2-8b-instruct-64bd7cfbbf-4smc4 8000:8000
```

Then, you can send requests to the model service at `http://localhost:8000`:

```bash
curl -s localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d '{
                    "model": "granite/granite-3-2-8b-instruct",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }'
```

### Via Inference Gateway

Port-forward the Inference Gateway to access it:

```bash
kubectl port-forward svc/gateway-istio 8000:80
```

Then, you can send requests to the model service at `http://localhost:8000`:

```bash
curl -s localhost:8000/granite3/v1/chat/completions \
     -H "x-gateway-inference-objective: food-review" \
     -H "Content-Type: application/json" -d '{
                    "model": "granite/granite-3-2-8b-instruct",
                    "max_tokens": 100,
                    "messages": [
                      {
                        "role": "user",
                        "content": "Linux is said to be an open source kernel because "
                      }
                    ]
            }'
```
