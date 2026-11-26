#!/usr/bin/env bash
# Publish build progress as a GitHub commit status every few minutes.
#
# The Actions web log freezes on huge logs and SSH sessions drop, so this writes
# the latest ninja progress line to a commit status that can be read from the
# commit page, the GitHub mobile app or `gh api repos/OWNER/REPO/commits/SHA/status`.
# Best effort: any failure is ignored so it can never break the build.
#
# Usage: progress.sh start | stop | final <message>
# Needs: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, STAGE  (statuses: write)
set -uo pipefail
ROM_ROOT="${ROM_ROOT:-/home/runner/rom}"
DIAG="$ROM_ROOT/diagnostics"
LOG="$DIAG/build.log"
PIDF="$DIAG/progress.pid"
INTERVAL="${PROGRESS_INTERVAL:-180}"
CONTEXT="hsin/build stage ${STAGE:-?}"

post() {   # post <state> <description>
  [[ -n "${GH_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_SHA:-}" ]] || return 0
  gh api -X POST "repos/$GITHUB_REPOSITORY/statuses/$GITHUB_SHA" \
    -f state="$1" -f context="$CONTEXT" -f description="${2:0:140}" \
    -f target_url="${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/${GITHUB_RUN_ID:-0}" \
    >/dev/null 2>&1 || true
}

loop() {
  local prev start
  prev=$(wc -l < "$ROM_ROOT/src/out/.ninja_log" 2>/dev/null || echo 0)
  start=$(date +%s)
  while sleep "$INTERVAL"; do
    local line x y pct all avail mem el
    line=$(tail -c 60000 "$LOG" 2>/dev/null | grep -aoE '\[ *[0-9]+% [0-9]+/[0-9]+\]' | tail -1)
    [[ -n "$line" ]] || continue
    x=$(sed -E 's/.* ([0-9]+)\/([0-9]+)\].*/\1/' <<<"$line")
    y=$(sed -E 's/.* ([0-9]+)\/([0-9]+)\].*/\2/' <<<"$line")
    pct=$(( x * 100 / (y > 0 ? y : 1) ))
    all=$(( (prev + x) * 100 / (prev + y > 0 ? prev + y : 1) ))
    avail=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
    mem=$(awk '/MemAvailable/ {printf "%.1f", $2/1048576}' /proc/meminfo)
    el=$(( ($(date +%s) - start) / 60 ))
    post pending "${x}/${y} (${pct}% of this stage, ~${all}% overall) ${el}min, disk ${avail}G free, mem ${mem}G free"
  done
}

case "${1:-}" in
  start) mkdir -p "$DIAG"; nohup bash "$0" loop >/dev/null 2>&1 & echo $! > "$PIDF" ;;
  stop)  [[ -f "$PIDF" ]] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF" ;;
  final) post "${3:-success}" "${2:-finished}" ;;
  loop)  loop ;;
  *) echo "usage: $0 start|stop|final <msg> [state]" >&2; exit 2 ;;
esac
