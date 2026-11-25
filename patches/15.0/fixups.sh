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

disable_soong_module() {
  local bp_file="$1"
  local module_name="$2"

  if [[ ! -f "$bp_file" ]]; then
    echo "[fixups] blueprint not found, skipping: $bp_file"
    return 0
  fi

  python3 - "$bp_file" "$module_name" <<'PY'
import re
import sys

bp_path, mod_name = sys.argv[1], sys.argv[2]
with open(bp_path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(
    r'(^\s*name:\s*"' + re.escape(mod_name) + r'",\s*\n)',
    re.MULTILINE,
)

match = pattern.search(content)
if not match:
    print(f"[fixups] module '{mod_name}' not found in {bp_path}")
    sys.exit(0)

# Check if 'enabled:' is already present right after 'name:'
after_name = content[match.end():match.end() + 200]
if re.search(r'^\s*enabled:\s*', after_name, re.MULTILINE):
    print(f"[fixups] '{mod_name}' already has an enabled property in {bp_path}")
    sys.exit(0)

indent_match = re.match(r'^(\s*)name:', match.group(1))
indent = indent_match.group(1) if indent_match else "    "

new_content, count = pattern.subn(
    r'\1' + f'{indent}enabled: false,\n',
    content,
    count=1,
)

if count > 0:
    with open(bp_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"[fixups] disabled '{mod_name}' in {bp_path}")
PY
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

# ROM manifest omits gfxstream, so disable the rutabaga_gfx gfxstream target
# instead of dropping external/crosvm (needed by Virtualization/crosvm_defaults).
disable_soong_module "external/crosvm/rutabaga_gfx/Android.bp" "librutabaga_gfx_gfxstream"

# blossom/device.mk still builds android.hardware.power-service.pixel-libperfmgr
# from hardware/google/pixel, which manifests/15.0/hsin.xml restores.
require_file "hardware/google/interfaces/Android.bp"
require_file "hardware/google/pixel/Android.bp"

echo "[fixups] completed Android 15 source-tree fixups"
