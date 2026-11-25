#!/usr/bin/env bash
# Remove CI-unneeded clang revisions and, by default, repo git object databases.
# Set KEEP_GIT=1 if a future Hsin build step needs git history/object access.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SRC"

CLANG_DIR=prebuilts/clang/host/linux-x86
if [[ -d "$CLANG_DIR" ]]; then
  keep="$(grep -rhoE 'clang-r[0-9]+[a-z]?' build/soong build/make/core \
    build/make/target vendor/hsin/build vendor/hsin/config 2>/dev/null \
    | sort -u | tr '\n' ' ')"
  echo "[prune] clang revisions to keep: ${keep} clang-stable"
  for dir in "$CLANG_DIR"/clang-r*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ " $keep " == *" $name "* ]] && continue
    echo "[prune] removing $dir ($(du -sh "$dir" | cut -f1))"
    rm -rf "$dir"
  done
fi

if [[ "${KEEP_GIT:-0}" != 1 ]]; then
  echo "[prune] removing .repo project object stores"
  du -sh .repo/project-objects .repo/projects 2>/dev/null || true
  rm -rf .repo/project-objects .repo/projects
fi

df -h "$ROM_ROOT"
sudo btrfs filesystem usage -T "$ROM_ROOT" 2>/dev/null | head -8 || true
