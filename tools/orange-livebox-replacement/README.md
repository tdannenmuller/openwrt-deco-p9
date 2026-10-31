# Replacing an Orange (France) Livebox with an OpenWrt router (FTTH)

Worked example on a TP-Link Deco P9 (`swconfig` switch, not `DSA`). The approach should carry over to other OpenWrt routers, but the switch/VLAN steps will differ.

**Status: experimental, tested on one line. Read "Known defects" first.**
The conversion worked once on a real Orange FTTH line (Oct 2026). Nothing here is vendor-supported, and most of it is not verified beyond that single test. Each section says what was verified and what was not.

## Legal / ToS note

Use only your own credentials, with your own Orange subscription, on your own equipment. Do not use anyone else's credentials or line identity. Check Orange's current terms of service. You are responsible for how you use these scripts.

## Why this is not just a cable and DHCP

Orange authenticates the router as a real Livebox, not only by VLAN. Without that, DHCP silently fails (no error message, just no lease).

## What you need, in order

1. **A dedicated WAN port.** If all Ethernet ports are in the LAN, remove one (port 3 or 5 on the P9) and make it a WAN port tagged on a new VLAN, under **Network > Switch** (the `swconfig` page, not the DSA screen of a newer router):
   - Remove the chosen port from VLAN 1 (the existing LAN).
   - Create VLAN **832** with the CPU port and this port both **tagged** (`t`). Frames from the ONT already arrive tagged, and the CPU port must be tagged too so that `eth0.832` appears on the Linux side.

2. **The WAN interface**, with DHCP options that mimic a Livebox. Template: `network-wan-snippet.txt` in this folder. Replace:
   - `11:22:33:AA:BB:CC` with the MAC address **of the real Livebox** you are replacing (label underneath it, or its admin interface). Written `<livebox-mac>` below. The DHCP client must present itself with this MAC (option 61/`clientid`), not the router's own. Orange authenticates through option 90, not the layer 2 address (see `orange-gen-auth.sh`).
   - `Livebox4` in `userclass` (option 77) with your actual model if it is not a Livebox 4 (`Livebox3`, `Livebox5`, `Livebox6`...). Only the last hex character changes (`33` to `34` to go from 3 to 4, etc.); the rest of the string is fixed.

3. **The authentication token (option 90 for IPv4, option 11 for IPv6).** `orange-gen-auth.sh` computes it from your Orange account credentials (customer area, not Wi-Fi), stored in `orange-auth`. Example identifier format: `fti/<login>`. **Never commit real values.** According to community sources the token expires after 5 to 8 weeks. `orange-auth-init.sh` (at boot) and `97-orange-config` (hotplug on WAN loss) regenerate it automatically; these scripts and the config file were not exercised in the real test (see "What the rollback does not cover"). `99-wan6-delay` delays `wan6` until `wan` has its lease.

4. **Network priority (802.1p/PCP).** Community sources (routers using the kernel-managed `8021q` interface, not `swconfig`) say Orange throttles upload to about 6 Mbit/s if DHCP frames are not sent with priority 6. See "Throughput and 802.1p marking" below for what was measured. Do not invent a syntax: if in doubt, plug in, measure upstream throughput, and dig only if needed.

## Before unplugging the Livebox

- Keep the Livebox aside, cable ready to plug back in. If authentication fails or the VLAN is refused, nothing is damaged, but the connection is down.
- This only covers internet access. Orange TV set-top boxes and the landline phone are not covered, and probably not transposable without extra work (VLAN and `igmpproxy` for TV, Livebox-specific hardware for the phone).

## Sources (community, no official Orange documentation)

- https://github.com/golfromeo-fr/openwrt-turris-omnia-orange-france : main reference for DHCP, VLAN 832 and PCP marking (on a router with an `8021q` device, not `swconfig`).
- https://lig-membres.imag.fr/rousseau/tech/2021/02/28/fibre-orange-avec-routeur-er-x.html
- https://www.lafois.com/2021/10/09/replacing-orange-livebox-by-an-edgerouter-with-ftth/
- https://vincent.bernat.ch/en/blog/2019-orange-livebox-linux
- https://wiki.csnu.org/index.php/Fibre_orange_en_DHCP_avec_routeur_pfsense

## Dry run on a device without an ONT

