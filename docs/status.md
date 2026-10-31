# Status: what is verified and what is not

Tested on two TP-Link Deco P9 units (hardware tested by one person, Oct 2026), OpenWrt `main`, kernel 6.18,
`apk` package manager.

## Verified on real hardware

- Flashing from the stock firmware (1.3.0) with the TFTP method, then permanent install with sysupgrade.
- Full 5-partition flash backup taken from the RAM-booted system before any write.
- Wi-Fi 2.4 GHz and 5 GHz (`ath9k`, `ath10k-ct`), Ethernet ports, switch port layout.
- Powerline chip: reachable on switch port 2, Broadcom protocol (read/write NMK) works, two Decos pair over
  the mains with the same NMK, the key survives a reboot, the boot service corrects a wrong key.
- Second Deco as a bridged access point reached over PLC (reboot included).
- Wi-Fi bridging between two Decos without `relayd`: WDS (4addr) on 2.4 and 5 GHz, 802.11s mesh on 2.4 GHz and
  on 5 GHz channel 36.
- Replacing an ISP box (Orange France FTTH) by a Deco as the router: public address, Internet and DNS worked
  (see [router-replacement.md](router-replacement.md) for conditions and defects).

## Verified statically only (no hardware)

- Patches apply with `git am` to the base commit and give the expected tree.
- The image builds; `check-image.sh` passes (package built, size under the limit, `product_name:P9`,
  manifest, rootfs content, network defaults). A prebuilt `plc-bcm` image was flashed on hardware only
  indirectly (see lessons learned: the first sysupgrade incident).

## Not verified

- Your device's `special_id` may not be in the support list (6 per hardware version are known). The stock
  firmware would refuse such an image.
- Behaviour after a complete power cut for the PLC key; long-term PLC stability.
- The exact PLC chip vendor/model (deduced from the ethertype and OUI, not read from the chip).
- UART location and U-Boot recovery over TFTP on the P9.
- LEDs: only the power and 5 GHz LEDs are defined; the red 2.4 GHz LED (GPIO 1 in the old fork) is not.
- Sysupgrade from an installation made with the old fork without `-F`.
- Cold boot of a Deco acting as the main router, token lifetime with an ISP, roaming with a real client
  while software flow offloading is on.
- 802.11v (BSS transition): impossible with `wpad-basic`; not tried with the full `wpad`.

## Known issues

- Running `network restart` over SSH froze a Deco twice (cause unknown). Use `network reload`, or `reboot`
  after `uci commit`.
- A `sysupgrade` keeps `/etc/config` but not packages or `/etc/rc.d` links installed by hand: anything you
  added (for example `relayd` before it was in the image) must be reinstalled.
- The prebuilt image ships a **public** default powerline key. Change it.
- The prebuilt images in `images/` predate the English translation of the `plc-bcm` messages; rebuild for the
  English log text (`NMK written and verified`, `NMK already up to date`).
