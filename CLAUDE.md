# Instructions for the build agent (Deco P9, `plc-bcm` package)

This repository holds three `git am` patches for OpenWrt (base `6b7ea6896a3a83c9ae80d31e8d35d911e032268f`):
`0001` signing tool entry, `0002` TP-Link Deco P9 support, `0003` the `plc-bcm` package (powerline) and port 2 in the LAN.
**Your mission: build the firmware with the three patches, check it, and report honestly.**
Read `docs/status.md` and `docs/powerline.md` first (powerline and the `plc-bcm` package).

## What is verified and what is not

- Verified: the three patches apply without conflict on the base. The package content (`package/utils/plc-bcm/files/`) was tested on real Decos (NMK read and write, correction at boot), but installed by hand, not from an image.
- **Never executed**: the `plc-bcm` `Makefile`, the selection through `DEVICE_PACKAGES`, the complete image. If something breaks, it is probably there. You are the first run.
- The repository has no access to hardware. **You cannot flash** and you must not claim the firmware "works": it is only built and statically checked. The real test is done by the user on their Decos.

## Build

```sh
./build-image.sh        # clones OpenWrt, applies the patches, configures, builds, runs check-image.sh
```
Linux machine with the OpenWrt toolchain (packages listed in `docs/build.md`). Variables: `WORK` (work directory), `PUBLISH=1` (also copies to `images/` and regenerates `SHA256SUMS`, only after the checks pass). The first build is long. The result is copied to `out/` (ignored by git).

`check-image.sh` checks: package built, images present, sysupgrade size <= 13824k, `product_name:P9`, manifest (plc-bcm, ucode-mod-socket, -uci, -fs, relayd, luci-proto-relay), rootfs content (`/usr/sbin/plc-nmk`, `/etc/init.d/plc`, link `/etc/rc.d/S99plc`, `/usr/sbin/relayd` and its `S*relayd` link, `/etc/config/plc` with the default NMK, `ucode` modules), and `02_network` with port 2. It writes nothing.

Also do the manual checks of `docs/build.md` ("Verify the image"): header comparison with an official M4R image, `hsqs` magic.

## Likely failure points (look here first if it fails)

1. **`/etc/rc.d/S99plc` missing**: in principle impossible, because `default_postinst` (injected automatically by `include/package-pack.mk`, defined in `package/base-files/files/lib/functions.sh`) enables every script of the package's `/etc/init.d` when the image is built. If the link is missing, either `/etc/init.d/plc` is not in the package file list or its `#!/bin/sh /etc/rc.common` / `START=99` header is broken: look at the `install` step of the `Makefile`.
2. **`Makefile` error** in `plc-bcm` (modelled on `package/network/config/gre/Makefile`): `PKGARCH:=all`, `conffiles`, `INSTALL_CONF`.
3. **`ucode` module missing from the image**: `check-image.sh` reports a missing `socket.so`, `uci.so` or `fs.so`. The dependencies are in the `Makefile`.
4. **Image too large** (limit 13824k): `luci-ssl` is heavy; reduce it only with the user's agreement.
5. **Feeds**: `make download` or `feeds update` can fail without network.

## If you have to fix the package

Patch `0003` is the source of truth for the image. In the work directory (`$WORK`, local commit `deco-p9`):
1. Fix the files under `package/utils/plc-bcm/` (or `target/linux/ath79/...`).
2. `git commit --amend` (the last commit is patch 0003).
3. Regenerate the patch in the repository: delete the old `patches/0003-...`, then `git format-patch -1 --start-number 3 -o <repo>/patches/`.
4. Check on a fresh base that `git am patches/*.patch` gives the same tree (`git rev-parse HEAD^{tree}`).
5. If the tool script changes, also update `tools/plc.uc` (copy of `files/plc-nmk.uc`) and `tools/plc-service/`.
Never work around an error by changing `check-image.sh` so that it passes.

## Rules

- **No secrets**: no private NMK is in the repository; do not invent or write one. The NMK in `/etc/config/plc` is the public HomePlug AV value (password "HomePlugAV"); this is intended and documented.
- Work on a branch (`git switch -c build-YYYY-MM-DD`). **Do not push to `main`** and do not push anywhere without agreement. Do not rewrite history.
- Commits in English, with a message that says what was done AND what was not verified. Add binaries to `images/` (PUBLISH=1) only if `check-image.sh` passes completely; otherwise say so.
- Report failures as they are (error output), without minimizing them.

## What you must report to the user

1. The result of `check-image.sh` (full copy) and the image sizes.
2. The `sha256` of the files in `out/` and the OpenWrt commit used.
3. What you fixed (and the new patch 0003 if it changed), what remains broken.
4. The checks **to do on hardware** (you cannot do them):
   - flash with the TFTP method of `docs/install.md`;
   - on the Deco: `ls /etc/rc.d | grep plc`, `logread | grep plc:` (expected: `NMK written and verified` or `NMK already up to date`), `uci show plc`, `swconfig dev switch0 vlan 1 show` (port 2 present with no manual setting);
   - two new Decos: ping from one to the other over the powerline;
   - **change the default NMK**: `uci set plc.main.nmk='<32 hex>'; uci commit plc; /etc/init.d/plc restart`.
