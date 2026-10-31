#!/bin/sh
# Switches a Deco from a Wi-Fi uplink ("wwan" client + relayd) to an ETHERNET uplink:
# the Deco becomes a plain bridge, cabled to the upstream router on one of its two ports.
# Reversible: the original state is saved in /root/backup-uplink and "off" restores it.
#
#   uplink-ethernet.sh status
#   uplink-ethernet.sh on  [secondes]    disables the Wi-Fi client + relay, sets the 5 GHz channel, applies after the delay
#   uplink-ethernet.sh off [secondes]    restores the original configuration
# Variables: CHAN=<non-DFS 5 GHz channel> (default 36); RADIO5=<5 GHz radio> (default radio0).
#
# ORDER MATTERS: run "on" BEFORE plugging in the cable. With the Wi-Fi client and relayd still active, a cable
# to the upstream router would create two paths between the Deco and the router: a network loop (broadcast storm).
# Between "on" and the cable, this Deco (and everything behind it, PLC included) has no uplink.

BK=/root/backup-uplink
RADIO5="${RADIO5:-radio0}"
CHAN="${CHAN:-36}"

die() { echo "ERROR: $*" >&2; exit 1; }

sta_sections() { uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.]*\)\.mode='sta'$/\1/p"; }

apply_later() {  # $1 = delay, $2 = relayd command (stop|restart)
	# "ifup lan" at the end: observed on a Deco, the default route of "lan" (gateway) was not reinstalled
	# in the kernel by the plain network reload after the relay stopped.
	setsid sh -c "sleep $1; /etc/init.d/relayd $2; /etc/init.d/network reload; wifi reload; sleep 8; ifup lan" </dev/null >/dev/null 2>&1 &
	echo "applying in $1 s (network and Wi-Fi reloaded; this Deco may become unreachable)"
}

case "$1" in
status)
	echo "== backup: $([ -d $BK ] && echo "present ($BK): Ethernet uplink prepared or active" || echo "absent: original configuration")"
	echo "== Wi-Fi client:"
	for s in $(sta_sections); do echo "  $s : $(uci -q get wireless.$s.ssid) disabled=$(uci -q get wireless.$s.disabled || echo 0)"; done
	for s in wwan relay_bridge; do uci -q get network.$s.proto >/dev/null && echo "  network.$s : disabled=$(uci -q get network.$s.disabled || echo 0)"; done
	echo "== $RADIO5: channel $(uci -q get wireless.$RADIO5.channel)"
	echo "== relayd: $(pidof relayd >/dev/null && echo "RUNNING" || echo stopped)"
	echo "== Ethernet links (ports 3 and 5):"; swconfig dev switch0 show 2>/dev/null | grep -E "link: port:(3|5) "
	if pidof relayd >/dev/null && swconfig dev switch0 show 2>/dev/null | grep -E "link: port:(3|5) .*link:up" >/dev/null; then
		echo "!! WARNING: relayd is running AND a cable is plugged in: possible loop to the upstream router"
	fi
	echo "== uplink: $(ip route | grep ^default | head -1)"
	;;
on)
	[ -d "$BK" ] && die "already prepared ($BK exists): run 'off' to return to the original state"
	mkdir -p "$BK" || die "cannot create $BK"
	cp /etc/config/network /etc/config/wireless "$BK"/ || die "backup failed"
	uci -q get "wireless.$RADIO5.channel" > "$BK/radio5.channel"
	for s in wwan relay_bridge; do
		uci -q get network.$s.proto >/dev/null && uci set network.$s.disabled=1
	done
	for s in $(sta_sections); do uci set wireless.$s.disabled=1; done
	uci set "wireless.$RADIO5.channel=$CHAN"
	uci commit network; uci commit wireless
	echo "configuration changed (backup: $BK); $RADIO5 channel: $(cat $BK/radio5.channel) -> $CHAN"
	apply_later "${2:-20}" stop
	echo "=> plug the cable upstream router -> Deco LAN port AFTER this delay"
	;;
off)
	[ -d "$BK" ] || die "no backup ($BK missing): nothing to restore"
	cp "$BK/network" "$BK/wireless" /etc/config/ || die "restore failed"
	rm -rf "$BK"
	echo "original configuration restored"
	echo "=> UNPLUG the cable to the upstream router before it applies (otherwise a loop with relayd)"
	apply_later "${2:-20}" restart
	;;
*)
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
	;;
esac
