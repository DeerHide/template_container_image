#!/usr/bin/env bash

# Include the utils library
source scripts/lib_utils.sh

set -eo pipefail

DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
log_info "Installing dive v${DIVE_VERSION}"
curl -OL https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb
sudo apt install ./dive_${DIVE_VERSION}_linux_amd64.deb
rm dive_${DIVE_VERSION}_linux_amd64.deb