`to-router.uc` (with automatic rollback) applied **only** the VLAN 832 switch config and the `wan` interface, then everything was rolled back by itself after the timeout. **Verified**, with no ONT and no cable:
- `swconfig` does create the **`eth0.832`** device (VID 832) when adding a `config switch_vlan` with `vlan '2'`, `vid '832'`, `ports '0t 3t'`.
- The DHCP client sends a DISCOVER on this VLAN with `Hostname livebox`, `Vendor-Class sagem`, `Client-ID ether <MAC>`, `User-Class FSVDSL_livebox.Internet.softathome.Livebox4` and option 90 (so `vendorid` + `clientid` + `sendopts` 77 and 90 are enough).
- **802.1p priority**: with a complete `device` section (`type '8021q'`, `ifname`, `vid`, `egress_qos_mapping`), frames leave as `vlan 832, p 6` and `/proc/net/vlan/eth0.832` shows `EGRESS priority mappings: 0:6 1:0 6:6`. Without `type/ifname/vid` the section is ignored (`p 0`). **Not verified at that stage**: that the `ar8327` chip keeps this priority on the wire at the WAN port (this needs a capture on the other side of the cable), and that Orange honours it.
- The automatic rollback restores everything (VLAN 1 back to `2 3 5 0t`, no more `eth0.832`, no more `wan` interface).

**Errors found in the original template** (fixed in `network-wan-snippet.txt`): `vendorclass` and `userclass` do not exist in OpenWrt's DHCP client; `sendopts` 12, 60 and 61 were redundant; without `defaultreqopts '0'`, `netifd` adds options 12 and 42 to the requested list. The DHCPv6 `clientid` must also be replaced (see the template). `/etc/config/orange-auth` and the token scripts were not executed in this dry run.

## Full conversion to a router: `to-router.uc convert` (written Oct 2026)

What it does, in order:
- Refuses without touching anything if `mac` or `auth` is missing, or if the target LAN address (`192.168.0.1`) already answers.
- Backs up `network`, `dhcp` and the service state to `/root/backup-router`.
- Stages VLAN 832 + WAN (+ 802.1p marking) + LAN address `192.168.0.1` (no static gateway or DNS) + DHCP server.
- Applies with `rpcd`'s rollback (300 s), then enables and restarts `dnsmasq` and `firewall`.
- **Confirms only if** the `wan` interface has an IPv4 lease, `ping 1.1.1.1` works and DNS resolves, twice in a row. Otherwise `rpcd` restores the configuration and the script puts `dnsmasq` and `firewall` back in their previous state.
- Runs detached from the SSH session (the LAN address changes).
- `to-router.uc restore` goes back to the previous state **after** a confirmation (it does not move cables back).

**Verified on a device connected to a real existing network (without applying the conversion)**: `plan full=1` (expected operations), `check` (29 network operations and 1 DHCP operation staged, valid, then cancelled, nothing left over), `guard` (refuses when `192.168.0.1` answers, passes on a free address), `selftest` (success checks and service state read without error), `restore` (refuses without a backup; with an identical backup, files unchanged), the token generator in `AUTH_ONLY=1` mode with dummy credentials, and, via the dry run above, applying the VLAN and WAN with rollback.

**Not verified in that setup, and cannot be without risk**: applying the LAN address and DHCP server (a DHCP server on a device plugged into an existing network would answer other devices there), the automatic confirmation, service activation, restore after failure, and anything involving the ONT and Orange.

### What the rollback does not cover

- Physical cabling.
- A frozen device (one device froze until a manual reboot during testing).
- IPv6 (`wan6` not configured, `odhcpd` untouched).
- Token renewal (5 to 8 weeks according to community sources): `orange-gen-auth.sh` and `97-orange-config` in this folder edit the configuration directly and were not adapted to this flow. `to-router.uc renew` is the replacement (see "Token commands" below); it is untested on a live line.
- DHCP reservations and static addresses that lived on the Livebox.

### Procedure and checklist (D-day)

Before:
1. **Independent internet for your working session**: for example a laptop on a phone hotspot over Wi-Fi, plus an Ethernet adapter to a LAN port of the router (manual IP `192.168.0.10`, no gateway). Without this, your session loses internet during the test.
2. Note the Livebox MAC address (label) as `<livebox-mac>`, and keep the Livebox next to you with its cables. Pick a short window when nobody needs internet.
3. Copy to the router: `to-router.uc` (in `/root/`), `orange-gen-auth.sh`, and create `/etc/config/orange-auth` (Orange credentials, **never committed**). Then run `verify-token` if you already have a token (see "Token commands").
4. Decide about the **password**: try first with a dummy value (this README cannot claim that Orange still checks it; see the test results below).
5. `AUTH_ONLY=1 sh orange-gen-auth.sh` to get the token, then `ucode /root/to-router.uc convert mac=<livebox-mac> auth=<token>` (without `go=yes`: prints the plan).

