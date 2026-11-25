#!/usr/bin/env bash
# Shared build configuration. Override these through workflow inputs or env vars.
set -o allexport

export ROM_ROOT="${ROM_ROOT:-/home/runner/rom}"
export SRC="${SRC:-${ROM_ROOT}/src}"
export REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export ROM_VERSION="${ROM_VERSION:-15.0}"
export HSIN_MANIFEST_URL="${HSIN_MANIFEST_URL:-https://github.com/hsin-os/manifest.git}"
export HSIN_BRANCH="${HSIN_BRANCH:-Moon_fox}"
export DEVICE="${DEVICE:-blossom}"
export HSIN_PRODUCT="${HSIN_PRODUCT:-hsin_blossom}"
export LUNCH_TARGET="${LUNCH_TARGET:-hsin_blossom-userdebug}"
export BUILD_TARGET="${BUILD_TARGET:-hsin}"
export VARIANT="${VARIANT:-userdebug}"

export BUILD_USERNAME="${BUILD_USERNAME:-hsin-ci}"
export BUILD_HOSTNAME="${BUILD_HOSTNAME:-hsin-blossom-ci}"
export TZ=UTC
export LC_ALL=C.UTF-8
export USE_CCACHE=0
export SKIP_ABI_CHECKS=true
export PATH="${HOME}/bin:${PATH}"

set +o allexport
