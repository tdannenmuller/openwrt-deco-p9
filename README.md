# OpenWrt for the TP-Link Deco P9

Patches, tools and notes to run current OpenWrt (`main`, ath79/QCA9563) on the **TP-Link Deco P9 (v1/v2)**,
including its Broadcom powerline (PLC) chip.

> **Status: experimental.** The patches apply cleanly and the images have been built and flashed on real
> hardware, but this is a community effort by one person with two devices. Read
> [docs/status.md](docs/status.md) before flashing: it lists what is verified and what is not.

## What you get

- **Device support** (patches `0001`, `0002`): board entry in `tplink-safeloader`, device tree, image definition,
  network defaults (same layout as the Deco M4R).
- **Powerline support** (patch `0003`): the `plc-bcm` package. The PLC chip is a Broadcom one, not Qualcomm, so
  `open-plc-utils` does not work. `plc-bcm` sets the powerline network key (NMK) at boot and puts the PLC port
  into the LAN, so two Decos find each other over the mains with no manual step.
- **Tools** for experiments and for typical home setups (see below).
- **Documentation** of the reverse-engineered PLC protocol and of what was measured.

## Quick start

1. Read [docs/status.md](docs/status.md) and [docs/install.md](docs/install.md) (backup first, then flash).
2. Get an image: build it ([docs/build.md](docs/build.md)) or use `images/`. The prebuilt images are
   convenience builds of a snapshot; rebuild if you want to audit them.
3. **Change the default powerline key** on every Deco ([docs/powerline.md](docs/powerline.md)). The default is
   the public HomePlug AV key, so anyone on the same mains circuit could join your LAN.

## Documentation

| Page | Content |
|---|---|
| [docs/status.md](docs/status.md) | Verified / not verified, known issues |
| [docs/install.md](docs/install.md) | Backup, TFTP flash method, sysupgrade, recovery |
| [docs/build.md](docs/build.md) | Building the image, checking it |
| [docs/powerline.md](docs/powerline.md) | PLC chip, protocol, `plc-bcm`, pairing, NMK security |
| [docs/bridge-ap-roaming.md](docs/bridge-ap-roaming.md) | Second Deco as a bridged access point over PLC, 802.11r/k roaming |
| [docs/router-replacement.md](docs/router-replacement.md) | Using a Deco as the main router (FTTH ISP box replacement) |
| [docs/measurements.md](docs/measurements.md) | Throughput and latency measurements, with their limits |
| [docs/porting.md](docs/porting.md) | Where each part of the device support comes from |
| [docs/lessons-learned.md](docs/lessons-learned.md) | Pitfalls hit during testing |

## Repository layout

- `patches/`: three `git am` patches on top of OpenWrt `main` at commit `6b7ea6896a3a83c9ae80d31e8d35d911e032268f`.
- `images/`: prebuilt factory, sysupgrade and initramfs images, `SHA256SUMS`, build manifest.
- `build-image.sh`, `check-image.sh`: build (Linux) and static checks. `build-native.sh`, `build.sh`
  (older; `build.sh` uses Docker and is untested).
- `tools/plc.uc`, `tools/mme.py`, `tools/plc-service/`: PLC tool (ucode, Python equivalent) and boot service.
- `tools/wifi-backhaul-test/`: experiment script for Wi-Fi bridging between two Decos (WDS, 802.11s).
- `tools/uplink-ethernet.sh`: switch a Deco from Wi-Fi relay to an Ethernet uplink, reversibly.
- `tools/orange-livebox-replacement/`: example of replacing an ISP box (Orange France, FTTH) by a Deco.
  Experimental and ISP-specific; see its README.
- `CLAUDE.md`: instructions for the automated build agent (in French for now).

## Contributing

Reports from other hardware revisions and regions are the most useful thing: please say which `special_id`
your Deco has, which firmware it came from, and exactly what you ran. Keep claims honest: say what you
verified and what you did not. Do not post private keys (NMK), ISP credentials, or MAC addresses of your line.

## License

Patches follow the licenses of the files they modify (GPL-2.0 for OpenWrt). Tools and documentation in this
repository: see the license file once one is added (the maintainer still has to choose it).
