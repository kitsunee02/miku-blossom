#!/usr/bin/env bash
# Create a compressed btrfs workspace from runner free space, plus swap.
# Usage: disk-setup.sh [mountpoint] [swap_gb]
set -euo pipefail
MP="${1:-/home/runner/rom}"
SWAP_GB="${2:-24}"

sudo swapoff -a || true
sudo rm -f /mnt/swapfile /swapfile || true

ROOT_DEV="$(df --output=source / | tail -1)"
MNT_DEV="$(df --output=source /mnt | tail -1)"
ROOT_FREE_MB="$(df --output=avail -B1M / | tail -1)"
MNT_FREE_MB="$(df --output=avail -B1M /mnt | tail -1)"

# When / and /mnt share a filesystem, protect at least 40 GiB for the ROM
# workspace (after leaving 5 GiB for the runner/apt/logs). Only use the
# remaining space for disk swap. With separate filesystems, swap comes from
# /mnt and the root workspace remains independent.
ROOT_RESERVE_MB=5120
MIN_WORKSPACE_MB=40960
if [[ "$ROOT_DEV" == "$MNT_DEV" ]]; then
  SWAP_BUDGET_MB=$((ROOT_FREE_MB - ROOT_RESERVE_MB - MIN_WORKSPACE_MB))
else
  SWAP_BUDGET_MB=$((MNT_FREE_MB - 2048))
fi

SWAP_TARGET_MB=$((SWAP_GB * 1024))
SWAP_MB=$((SWAP_BUDGET_MB < SWAP_TARGET_MB ? SWAP_BUDGET_MB : SWAP_TARGET_MB))
if (( SWAP_MB >= 1024 )); then
  SWAPF=/mnt/swapfile
  sudo fallocate -l "${SWAP_MB}M" "$SWAPF"
  sudo chmod 600 "$SWAPF"
  sudo mkswap -q "$SWAPF"
  sudo swapon -p 0 "$SWAPF"
  echo "Created ${SWAP_MB} MiB disk swap"
else
  echo "Skipping disk swap: workspace capacity has priority"
fi

# Optional compressed RAM swap.
( set +e
  sudo modprobe zram 2>/dev/null
  Z="$(sudo zramctl --find --size 8G --algorithm zstd 2>/dev/null)"
  [[ -n "$Z" ]] && sudo mkswap -q "$Z" && sudo swapon -p 100 "$Z"
) || echo "zram unavailable; continuing"
sudo sysctl -qw vm.swappiness=100 vm.overcommit_memory=1 || true

# Avoid the runner agent being selected by the OOM killer.
for p in $(pgrep -f 'Runner.Listener|Runner.Worker|actions-runner' || true); do
  echo -1000 | sudo tee "/proc/$p/oom_score_adj" >/dev/null 2>&1 || true
done

ROOT_FREE_MB="$(df --output=avail -B1M / | tail -1)"
IMGS=()

if [[ "$ROOT_DEV" != "$MNT_DEV" ]]; then
  MNT_FREE_MB="$(df --output=avail -B1M /mnt | tail -1)"
  MNT_IMG_MB=$((MNT_FREE_MB - 1024))
  if (( MNT_IMG_MB > 1024 )); then
    sudo fallocate -l "${MNT_IMG_MB}M" /mnt/pv-mnt.img
    IMGS+=(/mnt/pv-mnt.img)
  fi
fi

ROOT_IMG_MB=$((ROOT_FREE_MB - ROOT_RESERVE_MB))
if [[ "$ROOT_DEV" == "$MNT_DEV" ]] && (( ROOT_IMG_MB < MIN_WORKSPACE_MB )); then
  echo "Not enough space for the minimum ROM workspace: ${ROOT_IMG_MB} MiB available, ${MIN_WORKSPACE_MB} MiB required." >&2
  exit 1
fi
if (( ROOT_IMG_MB < 4096 )); then
  echo "Not enough free space on / for the ROM workspace (${ROOT_IMG_MB} MiB available after reserve)." >&2
  exit 1
fi
sudo fallocate -l "${ROOT_IMG_MB}M" /pv-root.img
IMGS+=(/pv-root.img)

LOOPS=()
for img in "${IMGS[@]}"; do
  LOOPS+=("$(sudo losetup --find --show "$img")")
done
sudo apt-get install -y -qq btrfs-progs >/dev/null 2>&1
sudo mkfs.btrfs -q -f -d single -m single -L rom "${LOOPS[@]}"
sudo mkdir -p "$MP"
sudo mount -o compress-force=zstd:1,noatime,space_cache=v2,commit=120 "${LOOPS[0]}" "$MP"
sudo chown -R runner:runner "$MP"

free -h
sudo swapon --show
df -h "$MP"
sudo btrfs filesystem usage -T "$MP" | head -12 || true
