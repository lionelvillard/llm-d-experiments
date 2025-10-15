#!/bin/bash

source $(dirname $0)/utils.sh

TMP_DIR=$(mktemp -d)

git clone https://github.com/dumb0002/llm-d-activator.git ${TMP_DIR}
log_success "Cloned llm-d-activator repository."

pushd ${TMP_DIR} > /dev/null

make image-kind KIND_CLUSTER=llm-d STAGING_IMAGE_REGISTRY=kind.local GIT_TAG=dev
log_success "Activator image built and loaded."


popd # TMP_DIR
