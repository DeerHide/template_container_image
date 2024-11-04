#!/usr/bin/env bash

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
WHITE_GRAY='\033[1;30m'
DARK_GRAY='\033[1;90m'
NC='\033[0m'

log_info() {
  echo -e "${WHITE}[INFO] $1${NC}"
}
log_error() {
  echo -e "${RED}[ERROR] $1${NC}"
}
log_warn() {
  echo -e "${YELLOW}[WARN] $1${NC}"
}
log_success() {
  echo -e "${GREEN}[SUCCESS] $1${NC}"
}
log_trace() {
  echo -e "${DARK_GRAY}[TRACE] $1${NC}"
}