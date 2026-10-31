# Installing OpenWrt on the Deco P9

**Back up first.** Without the `art` partition the Wi-Fi is uncalibrated and the MAC addresses are lost.
Nothing replaces it except your own backup.

## 1. Flashing from the stock firmware

The stock web upgrade silently ignored the factory image (the stock firmware seems to check a signature the
image does not have; hypothesis). What worked is the TFTP method, which boots OpenWrt **from RAM only**:

1. Get the `deco_all_webfailsafe_faux_fw_tftp_v2.bin` file from the community project
   `naf419/tplink_deco_exploits` (it lists the Deco P9 v1.80 and v2.0). **Inspect it yourself before use**: in
   our copy the only readable strings were U-Boot `setenv serverip/ipaddr`, `tftpboot` and `bootm`, with no flash
   write command (`erase`, `cp.b`, `mtd`, `nand`).
2. On your computer: Ethernet directly to the Deco, fixed IP `192.168.0.2/24`, no router. Run a TFTP server on
   port 69 serving a file named exactly `initramfs-kernel.bin` (a copy of the `...-initramfs-kernel.bin` image).
   Disable the firewall for the test.
3. Unplug the Deco, press and hold reset (paperclip), plug in, keep holding 10 to 15 s until the LED goes off.
4. Open `http://192.168.0.1` and upload the fake firmware. "Upgrade failed" is the expected answer. The Deco
   then fetches `initramfs-kernel.bin` by TFTP and boots it.
5. Set your computer to DHCP and open `http://192.168.1.1` (no password at first). Set a root password.

Nothing is written to flash until step 3 below. If power is cut before then, the Deco boots the stock firmware.

## 2. Backup from the RAM-booted system

The partition table covers the full 16 MB flash. From your computer:

```sh
ssh root@192.168.1.1 'cat /proc/mtd' | tee mtd-list.txt
for n in 0 1 2 3 4; do ssh root@192.168.1.1 "cat /dev/mtd${n}ro" > mtd$n.bin; done
for n in 0 1 2 3 4; do ssh root@192.168.1.1 "cat /dev/mtd${n}ro" | shasum -a 256; done; shasum -a 256 mtd*.bin
```
Both series of checksums must match, and the sizes must add up to 16 777 216 bytes. Keep the files in two places.
(Alternative: read the SPI flash with a clip and `flashrom -p ch341a_spi -r`, three times, identical hashes;
unpowered device, 3.3 V programmer.)

## 3. Permanent install

LuCI > System > Backup / Flash Firmware, choose the **sysupgrade** image, **untick "Keep settings"**, flash.
Allow 3 minutes and never cut power during the write.

## Updating an installed Deco

Use sysupgrade. Settings in `/etc/config` are kept; **packages and `/etc/rc.d` links you added by hand are not**
(see [lessons-learned.md](lessons-learned.md)). After an upgrade check `uci show plc` (same NMK on every Deco)
and the services you rely on.

## Recovery plan (partly unverified)

1. U-Boot (0x000000-0x080000) is not touched by the image.
2. UART (3.3 V, 115200 baud) gives access to U-Boot; the pad location on the P9 is not verified.
3. U-Boot TFTP recovery exists on the M4R; the P9 should have it (unverified).
4. Last resort: write the full backup back with `flashrom -p ch341a_spi -w`.
