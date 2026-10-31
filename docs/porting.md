# Where the device support comes from

The Deco P9 is hardware-identical to the Deco M4R for what matters to OpenWrt. The support was rebuilt on
current `main` from an older community fork (kernel 5.4/5.10), re-using only what still applies.

| Item | Origin | In the patches |
|---|---|---|
| Board id `DECO-P9-V1V2` | fork (`tplink-safeloader.c`) | identical |
| Support list (12 lines, product `P9`, versions 1.0.0 and 2.0.0, 6 `special_id` each) | fork, from the OEM firmware | identical |
| Compatible `tplink,deco-p9-v1v2` | fork device tree | identical |
| `SUPPORTED_DEVICES += deco-p9-v1v2` | fork `generic-tp-link.mk` | identical |
| `IMAGE_SIZE := 13824k` | fork | same as the M4R on `main` |
| Network: ports 3 and 5 in the LAN | fork `02_network` | same as the M4R |
| Calibration (art 0x1000, 0x5000) and MAC (config 0x8) | fork dts and caldata script | via the M4R dts of `main` (nvmem) |

Choices:
- The device tree is the M4R one from `main` with only the name and compatible changed. No shared `.dtsi`
  was created: it would modify the M4R, which cannot be tested here.
- The safeloader entry follows the M4R flash layout of `main` (`firmware` partition 0xe00000), not the older
  fork layout. It lives in a patch under `tools/firmware-utils/patches/` because that tool is now fetched from
  an external repository.
- The fork's trailing commas in the support list were removed (values unchanged).

Dropped: FastPath/shortcut-fe (tied to kernel 5.4, unmaintained), the red 2.4 GHz LED on GPIO 1 (not
confirmed), kernel config noise from the fork's rebases, performance experiments.

Checked against the OEM firmware 1.3.0 (build 20250804): identical support list and flash layout to the M4R
entry (u-boot 0x80000, firmware to 0xe80000, product-info, same partitions to `radio` at 0xff0000). The OEM
image contains `fw-type:Cloud`; whether the OpenWrt image writes the same was not checked. The OEM image
splits `os-image`/`file-system` at a fixed address; the OpenWrt tool places the split by kernel size, as for
the M4R.
