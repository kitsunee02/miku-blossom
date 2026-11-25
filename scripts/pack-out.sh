#!/usr/bin/env bash
# Keep only out/ and split a zstd-compressed tar into upload-friendly chunks.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SRC"
find . -mindepth 1 -maxdepth 1 ! -name out -exec rm -rf {} +
rm -f out/error.log out/verbose.log* out/soong.log 2>/dev/null || true
mkdir -p "$ROM_ROOT/parts"
df -h "$ROM_ROOT"
tar -C "$SRC" -cf - out | zstd -T0 -3 -q | split -b 1900M - "$ROM_ROOT/parts/out.tar.zst."
rm -rf "$SRC/out"
ls -lh "$ROM_ROOT/parts"
du -sh "$ROM_ROOT/parts"
