#!/bin/sh
# Passe un Deco d'une liaison montante Wi-Fi (client « wwan » + relayd) à une liaison montante ETHERNET :
# le Deco devient un simple pont (comme le Deco 2), relié à la Livebox par câble sur un de ses deux ports.
# Réversible : l'état d'origine est sauvegardé dans /root/backup-uplink et « off » le restaure.
#
#   uplink-ethernet.sh status
#   uplink-ethernet.sh on  [secondes]    désactive client Wi-Fi + relais, fixe le canal 5 GHz, applique après le délai
#   uplink-ethernet.sh off [secondes]    restaure la configuration d'origine
# Variables : CHAN=<canal 5 GHz sans DFS> (défaut 36) ; RADIO5=<radio 5 GHz> (défaut radio0).
#
# ORDRE À RESPECTER : lancer « on » AVANT de brancher le câble. Avec le Wi-Fi client et relayd encore actifs, un câble
# vers la Livebox ferait deux chemins entre le Deco et la Livebox : boucle réseau (tempête de diffusion).
# Entre « on » et le câble, ce Deco (et tout ce qui passe par lui, dont le CPL) n'a pas de liaison montante.

BK=/root/backup-uplink
RADIO5="${RADIO5:-radio0}"
CHAN="${CHAN:-36}"

die() { echo "ERREUR : $*" >&2; exit 1; }

sta_sections() { uci show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.]*\)\.mode='sta'$/\1/p"; }

apply_later() {  # $1 = délai, $2 = commande relayd (stop|restart)
	# « ifup lan » à la fin : constaté sur un Deco, la route par défaut de « lan » (gateway) n'était pas réinstallée
	# dans le noyau par le simple rechargement du réseau après l'arrêt du relais.
	setsid sh -c "sleep $1; /etc/init.d/relayd $2; /etc/init.d/network reload; wifi reload; sleep 8; ifup lan" </dev/null >/dev/null 2>&1 &
	echo "application dans $1 s (réseau et Wi-Fi rechargés ; ce Deco peut devenir injoignable)"
}

case "$1" in
status)
	echo "== sauvegarde : $([ -d $BK ] && echo "présente ($BK) : liaison Ethernet préparée ou active" || echo "absente : configuration d'origine")"
	echo "== client Wi-Fi :"
	for s in $(sta_sections); do echo "  $s : $(uci -q get wireless.$s.ssid) disabled=$(uci -q get wireless.$s.disabled || echo 0)"; done
	for s in wwan relay_bridge; do uci -q get network.$s.proto >/dev/null && echo "  network.$s : disabled=$(uci -q get network.$s.disabled || echo 0)"; done
	echo "== $RADIO5 : canal $(uci -q get wireless.$RADIO5.channel)"
	echo "== relayd : $(pidof relayd >/dev/null && echo "EN COURS" || echo arrêté)"
	echo "== liens Ethernet (ports 3 et 5) :"; swconfig dev switch0 show 2>/dev/null | grep -E "link: port:(3|5) "
	if pidof relayd >/dev/null && swconfig dev switch0 show 2>/dev/null | grep -E "link: port:(3|5) .*link:up" >/dev/null; then
		echo "!! ATTENTION : relayd tourne ET un câble est branché : boucle possible vers la Livebox"
	fi
	echo "== liaison montante : $(ip route | grep ^default | head -1)"
	;;
on)
	[ -d "$BK" ] && die "déjà préparé ($BK existe) : lancer 'off' pour revenir à l'état d'origine"
	mkdir -p "$BK" || die "impossible de créer $BK"
	cp /etc/config/network /etc/config/wireless "$BK"/ || die "sauvegarde impossible"
	uci -q get "wireless.$RADIO5.channel" > "$BK/radio5.channel"
	for s in wwan relay_bridge; do
		uci -q get network.$s.proto >/dev/null && uci set network.$s.disabled=1
	done
	for s in $(sta_sections); do uci set wireless.$s.disabled=1; done
	uci set "wireless.$RADIO5.channel=$CHAN"
	uci commit network; uci commit wireless
	echo "configuration modifiée (sauvegarde : $BK) ; canal $RADIO5 : $(cat $BK/radio5.channel) -> $CHAN"
	apply_later "${2:-20}" stop
	echo "=> brancher le câble Livebox -> port LAN du Deco APRÈS ce délai"
	;;
off)
	[ -d "$BK" ] || die "pas de sauvegarde ($BK absent) : rien à restaurer"
	cp "$BK/network" "$BK/wireless" /etc/config/ || die "restauration impossible"
	rm -rf "$BK"
	echo "configuration d'origine restaurée"
	echo "=> DÉBRANCHER le câble vers la Livebox avant l'application (sinon boucle avec relayd)"
	apply_later "${2:-20}" restart
	;;
*)
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
	;;
esac
