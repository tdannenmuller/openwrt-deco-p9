#!/bin/bash
# Construit l'image du Deco P9 avec les trois patchs (dont le paquet plc-bcm), puis la vérifie.
# Machine Linux avec la toolchain OpenWrt (voir docs/build.md). Non testé sur macOS.
#
#   ./build-image.sh                # build + vérification, copie dans ./out/
#   WORK=/chemin ./build-image.sh   # dossier de travail (défaut : ~/openwrt-deco-p9-build)
#   PUBLISH=1 ./build-image.sh      # copie aussi dans images/ et régénère SHA256SUMS (à ne faire qu'après vérification)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
BASE=6b7ea6896a3a83c9ae80d31e8d35d911e032268f    # commit de main sur lequel les patchs ont été faits
WORK="${WORK:-$HOME/openwrt-deco-p9-build}"
[ "$(id -u)" = 0 ] && export FORCE_UNSAFE_CONFIGURE=1

mkdir -p "$WORK"
cd "$WORK"
[ -d .git ] || git init -q .
git remote get-url origin >/dev/null 2>&1 || git remote add origin https://github.com/openwrt/openwrt.git
git config user.name  "Builder"
git config user.email "builder@localhost"

echo "== Récupération d'OpenWrt $BASE"
git fetch -q --depth 1 origin "$BASE" || git fetch -q origin
git checkout -q -f -B deco-p9 "$BASE"
rm -rf package/utils/plc-bcm            # reste d'un build précédent : git am refuserait d'écraser

echo "== Application des patchs"
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
# Relais Wi-Fi vers la Livebox (proto « relay »). Absent de l'image, un sysupgrade le supprime
# alors que sa configuration est conservée : le Deco perd alors sa liaison avec la Livebox.
CONFIG_PACKAGE_relayd=y
CONFIG_PACKAGE_luci-proto-relay=y
CFG
make defconfig

# plc-bcm doit venir de DEVICE_PACKAGES (patch 0003), pas de ce fichier ; relayd vient du .config ci-dessus.
for opt in plc-bcm ucode-mod-fs ucode-mod-socket ucode-mod-uci relayd luci-proto-relay; do
	grep -q "^CONFIG_PACKAGE_$opt=y" .config || { echo "ERREUR : $opt n'est pas sélectionné dans .config"; exit 1; }
done

echo "== Compilation"
make download -j8
make -j"$(nproc)" || make -j1 V=s

echo "== Vérification"
WORK="$WORK" "$REPO/check-image.sh"

echo "== Copie des fichiers"
OUT="$REPO/out"
mkdir -p "$OUT"
cp bin/targets/ath79/generic/*deco-p9* "$OUT"/
cp .config "$OUT/config.full"
( cd "$OUT" && sha256sum ./*deco-p9*.bin | sed 's#\./##' | tee SHA256SUMS.new )

if [ "${PUBLISH:-0}" = 1 ]; then
	cp bin/targets/ath79/generic/*deco-p9*.bin bin/targets/ath79/generic/*deco-p9*.manifest "$REPO/images/"
	cp bin/targets/ath79/generic/config.buildinfo "$REPO/images/"
	( cd "$REPO/images" && sha256sum ./*.bin | sed 's#\./##' > SHA256SUMS )
	echo "images/ mis à jour"
fi
