#!/usr/bin/env bash
# Free Ubuntu runner space before creating the compressed ROM filesystem.
set -uo pipefail

df -h / /mnt 2>/dev/null || true
sudo rm -rf \
  /usr/share/dotnet /usr/local/lib/android /opt/ghc /usr/local/.ghcup \
  /opt/hostedtoolcache /usr/local/share/boost /usr/share/swift \
  /usr/local/share/chromium /usr/local/share/powershell \
  /usr/local/lib/node_modules /opt/az /opt/microsoft /opt/google \
  /usr/lib/jvm /usr/local/julia* /usr/share/miniconda /opt/pipx \
  /usr/lib/google-cloud-sdk /usr/local/aws-cli /usr/local/aws-sam-cli \
  /usr/share/az_* 2>/dev/null || true
sudo docker system prune -af >/dev/null 2>&1 || true
sudo swapoff -a 2>/dev/null || true
sudo rm -f /mnt/swapfile /swapfile 2>/dev/null || true
sudo apt-get clean
df -h / /mnt 2>/dev/null || true
