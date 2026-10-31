#!/bin/bash
# Build de l'image Deco P9. A lancer sur le Mac (ou tout hote avec Docker).
# Le code et le build vivent dans un VOLUME Docker (ext4 Linux), pas dans un dossier macOS.
set -euo pipefail
PATCHES_DIR="$(cd "$(dirname "$0")" && pwd)/patches"
docker build -t openwrt-builder "$(dirname "$0")"
docker volume create openwrt-src >/dev/null
docker run --rm -v openwrt-src:/home/builder -u root openwrt-builder chown builder:builder /home/builder
docker run --rm -it -v openwrt-src:/home/builder -v "$PATCHES_DIR":/patches:ro openwrt-builder bash -euxc '
  git config --global user.name  "Builder"
  git config --global user.email "builder@localhost"
  [ -d openwrt ] || git clone https://github.com/openwrt/openwrt.git
  cd openwrt
  git fetch origin
  # IMPORTANT: les patchs ont ete faits sur main au commit 6b7ea6896a. Pour un build reproductible :
  git checkout -B deco-p9 6b7ea6896a
  git am /patches/*.patch
  ./scripts/feeds update -a && ./scripts/feeds install -a
  cat > .config <<CFG
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_tplink_deco-p9-v1v2=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_PACKAGE_relayd=y
CONFIG_PACKAGE_luci-proto-relay=y
# Pilote ath10k-ct (par defaut, comme le M4R). Variante non-ct : voir docs/build.md
CFG
  make defconfig
  make download -j8
  make -j"$(nproc)" || make -j1 V=s
  ls -l bin/targets/ath79/generic/*deco-p9*
  sha256sum bin/targets/ath79/generic/*deco-p9*
'
