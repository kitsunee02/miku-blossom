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
# hardware/google/pixel/kernel_headers defines qti_kernel_headers, which vendor/hsin
# (build/soong/Android.bp) already provides; Kati aborts on the duplicate
# MODULE.TARGET.HEADER_LIBRARIES.qti_kernel_headers.recovery.
remove_path "hardware/google/pixel/kernel_headers"
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

# Hsin SystemUI's ISystemUiProxy (inherited from Miku/Lineage) has extra methods,
# injectLongPress(int) and injectDoublePress(int). Stock AOSP Launcher3 (swapped in for
# the Miku launcher) does not implement them, so Launcher3QuickStepLib fails to compile
# (javac reports only the first missing one). Add forwarding methods when missing.
LSUP="packages/apps/Launcher3/quickstep/src/com/android/quickstep/SystemUiProxy.java"
require_file "$LSUP"
python3 - "$LSUP" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r"public class SystemUiProxy implements [^{]*\{\n", s)
if not m or "mSystemUiProxy" not in s:
    sys.exit("::error::SystemUiProxy class anchor or mSystemUiProxy not found in " + p)
add = ""
for name in ("injectLongPress", "injectDoublePress"):
    if name in s:
        print("[fixups] Launcher3 SystemUiProxy already has " + name)
        continue
    add += """
    @Override
    public void %s(int keyCode) {
        if (mSystemUiProxy != null) {
            try {
                mSystemUiProxy.%s(keyCode);
            } catch (RemoteException e) {
                Log.w(TAG, "Failed call %s", e);
            }
        }
    }
""" % (name, name, name)
    print("[fixups] adding " + name + " to Launcher3 SystemUiProxy")
if add:
    open(p, "w").write(s[:m.end()] + add + s[m.end():])
PY

# Launcher3 files outside SystemUiProxy that implement ISystemUiProxy would need the same.
if grep -rl "implements ISystemUiProxy" packages/apps/Launcher3 --include=*.java | grep -v "quickstep/src/com/android/quickstep/SystemUiProxy.java"; then
  echo "[fixups] note: other ISystemUiProxy implementers listed above"
fi

echo "[fixups] completed Android 15 source-tree fixups"
