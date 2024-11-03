#!/usr/bin/env bash

set -eo pipefail

# Include the utils library
source scripts/lib_utils.sh

IMAGE_NAME="builah-example"
IMAGE_TAG="latest"
IMAGE_FORMAT="oci"
UBUNTU_VERSION="22.04"
APP_UID="1000"

log_info "Build Containerfile for ${IMAGE_NAME}:${IMAGE_TAG} $(buildah --version)"

# Put in trace color
echo -e "${WHITE_GRAY}$(buildah build \
    --pull-always \
    --format ${IMAGE_FORMAT} \
    --build-arg UBUNTU_VERSION=${UBUNTU_VERSION} \
    --build-arg APP_UID=${APP_UID} \
    --tag ${IMAGE_NAME}:${IMAGE_TAG} \
    .)${NC}"

log_info "Build completed successfully"

log_info "Running dive scan on ${IMAGE_NAME}:${IMAGE_TAG} $(dive --version)"
dive_scan=$(CI=true dive --source=podman ${IMAGE_NAME}:${IMAGE_TAG})

if [[ $dive_scan == *"FAIL"* ]]; then
    echo -e "${WHITE_GRAY}${dive_scan}${NC}"
    log_error "Dive scan failed"
    exit 1
else
    log_success "Dive scan passed"
fi

log_info "Running trivy scan on ${IMAGE_NAME}:${IMAGE_TAG} $(trivy --version)"
trivy image ${IMAGE_NAME}:${IMAGE_TAG}