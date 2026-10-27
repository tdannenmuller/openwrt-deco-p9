# openwrt-deco-p9

Support OpenWrt (branche main) pour le TP-Link Deco P9, sans CPL par défaut.
Lis `NOTES.md` en premier : il décrit ce qui est vérifié et ce qui ne l'est pas.

- `patches/` : 2 patchs (`git am`) sur OpenWrt main, commit `6b7ea6896a`
- `images/` : image factory et sysupgrade construites, avec `SHA256SUMS`
- `build-native.sh` (Linux) et `build.sh` (Docker, non testé)
