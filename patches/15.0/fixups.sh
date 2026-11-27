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

# Hsin SystemUI's ISystemUiProxy (inherited from Miku/Lineage) has methods that stock AOSP
# Launcher3 (swapped in for the Miku launcher) does not implement, which breaks
# Launcher3QuickStepLib (javac reports only the first missing one, so doing this one method at
# a time cost whole build runs). Generate forwarding methods for EVERY aidl method the
# Launcher3 SystemUiProxy lacks, so any further Hsin-side additions are covered too.
LSUP="packages/apps/Launcher3/quickstep/src/com/android/quickstep/SystemUiProxy.java"
LAIDL="frameworks/base/packages/SystemUI/shared/src/com/android/systemui/shared/recents/ISystemUiProxy.aidl"
require_file "$LSUP"
require_file "$LAIDL"
python3 - "$LSUP" "$LAIDL" <<'PY'
import re, sys
p, aidl = sys.argv[1], sys.argv[2]
s = open(p).read()
a = re.sub(r"/\*.*?\*/|//[^\n]*", "", open(aidl).read(), flags=re.S)
m = re.search(r"public class SystemUiProxy implements [^{]*\{\n", s)
if not m or "mSystemUiProxy" not in s:
    sys.exit("::error::SystemUiProxy class anchor or mSystemUiProxy not found in " + p)
prims = {"int", "long", "float", "double", "boolean", "byte", "short", "char", "String", "CharSequence"}
add, bad = "", []
for mm in re.finditer(r"(?:oneway\s+)?void\s+(\w+)\s*\(([^)]*)\)\s*=\s*\d+\s*;", a):
    name, raw = mm.group(1), mm.group(2).strip()
    if re.search(r"\bvoid\s+" + name + r"\s*\(", s) or re.search(r"public\s+\w+\s+" + name + r"\s*\(", s):
        continue
    params = []
    for part in [x.strip() for x in raw.split(",") if x.strip()]:
        part = re.sub(r"^(in|out|inout)\s+", "", part)
        t, n = part.rsplit(None, 1)
        base = t.replace("[]", "")
        if base not in prims and not re.search(r"import\s+[\w.]+\." + re.escape(base) + r";", s):
            bad.append(name + ": " + t)
        params.append((t, n))
    sig = ", ".join(t + " " + n for t, n in params)
    call = ", ".join(n for _, n in params)
    add += """
    @Override
    public void %s(%s) {
        if (mSystemUiProxy != null) {
            try {
                mSystemUiProxy.%s(%s);
            } catch (RemoteException e) {
                Log.w(TAG, "Failed call %s", e);
            }
        }
    }
""" % (name, sig, name, call, name)
    print("[fixups] adding " + name + "(" + sig + ") to Launcher3 SystemUiProxy")
if bad:
    sys.exit("::error::missing imports for generated SystemUiProxy methods: " + "; ".join(bad))
if add:
    open(p, "w").write(s[:m.end()] + add + s[m.end():])
else:
    print("[fixups] Launcher3 SystemUiProxy already implements every ISystemUiProxy method")
PY

echo "[fixups] completed Android 15 source-tree fixups"
