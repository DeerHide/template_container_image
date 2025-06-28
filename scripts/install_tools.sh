#!/usr/bin/env bash

# Include the utils library
source scripts/lib_utils.sh

set -eo pipefail

# Install dive
DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
log_info "Installing dive v${DIVE_VERSION}"
curl -OL https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb
sudo apt install ./dive_${DIVE_VERSION}_linux_amd64.deb
rm dive_${DIVE_VERSION}_linux_amd64.deb

# Install trivy
sudo apt-get install wget gnupg
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
TRIVY_REPO_LINE="deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main"
TRIVY_LIST_FILE="/etc/apt/sources.list.d/trivy.list"
# Only add the line if it doesn't already exist
if ! grep -Fxq "$TRIVY_REPO_LINE" "$TRIVY_LIST_FILE" 2>/dev/null; then
  echo "$TRIVY_REPO_LINE" | sudo tee -a "$TRIVY_LIST_FILE"
fi
sudo apt-get update
sudo apt-get install trivy -y

# Install buildah
sudo apt-get install buildah -y

# Install yq\
VERSION="v4.45.4"
BINARY="yq_linux_amd64"
wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -O - |\
  tar xz && sudo mv ${BINARY} /usr/local/bin/yq

# Clean up
if [[ -f "yq.1" ]]; then
  rm yq.1
fi

# Install skopeo
sudo apt-get -y update
sudo apt-get -y install skopeo