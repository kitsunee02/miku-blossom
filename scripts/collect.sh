#!/usr/bin/env bash
# Collect the final Hsin OTA ZIP plus useful images and checksums.
set -euo pipefail
source "$(dirname "$0")/env.sh"
PRODUCT_OUT="$SRC/out/target/product/$DEVICE"
DEST="$ROM_ROOT/release"
mkdir -p "$DEST"
shopt -s nullglob

zip_files=("$PRODUCT_OUT"/*.zip)
collected=0
for file in "${zip_files[@]}"; do
  base="$(basename "$file")"
  [[ "$base" == *target_files* ]] && continue
  [[ "$base" == *-ota-* ]] && continue
  cp -v "$file" "$DEST/"
  [[ -f "$file.sha256sum" ]] && cp -v "$file.sha256sum" "$DEST/"
  collected=$((collected + 1))
done
if (( collected == 0 )); then
  echo "No final Hsin ZIP found in $PRODUCT_OUT" >&2
  ls -lah "$PRODUCT_OUT" || true
  exit 1
fi

for image in boot.img dtbo.img vbmeta.img vbmeta_system.img vbmeta_vendor.img super_empty.img; do
  [[ -f "$PRODUCT_OUT/$image" ]] && cp -v "$PRODUCT_OUT/$image" "$DEST/"
done
(
  cd "$DEST"
  sha256sum * > SHA256SUMS
)
ls -lh "$DEST"
