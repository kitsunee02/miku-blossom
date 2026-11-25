#!/usr/bin/env bash
# HsinOS CI source-tree fixups for Android 15.
# Runs from scripts/apply-patches.sh before envsetup and source pruning.
set -euo pipefail

cd "${SRC:?SRC must be set to the source tree}"

remove_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    echo "[fixups] removing conflicting/unneeded path: $path"
    rm -rf -- "$path"
  else
    echo "[fixups] already absent: $path"
  fi
}

# Resolve the hardware/lineage/interfaces power-libperfmgr namespace
# collision with the Pixel namespace referenced by Soong.
remove_path "hardware/lineage/interfaces/sensors"
remove_path "hardware/lineage/interfaces/biometrics/fingerprint"
remove_path "hardware/interfaces/biometrics/fingerprint/2.1/default"

echo "[fixups] completed Android 15 source-tree fixups"
