#!/bin/bash
set -ex
cd /home/user/work/upstream
export FORCE_UNSAFE_CONFIGURE=1
./scripts/feeds update -a
./scripts/feeds install -a
cat > .config <<CFG
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_tplink_deco-p9-v1v2=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CFG
make defconfig
make download -j8
make -j4 || make -j1 V=s
ls -l bin/targets/ath79/generic/
