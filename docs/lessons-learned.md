# Lessons learned (pitfalls hit during testing)

- **`network restart` over SSH froze a Deco** (twice; recovered only by a power cycle; no log survived). Use
  `network reload`; for address or Wi-Fi changes arm a rollback before and verify it runs. A RAM timer
  (`sleep 600` then restore `/etc/config`) did not save the device from a full freeze. Back up `/etc/config`
  to flash first.
- Do not combine `set -e` with `uci delete` of an option that may be absent (it returns 1).
- First-time SSH to a new address needs `-o StrictHostKeyChecking=accept-new`, otherwise `BatchMode` scripts fail.
- **A sysupgrade with "keep settings" keeps `/etc/config` only.** Packages installed by hand (`relayd`) disappeared
  while their config stayed, cutting off the only uplink. A Deco that never had the PLC config got the package's
  public default NMK and left the real PLC network. `/etc/rc.d` links are also not kept: services you had
  disabled (`firewall`, `dnsmasq`, `odhcpd`) came back. After an upgrade check `which relayd`, `uci show plc`,
  `ls /etc/rc.d`. `check-image.sh` now checks that `relayd` is in the image.
- A fix to `check-image.sh` on a throwaway build branch was lost on the next branch: merge verification fixes
  into the main line.
- **Computer on Ethernet and Wi-Fi in the same subnet** (macOS): everything goes through Wi-Fi and `ping` fails
  although the cable works. Force the interface (`ping -b en5 <ip>`, `ssh -o ProxyCommand='nc -b en5 %h %p'`).
- **Stale ARP caches** after moving a Deco from relay to bridge: clients kept the old relay MAC for about 20
  minutes (`arp -d <ip>`).
- Piping a script over SSH needs the `< file` redirect; a missing one truncated the remote script to 0 bytes.
- BusyBox lacks `ip -br`, `pkill`, `paste`, `nc -l`; `ip route get` is unreliable.
- Building OpenWrt on macOS is not supported (BSD `sed`, GNU Make 3.81) and needs 30-40 GB.
