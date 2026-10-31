# Experiment: a "bridge" Wi-Fi link between two TP-Link Deco P9 running OpenWrt (WDS and 802.11s, no relayd)

**Status (Oct 2026):** WDS worked as a real bridge on 2.4 GHz and on 5 GHz. 802.11s mesh worked on 2.4 GHz and on 5 GHz channel 36 (no DFS, radio otherwise idle). It failed on DFS channel 112, and the cause is not established. See "Results" below.

The script was modified after phase 1 (`nft` and `ip rule` rules, `RADIO` and `CHAN` variables, `wpad` restart in `swap-*`, removal of `mesh_fwding`); the modified version was used for the 5 GHz and mesh tests. The boot-time cleanup hook (see "Safeguards") has never actually run.

## Why

A standard Wi-Fi station cannot be put in a bridge (it only transmits with its own MAC address). This is the reason `relayd` exists. If both ends are Decos running OpenWrt, two approaches give a real bridge: **WDS (4addr)** and **802.11s mesh**. This experiment checks which of them work here.

Verified (read-only): both radios of each Deco (`ath10k` 5 GHz, `ath9k` 2.4 GHz) advertise `AP/VLAN` and `mesh point`. That is necessary, not sufficient.

## What the experiment tests, and what it does not

- Tests: WDS/mesh association, and above all that a frame whose source MAC address is **foreign** to the Wi-Fi interface crosses the link (`probe`). That is what proves a real bridge.
- The first phase used only the 2.4 GHz radio (`ath9k`); 5 GHz (`ath10k-ct`) was tested afterwards (see the results sections). A result on one radio does not carry over to the other.
- Throughput was measured only in the 5 GHz tests, with a single iperf3 TCP stream. These numbers are a rough indication, not a link capacity.
- Long-term stability was not measured: each test lasted a few minutes with the two Decos next to each other.

## Safeguards

- By default only `radio1` (2.4 GHz) is touched. Other links (powerline, cable, 5 GHz) stay in place.
- The test bridge `br-wdstest` (addresses `10.77.0.x`) is **never** connected to `br-lan`: no loop with the powerline link.
- Test network: hidden SSID `WDSTEST`, throwaway key set in the script (public and unimportant: the test lasts a few minutes). Change both if you run this on a network where it matters.
- **Automatic stop** after 20 min (`AUTOSTOP=<minutes>`, 0 to disable): `backhaul-test.sh stop` removes everything and restores the radio's channel. It runs as a process on the Deco, so it does not protect against a freeze or a reboot.
- During the test, the 2.4 GHz channel of the second Deco is switched to the first Deco's channel, then restored.
- No `network restart`: the script uses `network reload` and `wifi reload <radio>`.
- **Cleanup at boot**: `apply` adds a `... stop # wdstest-cleanup` line to `/etc/rc.local` (removed by `stop`), so the test configuration, written to flash, disappears if the Deco is rebooted by hand or crashes. It was added after an unstable test on 5 GHz channel 48 (see the end). It has never been executed.

## Preparation

- Copy the script to both Decos as `/root/backhaul-test.sh`.
- Download the `wpad-mesh-mbedtls` and `wpad-basic-mbedtls` packages into `/root/pkg/` on both Decos (about 1.4 MB of flash each; `rm -r /root/pkg` removes them).

## Procedure (roles: Deco 1 = 10.77.0.1, Deco 2 = 10.77.0.2)

Reach each Deco over SSH through a link that the test will not disturb (cable or powerline).

### Phase 1: WDS (no package change)

1. Deco 1: `/root/backhaul-test.sh wds-ap 10.77.0.1` (reloads its Wi-Fi radio for a few seconds)
2. Deco 2: `/root/backhaul-test.sh wds-sta 10.77.0.2`
3. Wait about 20 s, then run `/root/backhaul-test.sh status` on each Deco. Deco 2 should see the access point, Deco 1 should see Deco 2, and an interface such as `phy1-ap0.sta1` on the access point side indicates 4addr mode.
4. Deco 2: `/root/backhaul-test.sh probe 10.77.0.1`.
   - Replies: WDS relays a foreign address, **so it is a real bridge**.
   - No replies although the association exists: 4addr mode is not working (or not active).
5. On both: `/root/backhaul-test.sh stop`.

### Phase 2: 802.11s mesh (changes `wpad`, Wi-Fi down for ~30 s per Deco)

