# Powerline (PLC) on the Deco P9

## Hardware facts

- The PLC chip sits on **switch port 2** (link up at 1000 Mbit/s with no cable). By default only ports 3 and 5
  are in the LAN, so port 2 stays isolated. Patch `0003` puts it in the LAN.
- It is a **Broadcom** chip, not Qualcomm/Atheros (vendor deduced from ethertype `0x8912` and OUI `00:1F:84`,
  read in the stock `hpMakeBCMPacket`; the chip model itself was not read). `open-plc-utils`/`plctool` does not
  work (it speaks `0x88e1`, OUI `00:B0:52`). The chip does answer standard HomePlug AV `CC_DISCOVER_LIST`.
- The stock firmware drives no GPIO for it: it talks over raw frames on port 2 (`eth0-p2`). The chip MAC is
  the Deco LAN MAC **+ 5**.

### Switch ports by hand

Put all ports in **one** `ports` value:
```sh
uci delete network.@switch_vlan[0].ports
uci set network.@switch_vlan[0].ports='2 3 5 0t'
uci commit network && /etc/init.d/network reload
swconfig dev switch0 vlan 1 show     # expected: ports: 0t 2 3 5
```
With `list ports '3 5 0t'` plus `list ports '2'`, VLAN 1 ended up **empty** (cause not isolated). Use the single value.
To disable: `ports='3 5 0t'`.

## The `plc-bcm` package (patch 0003)

- `/usr/sbin/plc-nmk` (ucode tool, same as `tools/plc.uc`), `/etc/init.d/plc` (procd, background),
  `/etc/config/plc` (kept across sysupgrade). Depends on `ucode`, `ucode-mod-fs`, `-socket`, `-uci`.
- Pulled in by the P9 `DEVICE_PACKAGES`; the P9 gets its own `02_network` entry with port 2 in the LAN.
- At boot it reads `/etc/config/plc` and, if the chip's NMK differs, writes it and reads it back (up to 5 tries;
  a missing acknowledgement is not an error). It waits for `eth0.1` (60 s) and the chip (2 min), logs with the
  tag `plc` and never blocks boot.

```sh
uci show plc
logread | grep plc:
```

### Security: change the default key

`/etc/config/plc` ships with `enabled '1'` and the standard HomePlug AV NMK
`50d3e4933f855b7040784df815aa8db7` (password "HomePlugAV", the key of every new adapter), so new Decos find each
other with no setup. **That key is public**: any PLC adapter on the same electrical circuit can join your LAN.
On every Deco:
```sh
uci set plc.main.nmk='<32 hex characters>'; uci commit plc; /etc/init.d/plc restart
```
Use the **same** key on all your Decos. Generate it randomly, never publish it. Disable PLC with
`uci set plc.main.enabled='0'`.

## Pairing two Decos

There is no manual pairing on the Deco. The stock firmware derives the NMK from a network name and randomises it.
On OpenWrt you set the same 16-byte NMK on both chips; no button needed. Verified with two Decos that started
with different keys: after setting the same key, the second Deco answered pings over PLC and the first Deco's
switch learned its MAC on port 2. The key survives a reboot (full power cut: not tested).

Without the package, use the tool by hand (ucode is in the base image; only `ucode-mod-socket`, 24 kB, is missing;
Python does not fit in flash):
```sh
apk add ucode-mod-socket
ucode tools/plc.uc get-nmk
ucode tools/plc.uc set-nmk <32 hex>
ucode tools/plc.uc pushbutton
```
`tools/mme.py` is the Python equivalent (install Python in RAM from `apk fetch`). Notes on the ucode socket API:
bind by interface name with a valid MAC (not by ifindex); a `0x8912` filter delivered no frames (cause unknown), so
the script receives everything (`ETH_P_ALL`) on `eth0` and filters itself.

## Protocol (deduced from `libplcapi.so` 1.3.0)

Source functions: `hpMakeBCMPacket`, `hpBCMPushButtonStart`, `hpGetBCMNmk`, `hpSetBCMNmk`.

Ethernet frame (padded to 60 bytes), sent on `eth0.1` (VLAN 1, tagged):

| Offset | Size | Content |
|---|---|---|
| 0 | 6 | chip MAC (Deco MAC + 5) |
| 6 | 6 | source MAC |
| 12 | 2 | ethertype `0x8912` |
| 14 | 1 | version `0x02` |
| 15 | 2 | message type, **little-endian on the wire** (`8C A0` = `0xA08C`) |
| 17 | 2 | `00 00` |
| 19 | 3 | OUI `00 1F 84` |
| 22 | 1 | sequence number |
| 23 | n | payload |

The reply has type + 1 and the same OUI.

| Message | Type | Payload | Reply | Verified |
|---|---|---|---|---|
| Pushbutton start | `0xA08C` | `00` | `0xA08D`, `00` | reply seen; effect on pairing not seen (no partner) |
| Read NMK | `0xA05C` | `24 00` | `0xA05D`: status `01`, length `10 00`, 16 bytes of NMK | yes |
| Write NMK | `0xA018` | 16 bytes NMK + `00 00` | `0xA019`: `00` | yes |

- After a write the chip takes more than 3 s to answer: wait about 5 s before reading back.
- `hpSetBCMNmk` can trigger a second message (`0xA060`); not decoded, not needed.
- Seen in the code but untested: `hpGetNwInfoFromBCM`, `hpSetBCMMac`, `hpBCMGetEthSts`,
  `hpResetBCMFacDef` (factory reset, avoid), `hpRebootBCMDev`.

## Not verified

The "late acknowledgement" case of an NMK write could not be reproduced. Not tested: an image without `luci`, a
chip that never answers within 2 minutes, a chip whose MAC is not "Deco MAC + 5" (the stock fixes it up; the
service does not).
