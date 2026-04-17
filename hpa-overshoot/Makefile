CLUSTER_NAME ?= hpa-overshoot
IMAGE_NAME   ?= hpa-overshoot:latest
NAMESPACE    ?= hpa-overshoot

.PHONY: kind-create build kind-load deploy-infra deploy-workload start observe run clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

kind-create: ## Create kind cluster
	@if kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Cluster '$(CLUSTER_NAME)' already exists."; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --wait 60s; \
	fi
	@echo "Setting inotify limits (required for kube-proxy)..."
	docker exec $(CLUSTER_NAME)-control-plane sysctl -w fs.inotify.max_user_watches=1048576 fs.inotify.max_user_instances=512

build: ## Build Docker image
	docker build -t $(IMAGE_NAME) .

kind-load: ## Load Docker image into kind cluster
	kind load docker-image $(IMAGE_NAME) --name $(CLUSTER_NAME)

deploy-infra: ## Deploy namespace, Prometheus, prometheus-adapter, RBAC
	kubectl apply -f manifests/namespace.yaml
	kubectl apply -f manifests/rbac.yaml
	kubectl apply -f manifests/prometheus.yaml
	kubectl apply -f manifests/prometheus-adapter.yaml
	kubectl rollout status deployment/prometheus -n $(NAMESPACE) --timeout=120s
	kubectl rollout status deployment/prometheus-adapter -n $(NAMESPACE) --timeout=120s
	@echo "Waiting for external metrics API..."
	@for i in $$(seq 1 30); do \
		kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" &>/dev/null && break; \
		sleep 2; \
	done

deploy-workload: ## Deploy queue-server, worker, HPA
	kubectl apply -f manifests/queue-server.yaml
	kubectl rollout status deployment/queue-server -n $(NAMESPACE) --timeout=60s
	kubectl apply -f manifests/worker.yaml
	kubectl apply -f manifests/hpa.yaml
	@echo "Waiting for queue_length metric..."
	@for i in $$(seq 1 30); do \
		kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/$(NAMESPACE)/queue_length" &>/dev/null && break; \
		sleep 2; \
	done

start: ## Deploy load generator (starts the experiment)
	kubectl apply -f manifests/load-generator.yaml

observe: ## Run observer script (outputs CSV to stdout)
	./scripts/observe.sh

run: kind-create build kind-load deploy-infra deploy-workload start observe ## Full end-to-end experiment

clean: ## Delete all resources and kind cluster
	-kubectl delete namespace $(NAMESPACE) --ignore-not-found
	-kubectl delete apiservice v1beta1.external.metrics.k8s.io --ignore-not-found
	-kubectl delete clusterrolebinding hpa-overshoot:prometheus-adapter:system:auth-delegator --ignore-not-found
	-kubectl delete clusterrolebinding hpa-overshoot:external-metrics-reader --ignore-not-found
	-kubectl delete clusterrolebinding hpa-overshoot:prometheus-adapter:namespace-lister --ignore-not-found
	-kubectl delete clusterrole hpa-overshoot:external-metrics-reader --ignore-not-found
	-kubectl delete clusterrole hpa-overshoot:prometheus-adapter:namespace-lister --ignore-not-found
	-kubectl delete rolebinding hpa-overshoot:prometheus-adapter:extension-apiserver-authentication-reader -n kube-system --ignore-not-found
	-kind delete cluster --name $(CLUSTER_NAME)
