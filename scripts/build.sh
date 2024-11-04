#!/usr/bin/env bash

set -eo pipefail

# Include the utils library
source scripts/lib_utils.sh

IMAGE_NAME="builah-example"
IMAGE_TAG="latest"
IMAGE_FORMAT="oci"
UBUNTU_VERSION="24.04"
APP_UID="1000"

BUILD_DIR="./build"

buildah build \
    --pull-always \
    --format ${IMAGE_FORMAT} \
    --build-arg UBUNTU_VERSION=${UBUNTU_VERSION} \
    --build-arg APP_UID=${APP_UID} \
    --tag ${IMAGE_NAME}:${IMAGE_TAG} \
    .