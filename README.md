# Deerhide / Template for Container Image

## Pre-requisites

### Install `docker`
[See Docker documentation](https://docs.docker.com/get-docker/)

### Install tools

```bash
./scripts/install_tools.sh
```

## How to build the container image

### Update `manifest.yaml`

```yaml
name: deerhide_container_example
tags: 
  - latest
registry: ghcr.io/deerhide/template_container_image
build:
  format: oci
  args:
    - APP_UID=1000
    - UBUNTU_VERSION=24.04
```

### Authenticate to the container registry

```bash
skopeo login ghcr.io
```

### Launch Builder

```bash
./scripts/builder.sh
```
