# Using a Deco as the main router (replacing an ISP box)

**Experimental.** Done once, on one FTTH line (Orange France), with one Deco P9. The practical details, scripts and
measurements are in [tools/orange-livebox-replacement/README.md](../tools/orange-livebox-replacement/README.md).
Read its "Known defects" first. Other ISPs differ: this page is the general picture.

## What a replacement needs

1. **Physical**: the ISP's ONT connected to one Deco port; the other port (and PLC) for the LAN. A Deco has
   only two RJ45 ports, so plan a switch for wired devices.
2. **VLAN on the WAN**: with the `swconfig` switch (ar8327) the WAN VLAN is a tagged switch VLAN plus an
   `8021q` device on `eth0`, not a DSA port.
3. **ISP authentication**: some ISPs authenticate the box, not only the VLAN (Orange: VLAN 832, DHCP vendor class,
   client id from the box MAC, user class, option 90 token). A bad token gives a restricted lease. What worked in
   the test was **capturing the real box's DHCP request** (a transparent VLAN tap between ONT and box) and
   replaying its option-90 token and options; the token generator from a community project did not.
4. **Priority (802.1p)**: marking *all* traffic at priority 6 throttled upload to a few Mbit/s; only control
   traffic (DHCP, ICMP, IGMP) should carry it.
5. **CPU**: NAT was CPU-bound at ~320 Mbit/s; software flow offloading (`firewall.@defaults[0].flow_offloading`,
   global, not per port) raised wired download to ~850 Mbit/s with the CPU still saturated. Offloaded flows bypass
   netfilter hooks, so rules and QoS marking do not apply to established flows, and a client that roams
   during an offloaded flow may see stale forwarding until it expires (not tested).
6. **Not covered**: TV decoder (multicast/IGMP), VoIP, IPv6, token renewal over the long term.

## Safety

- Every conversion step is run with an automatic rollback (`rpcd` `uci apply` with `rollback`/`timeout`, confirmed
  from the **same** ubus session that applied it). Do not run a DHCP server on a Deco bridged to a live LAN.
- Never commit real credentials, tokens, box MAC addresses, public IPs or captures to a repository. A router's
  stored token is as sensitive as a password: treat config backups accordingly.
- Use only your own subscription's credentials, on your own equipment.
