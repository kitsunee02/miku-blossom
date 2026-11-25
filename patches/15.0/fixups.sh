#!/usr/bin/env bash
# HsinOS CI source-tree fixups for Android 15.
# Runs from scripts/apply-patches.sh before envsetup and source pruning.
set -euo pipefail

cd "${SRC:?SRC must be set to the source tree}"

remove_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    echo "[fixups] removing requested source-tree path: $path"
    rm -rf -- "$path"
  else
    echo "[fixups] already absent: $path"
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "::error::required source file is missing: $path"
    exit 1
  fi
  echo "[fixups] verified required source file: $path"
}

# Apply the three targeted source-tree removals requested for this build.
remove_path "hardware/lineage/interfaces/sensors"
remove_path "hardware/lineage/interfaces/biometrics/fingerprint"
remove_path "hardware/interfaces/biometrics/fingerprint/2.1/default"

# blossom/device.mk builds android.hardware.power-service.pixel-libperfmgr
# and the Lineage power-libperfmgr namespace imports hardware/google/pixel.
# The base Hsin manifest removes that AOSP project, so manifests/15.0/hsin.xml
# restores it. Fail here, before Soong, if the project was not synced.
require_file "hardware/google/interfaces/Android.bp"
require_file "hardware/google/pixel/Android.bp"
require_file "hardware/google/pixel/power-libperfmgr/Android.bp"

echo "[fixups] completed Android 15 source-tree fixups"
