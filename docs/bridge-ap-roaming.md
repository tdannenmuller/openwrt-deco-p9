# Second Deco as a bridged access point over PLC, and roaming

Setup: Deco A is the router (or connects to the router); Deco B is a plain access point reached **only** through
the powerline. They share SSID, key and mobility domain, so clients can roam.

## Deco B as a bridged AP

- `network.lan`: `proto static`, a free address in the LAN subnet, `gateway` and `dns` pointing at the router,
  no `ip6assign`.
- Switch: `ports='2 3 5 0t'` (port 2 is the PLC). **No cable to the router**: the PLC is the single uplink,
  otherwise you get a loop.
- DHCP: `dhcp.lan.ignore='1'`, `dhcpv6` and `ra` disabled; disable `firewall`, `dnsmasq`, `odhcpd` with
  `/etc/init.d/<service> disable`.
- Wi-Fi: same SSID and key as Deco A, `country` set, **different channels** (for example 5 GHz channel 36 and
  2.4 GHz channel 11 on B; another non-DFS channel on A).

Verified after a cold reboot: address and gateway in place, upstream ping through the PLC in about 5 ms, no local
DHCP, a computer on an Ethernet port of B got its lease from the router.
Not verified: long-term stability.

## 802.11r/k roaming

On the access-point sections of both Decos, on both radios:

```sh
uci set wireless.default_radio0.ieee80211k='1'
uci set wireless.default_radio0.ieee80211r='1'
uci set wireless.default_radio0.mobility_domain='4f57'     # identical on both Decos
uci set wireless.default_radio0.ft_over_ds='0'
uci set wireless.default_radio0.ft_psk_generate_local='1'  # no r0kh/r1kh to configure
uci set wireless.default_radio0.nasid='decoA-radio0'       # unique per radio and per Deco
uci commit wireless && wifi reload
```
Repeat for `default_radio1` (and `decoB-radioN` on the second Deco). Back up `/etc/config/wireless` first.

Verified in the generated hostapd configuration: `wpa_key_mgmt=WPA-PSK FT-PSK`, same `mobility_domain`,
`ft_psk_generate_local=1`, `rrm_neighbor_report=1`, Wi-Fi enabled on both after reload.

Limits:
- **802.11v is not available**: `wpad-basic-mbedtls` rejects `bss_transition` ("unknown configuration item"),
  hostapd then refuses the whole configuration and the radio stays off. Remove the option to recover. The full
  `wpad` might allow it (not tried).
- No neighbour sharing between Decos (no `usteer`/`dawn`): the client decides when to move.
- **Not tested with a real client** (switch time, incompatible clients). Some old devices refuse an `FT-PSK` SSID;
  if so, remove `ieee80211r` on both Decos.
- `wifi reload` on a Deco whose Wi-Fi is also its uplink cuts its SSH path for a few seconds.

## Extending a router over Wi-Fi with `relayd` (when no cable or PLC is possible)

A standard Wi-Fi station cannot be bridged (it only sends frames with its own MAC), hence `relayd`. Make it work:
1. `lan` static in the upstream subnet, outside its DHCP range, gateway and DNS = the upstream router.
2. DHCP server **off** on `lan`: only the upstream router hands out leases.
3. `wwan` stays proto `none`: `relayd` (via a `relay_bridge` interface) handles addressing for the whole bridge.

If `lan` keeps the factory address with its own DHCP server, `relay_bridge` stays without an address
("Carrier: Absent"): `relayd` joins two segments but does not change addresses. This needs the same subnet on both
sides. `relayd` and `luci-proto-relay` are in the image.

Alternatives without `relayd` between two OpenWrt devices: WDS (4addr) and 802.11s, see
[tools/wifi-backhaul-test/README.md](../tools/wifi-backhaul-test/README.md). Best of all: an Ethernet or PLC uplink,
which also frees the radio and the CPU (see [measurements.md](measurements.md)); `tools/uplink-ethernet.sh`
(`on`, `off`, `status`) switches a Deco from relay to Ethernet reversibly (run `on` **before** plugging the cable,
otherwise two paths create a loop). After `network reload` the default route may be missing: `ifup lan` restores it.
