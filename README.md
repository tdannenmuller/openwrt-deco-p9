# openwrt-deco-p9

Support OpenWrt (branche main) pour le TP-Link Deco P9, avec le CPL (puce Broadcom) géré par le paquet `plc-bcm`.
Lis `NOTES.md` en premier : il décrit ce qui est vérifié et ce qui ne l'est pas.

- `patches/` : 3 patchs (`git am`) sur OpenWrt main, commit `6b7ea6896a` (0003 = paquet `plc-bcm` et port CPL dans le LAN)
- `images/` : image factory et sysupgrade construites **à partir des patchs 0001 et 0002 seulement** (sans CPL) ; à reconstruire avec le patch 0003. `SHA256SUMS`
- `tools/` : `plc.uc` (outil `ucode`), `mme.py` (équivalent Python), `plc-service/` (service, pour une installation à la main)
- `build-native.sh` (Linux) et `build.sh` (Docker, non testé)
