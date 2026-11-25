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
 
# Targeted source-tree removals.
remove_path "hardware/lineage/interfaces/sensors"
remove_path "hardware/lineage/interfaces/biometrics/fingerprint"
remove_path "hardware/interfaces/biometrics/fingerprint/2.1/default"
remove_path "platform_testing/tools/automotive" 
# Lineage's power-libperfmgr namespace imports hardware/google/pixel, which
# Soong cannot resolve in this tree ("namespace hardware/google/pixel does not
# exist"). blossom does not use that Lineage HAL, so drop it before Soong parses
# every Android.bp.
remove_path "hardware/lineage/interfaces/power-libperfmgr"
 
# blossom/device.mk still builds android.hardware.power-service.pixel-libperfmgr
# from hardware/google/pixel, which manifests/15.0/hsin.xml restores.
require_file "hardware/google/interfaces/Android.bp"
require_file "hardware/google/pixel/Android.bp"
 
echo "[fixups] completed Android 15 source-tree fixups"
 
