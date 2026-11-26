#!/usr/bin/env bash
# Memory watchdog for the build step.
#
# When Soong/Kati/ninja exhaust RAM and swap, the whole VM thrashes and the
# GitHub runner agent stops answering ("The hosted runner lost communication
# with the server"). The job then dies without logs. This watchdog
#   * samples memory/PSI every few seconds into $ROM_ROOT/diagnostics/mem.log,
#   * kills the biggest build process before the VM stalls, so the job fails
#     normally with a readable error and the log can be uploaded.
#
# Usage: mem-guard.sh start | stop
set -uo pipefail
ROM_ROOT="${ROM_ROOT:-/home/runner/rom}"
DIAG="$ROM_ROOT/diagnostics"
LOG="$DIAG/mem.log"
PIDF="$DIAG/mem-guard.pid"
INTERVAL="${MEM_GUARD_INTERVAL:-5}"
PSI_LIMIT="${MEM_GUARD_PSI_FULL:-60}"      # memory "full" avg10 percentage
PSI_STRIKES="${MEM_GUARD_STRIKES:-6}"      # consecutive samples over the limit
MIN_AVAIL_MB="${MEM_GUARD_MIN_AVAIL_MB:-350}"

run() {
  local strikes=0
  echo "=== mem-guard started $(date -Is) interval=${INTERVAL}s psi>=${PSI_LIMIT} x${PSI_STRIKES} avail<${MIN_AVAIL_MB}MB" >> "$LOG"
  while sleep "$INTERVAL"; do
    local avail swapfree psi top
    avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    swapfree=$(awk '/SwapFree/ {print int($2/1024)}' /proc/meminfo)
    psi=$(awk '/^full/ {split($2,a,"="); print int(a[2])}' /proc/pressure/memory 2>/dev/null)
    psi=${psi:-0}
    top=$(ps -eo rss,comm --sort=-rss | awk 'NR==2 {printf "%s:%dMB", $2, $1/1024}')
    echo "$(date +%T) avail=${avail}MB swapfree=${swapfree}MB psi_full=${psi} top=${top}" >> "$LOG"

    if (( psi >= PSI_LIMIT )); then strikes=$((strikes + 1)); else strikes=0; fi
    if (( strikes >= PSI_STRIKES )) || { (( avail < MIN_AVAIL_MB )) && (( swapfree < 1024 )); }; then
      # Biggest process that is not the runner agent or basic system plumbing.
      local line pid rss comm
      line=$(ps -eo pid,rss,comm --sort=-rss \
        | awk 'NR>1 && $3 !~ /^(Runner|Runner\.|systemd|sshd|tailscaled|dockerd|containerd|node|mem-guard)/ {print; exit}')
      read -r pid rss comm <<<"$line"
      {
        echo "!!! $(date -Is) memory exhausted (avail=${avail}MB swapfree=${swapfree}MB psi_full=${psi});"
        echo "!!! killing $comm pid=$pid rss=$((rss / 1024))MB to keep the runner alive"
        ps -eo pid,rss,%mem,etime,args --sort=-rss | head -n 15
      } >> "$LOG"
      echo "::error::mem-guard: out of memory, killing $comm (rss=$((rss / 1024))MB). See diagnostics/mem.log" >&2
      [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null
      strikes=0
      sleep 10
    fi
  done
}

case "${1:-}" in
  start)
    mkdir -p "$DIAG"
    free -h >> "$LOG" 2>&1; swapon --show >> "$LOG" 2>&1
    nohup bash "$0" run >/dev/null 2>&1 &
    echo $! > "$PIDF"
    ;;
  stop)
    [[ -f "$PIDF" ]] && kill "$(cat "$PIDF")" 2>/dev/null
    rm -f "$PIDF"
    ;;
  run) run ;;
  *) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac
