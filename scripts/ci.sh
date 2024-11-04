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

clean_build_dir(){
    if [[ -d "${BUILD_DIR}" ]]; then
        log_trace "Removing existing build directory"
        rm -rf "${BUILD_DIR}"
    fi
    mkdir -p "${BUILD_DIR}"
}

hadolint_validate(){
    local hadolint_exec
    local hadolint_exit_code
    log_info "Validating Dockerfile with hadolint"
    podman pull -q ghcr.io/hadolint/hadolint:latest > /dev/null
    log_trace "$(podman run --rm -i hadolint/hadolint:latest hadolint -v)"

    set +e
    hadolint_exec=$(
        podman run --rm -i hadolint/hadolint:latest < Containerfile \
            2>&1
    )
    set -e
    hadolint_exit_code=$?

    if [[ $hadolint_exit_code -ne 0 ]]; then
        echo -e "${WHITE_GRAY}${hadolint_exec}${NC}"
        log_error "Hadolint validation failed"
        exit 1
    else
        log_success "Hadolint validation passed"
    fi
}

buildah_build(){
    local buildah_exec
    local buildah_exit_code
    log_info "Build Containerfile for ${IMAGE_NAME}:${IMAGE_TAG}"
    log_trace "$(buildah --version)"

    set +e
    # Put in trace color
    buildah_exec=$(
        buildah build \
            --squash \
            --pull-always \
            --format ${IMAGE_FORMAT} \
            --build-arg UBUNTU_VERSION=${UBUNTU_VERSION} \
            --build-arg APP_UID=${APP_UID} \
            --tag ${IMAGE_NAME}:${IMAGE_TAG} \
            . \
            2>&1
    )
    set -e
    buildah_exit_code=$?
    if [[ $buildah_exit_code -ne 0 ]]; then
        echo -e "${WHITE_GRAY}${buildah_exit_code}${NC}"
        log_error "Build failed"
        exit 1
    else
        log_success "Build completed successfully"
    fi
}

podman_save_image_to_tar(){
    local podman_exec
    local podman_exit_code
    log_info "Saving image to tar ${IMAGE_NAME}:${IMAGE_TAG}"
    log_trace "$(podman --version)"

    set +e
    podman_exec=$(
        podman save \
            --output ${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar \
            ${IMAGE_NAME}:${IMAGE_TAG} \
            2>&1
    )
    set -e
    podman_exit_code=$?

    if [[ $podman_exit_code -ne 0 ]]; then
        echo -e "${WHITE_GRAY}${podman_exec}${NC}"
        log_error "Saving image to tar failed"
        exit 1
    else
        log_success "Image saved to ${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar"
    fi
}

dive_scan() {
    local dive_scan
    log_info "Running dive scan on ${IMAGE_NAME}:${IMAGE_TAG}"
    log_trace "$(dive --version)"

    set +e
    dive_scan=$(\
        dive \
            --ci \
            --source=podman \
            ${IMAGE_NAME}:${IMAGE_TAG} \
            2>&1 \
    )
    set -e

    if [[ $dive_scan == *"FAIL"* ]]; then
        echo -e "${WHITE_GRAY}${dive_scan}${NC}"
        log_error "Dive scan failed"
        exit 1
    else
        log_success "Dive scan passed"
    fi
}

trivy_scan () {
    
    local trivy_scan_exec
    local trivy_scan_exit_code

    log_info "Running trivy scan on ${IMAGE_NAME}:${IMAGE_TAG}"
    log_trace "$(trivy --version)"

    set +e
    trivy_scan_exec=$(\
            trivy image \
            --input ${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar \
            --format github \
            --severity HIGH,CRITICAL \
            --exit-code 2 \
            ${IMAGE_NAME}:${IMAGE_TAG} \
            2>&1
    )
    set -e

    # Detect exit code
    trivy_scan_exit_code=$?
    if [[ $trivy_scan_exit_code -eq 2 ]]; then
        echo -e "${WHITE_GRAY}${trivy_scan_exec}${NC}"
        log_error "Trivy scan failed"
        exit 1
    elif [[ $trivy_scan_exit_code -eq 1 ]]; then
        echo -e "${WHITE_GRAY}${trivy_scan_exec}${NC}"
        log_error "Trivy scan error"
    else
        log_success "Trivy scan passed"
    fi
}


clean_build_dir
hadolint_validate # Validate/Lint Containerfile
buildah_build # Build Containerfile
podman_save_image_to_tar # Save image to tar (for trivy scan)
dive_scan # Filesystem scan and analysis
trivy_scan # Vulnerability scan