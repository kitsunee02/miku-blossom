#!/usr/bin/env bash
# Android 15 host dependencies for Ubuntu 24.04 GitHub runners.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
  git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev \
  libelf-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop \
  pngcrush rsync schedtool squashfs-tools xsltproc zip unzip zlib1g-dev \
  python3 python-is-python3 zstd pigz fontconfig openjdk-17-jdk-headless \
  patchelf >/dev/null

mkdir -p "$HOME/bin"
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
chmod +x "$HOME/bin/repo"

git config --global user.name "hsin-blossom-ci"
git config --global user.email "ci@hsin-blossom.invalid"
git config --global color.ui false
git config --global http.postBuffer 524288000
git lfs install --skip-repo

sudo sysctl -qw fs.inotify.max_user_watches=524288 || true
ulimit -n 65535 || true
java -version
free -h
nproc
df -h