On the day:
6. **Switch off the Livebox** (or unplug its cable from the router). Otherwise `convert` refuses (`192.168.0.1` answers).
7. `ucode /root/to-router.uc convert mac=<livebox-mac> auth=<token> go=yes`: the conversion starts in the background (300 s to succeed).
8. **Plug the ONT cable into port 3** of the router within the next minute. Do not plug it in earlier: port 3 is still in the LAN.
9. Follow with `logread -e to-router` (or `tail -f /root/to-router.log`) until you see the confirmed or cancelled message.
10. If cancelled: unplug the ONT from the router, plug the ONT back into the Livebox and power it on. To go back later: `to-router.uc restore`.

### Known gaps to validate on a real line

802.1p priority on the wire at the WAN port, Orange's acceptance of the token, IPv6, TV set-top box and landline phone (not covered), and whether `192.168.0.1` suits your network (devices with static addresses; DHCP range `100` to `249` to be confirmed).

## Token commands and the priority service

All of these are subcommands of `ucode /root/to-router.uc`. They read the credentials from `/etc/config/orange-auth` (or `creds=<file>`), which **you** create on the router with mode 600; the password is never printed, logged or passed on the command line. Create the file without leaving the password in your shell history:

```sh
umask 077
printf 'Login (without fti/): '; read L
printf 'Password: '; stty -echo; read P; stty echo; echo
printf 'LOGIN="%s"\nPASSWORD="%s"\nBYTE="A"\n' "$L" "$P" > /etc/config/orange-auth
unset L P
```
A double quote inside the password is not supported by the file reader. `/etc/config/` is kept by a sysupgrade, so the file survives it; treat configuration backups as sensitive (they also contain the token).

| Command | What it does | Status |
|---|---|---|
| `selftest-token` | Builds a token from dummy data, parses it back and recomputes the MD5. No secret involved. | passes on one device |
| `verify-token` | Recomputes the MD5 of the token stored in `network.wan.sendopts` (option 90) with the password of the file, and compares. Prints only whether the login matches and whether the MD5 is identical. Use it to check your password and the formula without touching the line. | on one device the stored real token was identical to the computed one |
| `renew [go=yes] [timeout=120]` | Builds a new token (random printable 16-character salt and random byte, like a real Livebox) and applies it to `network.wan.sendopts` with rpcd rollback. Without `go=yes` it only says what it would do. Confirm by hand with `confirm` once the lease is public. | **untested**: it replaces the token of a live line, so it needs the ONT and a way back |
| `install-prio` | Installs the `orange-prio` service (nft rules marking control traffic at 802.1p priority 6, see the measurements below) on an already converted router, enables it at boot and lists its two files in `/etc/sysupgrade.conf` so that a sysupgrade keeps them. | loads the rules, present after a reboot |
| `remove-prio` | Removes the service and its files (the `/etc/sysupgrade.conf` lines stay). | untested |

Notes:
- A sysupgrade keeps `/etc/config` but not files you added elsewhere. `convert` installs `orange-prio` itself; after flashing a new image on a router that was already converted, run `install-prio` again (or keep the files listed in `/etc/sysupgrade.conf`).
- Two bugs were fixed when these commands were tested: the init script must not set `USE_PROCD=0` (`rc.common` tests whether the variable is non-empty), and ucode has no `.map()` method.
- Method used to confirm that the password is right without sharing it: store the password in the file, run `verify-token`, read "IDENTICAL". The token stored on the router was the one replayed from the real box, so this also validates the formula.

## Real test results and lessons (Oct 2026, one FTTH line)

**The conversion worked on one Orange FTTH line**: the router took the Livebox's place and obtained its public address (`/21`, gateway, Orange DNS, 3-day lease), with internet and DNS. What had to be understood to get there:

1. **A first attempt failed** (lease in `172.16.0.0/16`, silent gateway) with a dummy password, the salt and token byte generated by `orange-gen-auth.sh`, a hostname, option 121, no option 125 and the router's own MAC address. The cause was **not isolated**: several things changed at once before success.
2. **Capture from the real Livebox**: `to-router.uc tap go=yes` makes the router a transparent VLAN 832 bridge between the ONT and the Livebox (CPU as a third party). Then `tcpdump` on `eth0` (`vlan 832 and (udp port 67 or udp port 68)`) sees the Livebox's DHCP request with its **real token** (option 90: 16 random printable characters of salt, a random byte, a hash), its option 125, no hostname, 12 requested options without 121, 802.1p priority 6.
3. **Replay of the captured token** with a request aligned to the Livebox's (including the MAC on the wire, set in the `device` section): **public address obtained**. The password was not needed: the token already contains its hash. The token **will expire** (5 to 8 weeks according to community sources, not verified): it must be recaptured by putting the Livebox back behind the router with `tap`. It is stored in the router config (`network.wan.sendopts`): any config backup is sensitive.
4. **The Livebox and the router cannot be active together** (same identity at Orange): switch the Livebox off before `convert`.