1. Run `swap-mesh` on Deco 2 first. If all goes well, do the same on Deco 1. **Warning: this cuts that Deco's Wi-Fi for 30 to 60 s, including any Wi-Fi uplink to the upstream router (so its Internet access and relay function).** Do it over SSH from the other Deco or over a wired link, not over a Wi-Fi connection to that Deco.
2. On both: `/root/backhaul-test.sh mesh 10.77.0.1` (Deco 1) and `... mesh 10.77.0.2` (Deco 2).
3. `status` (the `mpath` table should show the neighbour), then `probe` as above.
4. `stop` on both, then `swap-basic` to restore `wpad-basic` (unless you keep the mesh).

## If something breaks

- `/root/backhaul-test.sh stop` on the affected Deco (or wait for the automatic stop).
- `swap-basic` if Wi-Fi does not come back after `swap-mesh`.
- Original configurations are not backed up: the script only adds the sections `wireless.wdstest`, `network.wdstest`, `network.wdstest_dev`, and only changes the channel of the chosen radio (saved in `/root/backhaul-test.saved`).

## What to record after each test

For each mode: whether association succeeded, the `probe` result, messages from `logread | grep -E "hostapd|wpa|mesh"`, and which radio (`ath9k` or `ath10k`) the result applies to.

## Phase 1 results (WDS, 2.4 GHz `ath9k` only)

