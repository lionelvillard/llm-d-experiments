#!/bin/bash

source $(dirname $0)/utils.sh

kind delete cluster --name llm-d
log_success "Kind cluster 'llm-d' deleted."
