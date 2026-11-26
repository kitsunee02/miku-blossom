#!/usr/bin/env bash
# Execute one build window.
# Usage: build-stage.sh <deadline_epoch> [resumed=0|1] [target]
# Writes: $ROM_ROOT/status = done | timeout | failed
set -uo pipefail
source "$(dirname "$0")/env.sh"
# ulimit is process-local, so set it in this shell before starting Soong.
ulimit -n 65535 || true
DEADLINE="$1"
RESUMED="${2:-0}"
TARGET="${3:-$BUILD_TARGET}"
cd "$SRC"

set +u
if ! source "$REPO_DIR/scripts/lunch.sh"; then
  echo failed > "$ROM_ROOT/status"
  exit 1
fi
set -u

if [[ "$RESUMED" == 1 ]]; then
  # On a fresh runner, synced sources are newer than restored out/. Give source
  # files a stable old mtime so ninja can reuse completed outputs from earlier stages.
  echo "[stage] setting source mtimes to the baseline timestamp"
  find . -path ./out -prune -o -path ./.repo -prune -o -print0 \
    | xargs -0 -P"$(nproc)" -n 5000 touch -h -d @946684800 -- 2>/dev/null || true
fi

NOW="$(date +%s)"
SECS=$((DEADLINE - NOW))
echo "[stage] build time remaining: $((SECS / 60)) minutes"
if (( SECS < 600 )); then
  echo timeout > "$ROM_ROOT/status"
  exit 0
fi

JOBS="$(nproc)"

# Keep Go (soong_build and friends) from growing past what the runner can hold,
# and keep the VM responsive by killing the biggest process if memory runs out.
export GOMEMLIMIT="${GOMEMLIMIT:-9GiB}"
export GOGC="${GOGC:-75}"
"$REPO_DIR/scripts/mem-guard.sh" start || true

set +e
timeout -s INT -k 600 "$SECS" build/soong/soong_ui.bash --make-mode "$TARGET" -j"$JOBS"
rc=$?
set -e
"$REPO_DIR/scripts/mem-guard.sh" stop || true
# Show the memory trace in the job log (the artifact is not readable if the job dies).
if [[ -f "$ROM_ROOT/diagnostics/mem.log" ]]; then
  echo "[mem] peak/guard summary:"
  grep -E '^!!!|^===' "$ROM_ROOT/diagnostics/mem.log" | tail -n 20 || true
  echo "[mem] last samples:"
  tail -n 25 "$ROM_ROOT/diagnostics/mem.log" || true
  echo "[mem] lowest MemAvailable (MB):"
  grep -oE 'avail=[0-9]+' "$ROM_ROOT/diagnostics/mem.log" | cut -d= -f2 | sort -n | head -1 || true
fi
case "$rc" in
  0)   echo done > "$ROM_ROOT/status" ;;
  124) echo timeout > "$ROM_ROOT/status" ;;
  *)   echo failed > "$ROM_ROOT/status" ;;
esac

echo "[stage] soong rc=$rc status=$(cat "$ROM_ROOT/status")"
df -h "$ROM_ROOT"
du -sh out 2>/dev/null || true
exit 0
