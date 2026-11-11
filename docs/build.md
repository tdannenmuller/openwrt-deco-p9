# Building the image

Linux machine with the OpenWrt build toolchain (case-sensitive filesystem; ~30-40 GB free). macOS is not supported.
Packages (Debian/Ubuntu): `build-essential gawk flex bison libncurses-dev libssl-dev python3-setuptools swig rsync
unzip zlib1g-dev file wget libelf-dev`.

```sh
./build-image.sh        # clone OpenWrt at the pinned commit, apply the 3 patches, configure, build, check
```
Variables: `WORK` (work directory), `PUBLISH=1` (also copy to `images/` and regenerate `SHA256SUMS`, only after the
checks pass). Result in `out/`. The base commit is `6b7ea6896a3a83c9ae80d31e8d35d911e032268f`. SHA-256 sums of
another build will differ (timestamps).

The default config adds `luci`, `luci-ssl`, `kmod-ath10k-ct`, `ath10k-firmware-qca9888-ct`, `relayd` and
`luci-proto-relay`, and for a VPN and dynamic DNS `kmod-wireguard`, `wireguard-tools`, `luci-proto-wireguard`,
`ddns-scripts` and `ddns-scripts-cloudflare` (the last one pulls in `curl`). `kmod-wireguard` has to be built with
the image: the official kernel-module feeds are for another kernel build, so it cannot be installed with `apk`
afterwards. `plc-bcm` comes with the device profile.

## Verify the image

`./check-image.sh` (writes nothing) checks: package built, images present, sysupgrade size under 13824k,
`product_name:P9`, manifest (plc-bcm, ucode modules, relayd, luci-proto-relay, WireGuard and DDNS packages, curl), rootfs content
(`/usr/sbin/plc-nmk`, `/etc/init.d/plc`, `S99plc`, `relayd`, `/etc/config/plc`, `/usr/bin/wg`, `wireguard.ko`, the
Cloudflare DDNS script), and the port-2 entry in `02_network`.

Manual checks worth doing:
- `strings -n 20 factory.bin | grep product_name`
- compare header bytes with an official M4R factory image: same partitions and sizes, only the support list differs
- `unsquashfs -s` on the rootfs: magic `hsqs`, partition ends at or before 0xe80000

## Using the non-ct Wi-Fi driver

Add to `.config`:
```
# CONFIG_PACKAGE_kmod-ath10k-ct is not set
# CONFIG_PACKAGE_ath10k-firmware-qca9888-ct is not set
CONFIG_PACKAGE_kmod-ath10k=y
CONFIG_PACKAGE_ath10k-firmware-qca9888=y
```
The old fork used the non-ct variant; whether QCA9886 behaves identically was not checked.

## If you change `plc-bcm`

Patch `0003` is the source of truth. Amend the last commit in the work tree, regenerate it with
`git format-patch -1 --start-number 3`, then check on a fresh base that `git am patches/*.patch` gives the same
tree. If the script changes, update `tools/plc.uc` and `tools/plc-service/` too.
