#!/bin/bash
# Builds the Deco P9 image with the three patches (including the plc-bcm package), then checks it.
# Linux machine with the OpenWrt toolchain (see docs/build.md). Not tested on macOS.
#
#   ./build-image.sh                # build + check, copy to ./out/
#   WORK=/chemin ./build-image.sh   # work directory (default: ~/openwrt-deco-p9-build)
#   PUBLISH=1 ./build-image.sh      # also copy to images/ and regenerate SHA256SUMS (only after the checks pass)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
BASE=6b7ea6896a3a83c9ae80d31e8d35d911e032268f    # commit of main the patches were made on
WORK="${WORK:-$HOME/openwrt-deco-p9-build}"
[ "$(id -u)" = 0 ] && export FORCE_UNSAFE_CONFIGURE=1

mkdir -p "$WORK"
cd "$WORK"
[ -d .git ] || git init -q .
git remote get-url origin >/dev/null 2>&1 || git remote add origin https://github.com/openwrt/openwrt.git
git config user.name  "Builder"
git config user.email "builder@localhost"

echo "== Fetching OpenWrt $BASE"
git fetch -q --depth 1 origin "$BASE" || git fetch -q origin
git checkout -q -f -B deco-p9 "$BASE"
rm -rf package/utils/plc-bcm            # left over from a previous build: git am would refuse to overwrite it

echo "== Applying the patches"
git am "$REPO"/patches/*.patch
git log --oneline -4

echo "== Feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "== Configuration"
cat > .config <<CFG
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_tplink_deco-p9-v1v2=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
# Wi-Fi relay to the upstream router (proto "relay"). If it is missing from the image, a sysupgrade
# removes it while its configuration is kept: the Deco then loses its link to the upstream router.
CONFIG_PACKAGE_relayd=y
CONFIG_PACKAGE_luci-proto-relay=y
CFG
make defconfig

# plc-bcm must come from DEVICE_PACKAGES (patch 0003), not from this file; relayd comes from the .config above.
for opt in plc-bcm ucode-mod-fs ucode-mod-socket ucode-mod-uci relayd luci-proto-relay; do
	grep -q "^CONFIG_PACKAGE_$opt=y" .config || { echo "ERROR: $opt is not selected in .config"; exit 1; }
done

echo "== Building"
make download -j8
make -j"$(nproc)" || make -j1 V=s

echo "== Checking"
WORK="$WORK" "$REPO/check-image.sh"

echo "== Copying the files"
OUT="$REPO/out"
mkdir -p "$OUT"
cp bin/targets/ath79/generic/*deco-p9* "$OUT"/
cp .config "$OUT/config.full"
( cd "$OUT" && sha256sum ./*deco-p9*.bin | sed 's#\./##' | tee SHA256SUMS.new )

if [ "${PUBLISH:-0}" = 1 ]; then
	cp bin/targets/ath79/generic/*deco-p9*.bin bin/targets/ath79/generic/*deco-p9*.manifest "$REPO/images/"
	cp bin/targets/ath79/generic/config.buildinfo "$REPO/images/"
	( cd "$REPO/images" && sha256sum ./*.bin | sed 's#\./##' > SHA256SUMS )
	echo "images/ updated"
fi
