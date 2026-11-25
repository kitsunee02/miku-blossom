#!/usr/bin/env bash
# Sync HsinOS Android 15 and the blossom local manifest.
# Usage: sync.sh [pinned-manifest.xml]
set -euo pipefail
source "$(dirname "$0")/env.sh"
PINNED="${1:-}"
mkdir -p "$SRC"
cd "$SRC"

repo init -q --depth=1 --no-clone-bundle --git-lfs \
  -u "$HSIN_MANIFEST_URL" -b "$HSIN_BRANCH"

JOBS=$(( $(nproc) * 4 ))
SYNC_ARGS=(-c -j"$JOBS" --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune --fail-fast)

if [[ -n "$PINNED" ]]; then
  # All local projects and their resolved commit SHAs are already embedded in pinned.xml.
  rm -rf .repo/local_manifests
  mkdir -p .repo/manifests
  cp "$PINNED" .repo/manifests/pinned.xml
  sync_cmd=(repo sync -m pinned.xml "${SYNC_ARGS[@]}")
else
  mkdir -p .repo/local_manifests
  cp "$REPO_DIR/manifests/$ROM_VERSION/"*.xml .repo/local_manifests/
  sync_cmd=(repo sync "${SYNC_ARGS[@]}")
fi

for attempt in 1 2 3; do
  if "${sync_cmd[@]}"; then
    break
  fi
  echo "::warning::repo sync attempt ${attempt} failed"
  if [[ "$attempt" == 3 ]]; then exit 1; fi
  sleep 20
done

if [[ -z "$PINNED" ]]; then
  "$REPO_DIR/scripts/resolve-deps.sh"
  repo manifest -r -o "$ROM_ROOT/pinned.xml"
  echo "Pinned manifest written to $ROM_ROOT/pinned.xml"
else
  if [[ "$(realpath "$PINNED")" != "$(realpath -m "$ROM_ROOT/pinned.xml")" ]]; then
    cp "$PINNED" "$ROM_ROOT/pinned.xml"
  fi
fi

du -sh "$SRC" 2>/dev/null || true
df -h "$ROM_ROOT"
