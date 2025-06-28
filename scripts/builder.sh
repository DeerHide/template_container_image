#!/usr/bin/env bash

set -eo pipefail

# Include the utils library
source scripts/lib_utils.sh

CLI="docker"

MANIFEST_FILE="manifest.yaml"

IMAGE_TAG="latest"
IMAGE_FORMAT="oci"
UBUNTU_VERSION="24.04"
APP_UID="1000"

BUILD_DIR="./build"

check_for_manifest(){
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        log_error "Manifest file not found"
        exit 1
    fi
}

retrieve_name_from_manifest(){
    local name
    name=$(yq e '.name' $MANIFEST_FILE)
    echo $name
}

retrieve_registry_from_manifest(){
    local registry
    registry=$(yq e '.registry' $MANIFEST_FILE)
    echo $registry
}


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
    ${CLI} pull -q ghcr.io/hadolint/hadolint:latest > /dev/null
    log_trace "$(${CLI} run --rm -i hadolint/hadolint:latest hadolint -v)"

    set +e
    hadolint_exec=$(
        ${CLI} run --rm -i hadolint/hadolint:latest < Containerfile \
            2>&1
    )
    hadolint_exit_code=$?
    set -e
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
    local buildah_args
    local manifest_args
    log_info "Build Containerfile for ${IMAGE_NAME}:${IMAGE_TAG}"
    log_trace "$(buildah --version)"


    # Extract build args from manifest
    buildah_args=()
    for arg in $(yq e '.build.args[]' $MANIFEST_FILE); do
        buildah_args+="--build-arg ${arg} "
    done

    log_trace "Buildah args: ${buildah_args}"
    set +e
    buildah_exec=$(
        buildah build \
            --squash \
            --pull-always \
            --format ${IMAGE_FORMAT} \
            ${buildah_args} \
            --tag docker-daemon:${IMAGE_NAME}:${IMAGE_TAG} \
            . \
            2>&1
    )
    buildah_exit_code=$?
    set -e
    if [[ $buildah_exit_code -ne 0 ]]; then
        log_error "Build failed"
        log_error "${buildah_exec}"
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
        ${CLI} save \
            --output ${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar \
            ${IMAGE_NAME}:${IMAGE_TAG} \
            2>&1
    )
    podman_exit_code=$?
    set -e
    if [[ $podman_exit_code -ne 0 ]]; then
        echo -e "${WHITE_GRAY}${podman_exec}${NC}"
        log_error "Saving image to tar failed"
        exit 1
    else
        log_success "Image saved to ${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar"
    fi
}

docker_save_image_to_tar(){
    local docker_exec
    local docker_exit_code
    log_info "Saving image to tar ${IMAGE_NAME}:${IMAGE_TAG}"
    log_trace "$(docker --version)"

    set +e
    docker_exec=$(
        ${CLI} save \
            --output ${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}.tar \
            ${IMAGE_NAME}:${IMAGE_TAG} \
            2>&1
    )
    docker_exit_code=$?
    set -e
    if [[ $docker_exit_code -ne 0 ]]; then
        echo -e "${WHITE_GRAY}${docker_exec}${NC}"
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
            --source=${CLI} \
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
    # Detect exit code
    trivy_scan_exit_code=$?
    set -e
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

# Main
clean_build_dir
check_for_manifest # Check for manifest file existence\
IMAGE_NAME=$(retrieve_name_from_manifest) # Retrieve image name from manifest

log_info "Starting build process"
log_trace "CLI: ${CLI}"
log_trace "IMAGE_NAME: ${IMAGE_NAME}"
log_trace "IMAGE_TAG: ${IMAGE_TAG}"
log_trace "IMAGE_FORMAT: ${IMAGE_FORMAT}"


hadolint_validate # Validate/Lint Containerfile
buildah_build # Build Containerfile

if [[ $CLI == "podman" ]]; then
    podman_save_image_to_tar # Save image to tar (for trivy scan)
elif [[ $CLI == "docker" ]]; then
    docker_save_image_to_tar # Save image to tar (for trivy scan)
else
    log_error "Invalid CLI"
    exit 1
fi

dive_scan # Filesystem scan and analysis
trivy_scan # Vulnerability scan

# Deploy to registry with skopeo using tags in manifest
registry=$(retrieve_registry_from_manifest)
skopeo copy docker-daemon:${IMAGE_NAME}:${IMAGE_TAG} docker://${registry}:${IMAGE_TAG}