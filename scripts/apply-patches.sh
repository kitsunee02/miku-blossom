#!/usr/bin/env bash
# Apply CI patches/overrides, then source envsetup once so the device's
# vendorsetup.sh can run patch_camera.sh and applyPatches.sh before git pruning.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SRC"

PDIR="$REPO_DIR/patches/$ROM_VERSION"
if [[ -d "$PDIR" ]]; then
  while IFS= read -r -d '' patch_file; do
    relative="${patch_file#$PDIR/}"
    project="$(dirname "$relative")"
    if git -C "$project" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
      echo "[patch] already applied: $relative"
    elif git -C "$project" apply --whitespace=nowarn "$patch_file"; then
      echo "[patch] applied: $relative"
    else
      echo "::error::failed to apply patch: $relative"
      exit 1
    fi
  done < <(find "$PDIR" -type f -name '*.patch' -print0 | sort -z)
fi

ODIR="$REPO_DIR/overrides/$ROM_VERSION"
if [[ -d "$ODIR" ]] && [[ -n "$(find "$ODIR" -type f ! -name .gitkeep -print -quit)" ]]; then
  rsync -a --exclude .gitkeep "$ODIR/" "$SRC/"
  echo "[override] copied overrides/$ROM_VERSION"
fi

HOOK="$PDIR/fixups.sh"
if [[ -x "$HOOK" ]]; then
  echo "[fixups] running $HOOK"
  SRC="$SRC" bash "$HOOK"
fi

# Device vendorsetup.sh on blossom runs patch_camera.sh and applyPatches.sh.
# patchelf is installed by setup-runner.sh; these hooks must run before prune.sh.
if [[ -f build/envsetup.sh ]]; then
  env_log="$ROM_ROOT/envsetup-prep.log"
  if ! (source build/envsetup.sh) >"$env_log" 2>&1; then
    tail -n 160 "$env_log" || true
    echo "::error::sourcing build/envsetup.sh failed while applying device setup hooks"
    exit 1
  fi
  echo "[device] build/envsetup.sh sourced; vendorsetup hooks have run"
fi
