#!/bin/bash

source $(dirname $0)/utils.sh

kind create cluster --name llm-d || echo "Kind cluster 'llm-d' already exists."; exit 1
log_success "Kind cluster 'llm-d' created."
