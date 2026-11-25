#!/usr/bin/env bash
# Resolve Hsin hsin.dependencies before the first pinned manifest is generated.
# Hsin roomservice expects the local device manifest to be named hsin.xml.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SRC"

ROOMSERVICE="vendor/hsin/build/tools/roomservice.py"
if [[ ! -f "$ROOMSERVICE" ]]; then
  echo "::error::Hsin roomservice not found at $ROOMSERVICE after repo sync"
  exit 1
fi

echo "[roomservice] resolving dependencies for $HSIN_PRODUCT (branch: $HSIN_BRANCH)"
ROOMSERVICE_DEFAULT_BRANCH="$HSIN_BRANCH" \
  python3 "$ROOMSERVICE" "$HSIN_PRODUCT" true