**WDS (4addr) works as a real bridge on `ath9k`.** Deco 1 as access point (`wds-ap`), Deco 2 as client (`wds-sta`):
- WPA2 association succeeded (signal -42 dBm), interface `phy1-ap1.sta1` created on the access point side, `4addr: on` on the client side;
- Deco 1 learned the **foreign** MAC address `02:77:00:00:00:02` on its WDS interface (the address `probe` forces on Deco 2's bridge), and ICMP frames with that source address do arrive (`tcpdump` capture on Deco 1);
- `probe`: 5 replies out of 5, 1 to 26 ms, from Deco 2 to Deco 1; ping in the other direction (`ping -I br-wdstest`): 3 out of 3.

Not measured: throughput. Not tried in this phase: 5 GHz, mesh, long-term stability.

**Pitfalls (specific to a Deco used as a relay, unrelated to WDS):** the first `probe` runs got no reply.
1. `firewall4` has an input chain with `policy drop` that only accepts `br-lan` and the Wi-Fi client interface: a bridge outside any zone is ignored (the output chain is `policy accept`).
2. **Actual cause of the missing replies:** `relayd` installs `ip rule 2: from all iif lo lookup 16800`, ahead of the main table. Traffic generated by the Deco itself (ping replies) therefore went to the upstream router instead of the test bridge. A ping with `-I br-wdstest` bypasses this rule, which gave a misleading diagnosis (the `OutEchoReps` counters were increasing). Workaround: `ip rule add to 10.77.0.0/24 lookup main pref 1`. **Keep this in mind for real use:** on a Deco acting as a relay, any additional local network has the same problem.
3. BusyBox `ip route get` is unreliable (it showed a default route although the direct route existed).

After the test, `stop` on both Decos restored the channels and removed all test configuration; the `nft` and `ip rule` rules added by hand were removed. `tcpdump-mini` stayed installed.

## WDS on 5 GHz (`ath10k-ct`)

Same setup (Deco 1 as access point `wds-ap`, Deco 2 as client `wds-sta`) with `RADIO=radio0`. Deco 1 kept its channel (`CHAN=` empty, so it follows the upstream router: channel 112, VHT80), Deco 2 forced to `CHAN=112`. Deco 1 was connected by cable during the test.

**WDS (4addr) also works on `ath10k-ct`.**
- WPA2 association succeeded (-53 dBm, negotiated rate 390 / 585 Mbit/s, `4addr: on` on the client, interface `phy0-ap1.sta1` on the access point).
- `probe`: 5 replies out of 5 (1.7 to 12.9 ms) with the foreign MAC `02:77:00:00:00:02`, learned by Deco 1 on its WDS interface.
- **Measured throughput (iperf3, TCP, one stream, 10 s): 196 Mbit/s in each direction**, no retransmissions. This is probably limited by the Decos' CPU (iperf3 itself used about 38 % of CPU, plus switching) rather than by the radio link: other measurements on these Decos also top out around 200 Mbit/s. Do not read it as the link's capacity.
- Side effects: Deco 1's 5 GHz radio was reloaded (its upstream Wi-Fi link stayed up); Deco 2's went to DFS channel 112 (60 s CAC wait) before returning to channel 36 on `stop`.
- Not measured: long-term stability, real or multiple traffic flows. The Decos were close to each other.

**Consequence:** for two Decos running OpenWrt, a 5 GHz Wi-Fi link as a real bridge (WDS) is possible **without `relayd`**, if both ends run OpenWrt. It does not depend on the upstream router, which probably does not support 4addr (not tested).

## 802.11s mesh results

Package `wpad-mesh-mbedtls` installed on both Decos (`wpad-basic-mbedtls` restored afterwards with `swap-basic`).

**5 GHz (`ath10k-ct`, channel 112, DFS): peering does not establish.** SAE authentication succeeds on both sides (`authenticated: yes`, `authorized: yes`, signal -50 dBm), but the link stays at `mesh plink: OPN_SNT` and `wpa_supplicant` repeats `Mesh MPM: failed to send peering frame` for more than 80 s (no path in `mpath dump`). The kernel also logged `ath10k_pci: failed to create vdev 3 peer for AP/IBSS: -145` during a Wi-Fi reload; no link to the failure was established. **Cause not established:** DFS channel (mesh does not perform CAC by itself), a limitation of the `ath10k` CT firmware, or something else.

**2.4 GHz (`ath9k`, channel 1): mesh works.** `mesh plink: ESTAB`, `MESH-PEER-CONNECTED`, one-hop path in `mpath dump` (metric 10241), and `probe`: 5 replies out of 5 (1.3 to 67.8 ms) with the foreign MAC, learned by Deco 1. Throughput not measured.

**Two mistakes in the script, since fixed (they wasted the first 5 GHz attempt):**
1. `mesh_fwding` is rejected by `wpa_supplicant` (`unknown network field 'mesh_fwding'`): removed (the kernel forwards by default).
2. **Replacing the `wpad` package does not change the daemon already running.** The old `wpa_supplicant` (basic variant) rejected mesh mode (`too large mode (value=5 max_value=4)`) until the service was restarted: `swap-*` now runs `/etc/init.d/wpad restart`. `wifi reload` is not enough.

## 802.11s mesh on 5 GHz, channel 36 (no DFS)

Deco 1 was then connected to the upstream router **by cable** (its 5 GHz radio idle, no longer a Wi-Fi client), both Decos on channel 36 (VHT80), with `wpad-mesh-mbedtls`.

**5 GHz mesh works.**
- Peering: `mesh plink: ESTAB`, `MESH-PEER-CONNECTED` on both sides (-58 to -62 dBm), one-hop path, metric 137 (the 2.4 GHz one was 10241; lower is better).
- `probe`: the foreign MAC `02:77:00:00:00:02` is learned by Deco 1, so it is a real bridge. The first packets had very high latency (2076, 1076, then 76 ms, 2 losses out of 5), probably mesh path discovery (not verified); after that, 19 replies out of 20 (2.2 to 21 ms, average 4.6 ms).
- **Throughput (iperf3, TCP, one stream, 10 s): 146 Mbit/s (Deco 2 to Deco 1, 264 retransmissions) and 140 Mbit/s (reverse, 0 retransmissions).** Negotiated rate 195 / 175 Mbit/s (`VHT-MCS 4`, one spatial stream in one direction), driver-expected throughput 170 Mbit/s.

**Comparison with 5 GHz WDS (196 Mbit/s): be careful.** Conditions differ (channel 112 then 36, signal -53 then -58 to -60 dBm, one run each), so the gap cannot be attributed to the protocol. Mesh is in the same order of magnitude, somewhat lower.

**Cause of the channel 112 failure: still not established.** Between the two tests, **two things changed at once**: the channel (DFS 112, then non-DFS 36) and the radio's role (it carried the Wi-Fi uplink to the upstream router, then no longer). DFS is a reasonable hypothesis, not a demonstrated one. What can be said: mesh established when the radio was free, on a non-DFS channel.

**Takeaway:** for a 5 GHz real-bridge link between two OpenWrt Decos, **WDS is the demonstrated solution**; 802.11s mesh is demonstrated on 2.4 GHz and on 5 GHz channel 36 with an idle radio. All tests lasted a few minutes with the Decos side by side, without stability measurement.

**Unstable test with a loaded radio** (Wi-Fi uplink to the upstream router + access point + mesh on channel 48, no DFS): Deco 1 became intermittently unreachable, then completely so until a manual reboot; no logs were kept. Caution (hypothesis only): a node that connects to the upstream router over Wi-Fi should probably not also carry a 5 GHz mesh.
