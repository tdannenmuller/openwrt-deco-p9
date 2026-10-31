# Measurements (and their limits)

All on two Deco P9 on one mains strip (also an LED bulb and a laptop charger), single runs, no repetition.
iperf3 runs were 8-10 s, TCP, one stream, with iperf3 installed in RAM (`apk fetch --recursive iperf3`,
`apk extract --destination /tmp/ip`). Phone numbers are speed-test apps at nearby but not identical spots.

Relay setup (Deco A as a Wi-Fi relay to the ISP box on 5 GHz, Deco B bridged over PLC):

| Path | Mbit/s (up / down) |
|---|---|
| Phone on the ISP box Wi-Fi | ~270 / ~270 |
| Phone on Deco A Wi-Fi | 123 / 89 |
| Phone on Deco B Wi-Fi | ~40 / ~40 |
| iperf3 Deco A to a computer behind the box (client Wi-Fi only) | 208 / 196 |
| iperf3 PLC only, Deco B to Deco A | 174 (92 retransmits) / 200 (26) |
| iperf3 Deco B to the same computer (PLC + `relayd` + client Wi-Fi) | 79 / 141 |

Findings:
- The PLC is not the bottleneck: 174-200 Mbit/s between Decos despite the bulb and charger. Latency over PLC is
  irregular (5-47 ms, mean 20 ms; cause not established).
- The relay chain loses a lot: Deco A's CPU was fully busy (84 % softirq) during a 200 Mbit/s transfer; `relayd`
  itself was not profiled.
- With client and AP sharing one 5 GHz radio, client traffic crosses the radio twice: this explains most of 123 / 89.
- The Deco B hop from ~79-141 down to ~40 with a phone: cause not isolated.
- With an **Ethernet uplink** Deco A becomes a plain bridge: no `relayd`, no shared radio.

Wi-Fi bridging between two Decos (WDS, 802.11s) measured about 140-196 Mbit/s, limited by the Deco CPU:
see `tools/wifi-backhaul-test/README.md`.

Router use (Deco as the main router on a gigabit line) is in
[tools/orange-livebox-replacement/README.md](../tools/orange-livebox-replacement/README.md): NAT throughput
was CPU-bound at about 320 Mbit/s; software flow offloading raised wired download to about 850 Mbit/s with the CPU
still saturated. Use iperf3 or an external client: BusyBox `wget` (HTTPS in particular) saturates the Deco CPU and
is not a valid measurement tool.
