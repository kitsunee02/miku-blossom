#!/usr/bin/env bash
# HsinOS CI source-tree fixups for Android 15.
# Runs after repo sync and before envsetup/source pruning.
set -euo pipefail

cd "${SRC:?SRC must be set to the source tree}"

remove_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    echo "[fixups] removing source-tree path: $path"
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

require_module() {
  local bp_file="$1"
  local module_name="$2"
  require_file "$bp_file"
  if ! grep -Eq '^[[:space:]]*name:[[:space:]]*"'"${module_name}"'",[[:space:]]*$' "$bp_file"; then
    echo "::error::required Soong module '$module_name' is not defined in $bp_file"
    exit 1
  fi
  echo "[fixups] verified Soong module '$module_name' in $bp_file"
}

# Targeted removals for conflicts/unneeded device-specific interfaces.
remove_path "hardware/lineage/interfaces/sensors"
remove_path "hardware/lineage/interfaces/biometrics/fingerprint"
remove_path "hardware/interfaces/biometrics/fingerprint/2.1/default"

# The Lineage power-libperfmgr namespace imports hardware/google/pixel.
# blossom builds the Pixel power HAL instead, so avoid parsing this unused
# conflicting Lineage namespace.
remove_path "hardware/lineage/interfaces/power-libperfmgr"

# blossom's device.mk uses the Pixel power service, so these projects must
# remain synced even though the base removal manifest excludes some Pixel code.
require_file "hardware/google/interfaces/Android.bp"
require_file "hardware/google/pixel/Android.bp"
require_file "hardware/google/pixel/power-libperfmgr/Android.bp"

# external/crosvm's rutabaga_gfx targets depend on this module. The Hsin
# manifest now keeps both gfxstream and aemu, so do not disable crosvm modules.
require_file "external/crosvm/rutabaga_gfx/Android.bp"
require_file "packages/modules/Virtualization/Android.bp"
require_file "hardware/google/aemu/Android.bp"
require_file "hardware/google/gfxstream/Android.bp"
require_module "hardware/google/gfxstream/host/Android.bp" "libgfxstream_backend"

echo "[fixups] completed Android 15 source-tree fixups"
