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
    local buildah_labels
    local buildah_labels_array
    local manifest_args
    log_info "Build Containerfile for ${IMAGE_NAME}:${IMAGE_TAG}"
    log_trace "$(buildah --version)"


    # Extract build args from manifest
    buildah_args=()
    for arg in $(yq e '.build.args[]' $MANIFEST_FILE); do
        buildah_args+="--build-arg ${arg} "
    done

    # Extract labels from manifest
    buildah_labels=()
    buildah_labels_array=()
    while IFS= read -r label; do
        if [[ -n "${label}" ]]; then
            # Parse key=value and remove quotes from value if present
            # Handle both key=value and key="value" formats
            if [[ "${label}" =~ ^([^=]+)=(.*)$ ]]; then
                local label_key="${BASH_REMATCH[1]}"
                local label_value="${BASH_REMATCH[2]}"
                # Remove surrounding quotes from value if present
                label_value=$(echo "${label_value}" | sed -e 's/^"//' -e 's/"$//')
                # Reconstruct label without quotes in value
                label="${label_key}=${label_value}"
            fi
            # Add to both string (for logging) and array (for command)
            buildah_labels+="--label ${label} "
            buildah_labels_array+=("--label" "${label}")
        fi
    done < <(yq e '.build.labels[]' $MANIFEST_FILE)

    log_trace "Buildah args: ${buildah_args}"
    log_trace "Buildah labels: ${buildah_labels}"
    set +e
    buildah_exec=$(
        buildah build \
            --squash \
            --pull-always \
            --format ${IMAGE_FORMAT} \
            ${buildah_args} \
            "${buildah_labels_array[@]}" \
            --tag ${IMAGE_NAME}:${IMAGE_TAG} \
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
    
    # Copy to docker-daemon after successful build
    # Save image to tar first, then load into docker daemon
    # Store tar path in a variable for later use with skopeo
    export BUILD_TAR="${BUILD_DIR}/${IMAGE_NAME}-${IMAGE_TAG}-temp.tar"
    log_info "Saving image to temporary tar: ${BUILD_TAR}"
    set +e
    buildah_exec=$(
        buildah push ${IMAGE_NAME}:${IMAGE_TAG} oci-archive:${BUILD_TAR} \
            2>&1
    )
    buildah_exit_code=$?
    set -e
    if [[ $buildah_exit_code -ne 0 ]]; then
        log_error "Failed to save image to tar"
        log_error "${buildah_exec}"
        exit 1
    else
        log_success "Image saved to tar successfully"
        # Verify labels are in the tar file
        if command -v skopeo &> /dev/null; then
            local tar_labels
            tar_labels=$(skopeo inspect oci-archive:${BUILD_TAR} --format '{{.Labels}}' 2>/dev/null || echo "")
            if [[ -n "${tar_labels}" ]]; then
                log_trace "Labels in tar file: ${tar_labels}"
            else
                log_warn "No labels found in tar file"
            fi
        fi
    fi
    
    log_info "Loading image into Docker daemon: ${IMAGE_NAME}:${IMAGE_TAG}"
    set +e
    buildah_exec=$(
        docker load -i ${BUILD_TAR} \
            2>&1
    )
    buildah_exit_code=$?
    set -e
    
    if [[ $buildah_exit_code -ne 0 ]]; then
        log_error "Failed to load image into Docker daemon"
        log_error "${buildah_exec}"
        exit 1
    fi
    
    # docker load might not preserve the tag, so we need to tag it
    # Extract the loaded image name/ID from the output
    # Format can be: "Loaded image: name:tag" or "Loaded image ID: sha256:..."
    local loaded_image=""
    if echo "${buildah_exec}" | grep -qi "Loaded image:"; then
        # Extract image name:tag format
        loaded_image=$(echo "${buildah_exec}" | grep -i "Loaded image:" | sed -E 's/.*Loaded image: //' | head -n1 | tr -d '\r\n')
    elif echo "${buildah_exec}" | grep -qi "Loaded image ID:"; then
        # Extract just the sha256:... part
        loaded_image=$(echo "${buildah_exec}" | grep -i "Loaded image ID:" | sed -E 's/.*Loaded image ID: //' | head -n1 | tr -d '\r\n')
    fi
    
    if [[ -n "${loaded_image}" && "${loaded_image}" != "${IMAGE_NAME}:${IMAGE_TAG}" ]]; then
        log_info "Tagging loaded image ${loaded_image} as ${IMAGE_NAME}:${IMAGE_TAG}"
        set +e
        buildah_exec=$(
            docker tag "${loaded_image}" "${IMAGE_NAME}:${IMAGE_TAG}" \
                2>&1
        )
        buildah_exit_code=$?
        set -e
        if [[ $buildah_exit_code -ne 0 ]]; then
            log_error "Failed to tag image"
            log_error "${buildah_exec}"
            exit 1
        fi
    fi
    
    log_success "Image loaded into Docker daemon successfully"
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
# Use oci-archive (tar file) as source to avoid Docker API version issues
registry=$(retrieve_registry_from_manifest)
if [[ -n "${BUILD_TAR}" && -f "${BUILD_TAR}" ]]; then
    log_info "Pushing image to registry: ${registry}:${IMAGE_TAG}"
    # Use --all to copy all formats and preserve metadata including labels
    skopeo copy --all oci-archive:${BUILD_TAR} docker://${registry}:${IMAGE_TAG}
    log_success "Image pushed to registry successfully"
    # Verify labels in registry
    log_info "Verifying labels in registry..."
    registry_labels=$(skopeo inspect docker://${registry}:${IMAGE_TAG} --format '{{.Labels}}' 2>/dev/null || echo "")
    if [[ -n "${registry_labels}" ]]; then
        log_trace "Labels in registry: ${registry_labels}"
    else
        log_warn "No labels found in registry image"
    fi
    # Clean up temp tar file after registry push
    rm -f ${BUILD_TAR}
else
    log_error "Build tar file not found, cannot push to registry"
    exit 1
fi