**Known defects of `to-router.uc`**
- **The automatic confirmation does not run to the end**: the process stops after one or two passes of the wait loop, with no error and no sign of memory exhaustion (two attempts, cause not found; the loop in isolation runs fine). You must therefore **confirm by hand**: `to-router.uc confirm`, which uses the session stored in `/tmp/to-router.sid`. Without confirmation, `rpcd` rolls back at the end of the timeout (300 s).
- **Only the session that applied can cancel or confirm** (another session gets "Permission denied"): `untap` only works if the stored session exists; otherwise wait for the timeout to expire.
- Do not test `dry-run` with `wan_port` equal to the port your workstation is plugged into: it gets cut off for the duration of the timeout (happened once).

## Throughput and 802.1p marking: measurements (Oct 2026)

All figures are from one P9 on a gigabit line, single test run, not a benchmark.

**Marking all traffic at priority 6 throttles upload.** Same path (`iperf3`, 4 streams, from the router to a public server in Paris):

| Marking | Download | Upload |
|---|---|---|
| Everything at priority 6 (mapping `0:6` without rules) | 266 Mbit/s | **4.5 Mbit/s** |
| Data at 0, control traffic (ICMP, IGMP, DHCP) at 6 | 271 Mbit/s | **218 Mbit/s** |

**Chosen setup**: the `eth0.832` device only has the `6:6` mapping, so ordinary traffic (priority 0) leaves at priority 0 on the wire. `nft` rules (table `orange_prio` in the `output` hook, service `orange-prio`) mark only router-generated control traffic at 6 (ICMP, IGMP, unicast DHCP). `convert` installs this mapping and these rules and enables software offloading. An earlier scheme (mapping `0:6 1:0 6:6` plus `postrouting` rules setting data to priority 1) gave the same throughput without offloading but **does not work with it**: offloaded flows no longer go through netfilter, so they would have stayed at priority 0, and the `0:6` mapping would have put them back at priority 6, hence throttled.
**Difference from the Livebox**: `udhcpc`'s *broadcast* DHCP request (raw socket, invisible to `nft`) now leaves at priority 0 whereas the Livebox sends it at 6. Orange accepted it (lease obtained in under a second) and upload was not throttled. This is a single measurement; nothing guarantees Orange will not change this.
**Not verified**: behaviour after a full reboot, and persistence across `sysupgrade` (the service and file are not in the image).

**Ceiling of about 320 Mbit/s wired, caused by the P9's CPU** (without offloading): from a wired NAS, one HTTPS stream gives 321 Mbit/s with the router CPU at 0% idle and 93 to 98% interrupt handling. Four streams give 279 Mbit/s total (CPU also saturated). From a laptop on Wi-Fi (390 Mbit/s negotiated), about 200 Mbit/s upload with the CPU about 60% free: there the limit is Wi-Fi. No measurement shows a ceiling on the Orange side at this level.

**Measurement pitfalls**: BusyBox `wget` is slow and with HTTPS it saturates the router CPU (it measures the router, not the line); use `iperf3` or an external client. A public server can be poor at receiving (23 to 35 Mbit/s on one, 177 on another from the same laptop). `proof.ovh.net` redirects HTTP to HTTPS and serves only one stream out of eight in parallel. Parallel `wget`s killed by `timeout` can stay alive: always kill them forcefully.

### Software flow offloading (`flow_offloading`)
`firewall.@defaults[0].flow_offloading='1'` (the firewall creates a `flowtable` on `eth0` and both radios; the `nf_flow_table` modules were already in the image). Applied with `rpcd` rollback, then confirmed. Same wired client (the NAS), same server, one HTTPS stream:

| | Without offloading | With offloading |
|---|---|---|
| Download | 321, then 339 and 361 Mbit/s | **818 and 850 Mbit/s** |
| Upload (NAS to Cloudflare) | 114 to 199 Mbit/s | 162 and 167 Mbit/s (not throttled) |
| Router CPU during download | 0% idle, 93 to 98% interrupts | 0 to 4% idle, 94 to 100% interrupts |

37 flows marked `OFFLOAD` in conntrack; the 60 outgoing TCP frames captured were at `p 0`. From a laptop on Wi-Fi: upload 214 Mbit/s (193 to 198 before), download 151 Mbit/s (Wi-Fi is the limit). **The CPU remains saturated**: it is unknown what the router could still deliver, or whether 850 Mbit/s is limited by the router, by OVH or by the NAS.
**Not verified**: long-term stability (measurements over a few minutes), behaviour with many simultaneous flows (eight streams to OVH could not be measured), and known side effects of software offloading (for example on firewall or QoS rules added later).
