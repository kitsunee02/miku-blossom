#!/usr/bin/env bash
# Hsin roomservice expects the device's local manifest to be named hsin.xml.
# This runs dependency-only mode so hsin.dependencies (when present) is synced
# before the pinned manifest is generated for all subsequent build stages.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SRC"

ROOMSERVICE="vendor/hsin/build/tools/roomservice.py"
if [[ -f "$ROOMSERVICE" ]]; then
  DEVICE_PRODUCT="${HSIN_PRODUCT}"
  echo "[roomservice] resolving dependencies for ${DEVICE_PRODUCT}"
  python3 "$ROOMSERVICE" "$DEVICE_PRODUCT" true
else
  echo "[roomservice] not found in Hsin source; skipping dependency expansion"
fi
