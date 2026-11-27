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

# Put the build in its own cgroup with a soft memory ceiling (memory.high). When
# soong_build wants more than the ceiling the kernel throttles and swaps out only
# that cgroup, instead of reclaiming pages from the runner agent and sshd. That
# is what turns "VM starved -> hosted runner lost communication" into a slow but
# alive build. Best effort: silently skipped if cgroup v2 is not writable.
if [[ -z "${BUILD_MEM_HIGH:-}" ]]; then
  _total_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  BUILD_MEM_HIGH="$(( _total_mb - 3500 ))M"
fi
CG=/sys/fs/cgroup/hsinbuild
if [[ -f /sys/fs/cgroup/cgroup.controllers ]] && grep -qw memory /sys/fs/cgroup/cgroup.controllers; then
  sudo sh -c "echo +memory > /sys/fs/cgroup/cgroup.subtree_control" 2>/dev/null || true
  if sudo mkdir -p "$CG" 2>/dev/null \
     && sudo sh -c "echo $BUILD_MEM_HIGH > $CG/memory.high && echo $$ > $CG/cgroup.procs" 2>/dev/null; then
    echo "[stage] build cgroup $CG memory.high=$BUILD_MEM_HIGH"
  else
    echo "[stage] build cgroup not available; continuing without memory.high"
  fi
fi

set +e
# Keep a copy of the build output so progress can be published and tailed.
mkdir -p "$ROM_ROOT/diagnostics"
BUILD_LOG="$ROM_ROOT/diagnostics/build.log"
: > "$BUILD_LOG"
"$REPO_DIR/scripts/progress.sh" start || true
timeout -s INT -k 600 "$SECS" build/soong/soong_ui.bash --make-mode "$TARGET" -j"$JOBS" -k 2>&1 | tee -a "$BUILD_LOG"
rc=${PIPESTATUS[0]}
set -e
"$REPO_DIR/scripts/progress.sh" stop || true
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
case "$(cat "$ROM_ROOT/status")" in
  done)    "$REPO_DIR/scripts/progress.sh" final "stage ${STAGE:-?} finished: ROM built" success || true ;;
  timeout) "$REPO_DIR/scripts/progress.sh" final "stage ${STAGE:-?} hit its deadline, next stage resumes" success || true ;;
  *)       "$REPO_DIR/scripts/progress.sh" final "stage ${STAGE:-?} FAILED, see the job log" failure || true ;;
esac
df -h "$ROM_ROOT"
du -sh out 2>/dev/null || true
exit 0
