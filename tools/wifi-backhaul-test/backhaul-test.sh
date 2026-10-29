#!/bin/sh
# Essai d'une liaison Wi-Fi « pont » entre deux Deco P9 sous OpenWrt, sans relayd :
#   - WDS (4addr) : un Deco en point d'accès (wds-ap), l'autre en client (wds-sta) ;
#   - maillage 802.11s : les deux Deco en « mesh point » (mesh), avec wpad-mesh.
# Se limite à la radio 2,4 GHz (radio1, ath9k) et à un pont de test isolé (br-wdstest, adresses
# 10.77.0.x) : il n'est JAMAIS relié à br-lan, donc pas de boucle avec la liaison CPL.
# Ne dit rien de la radio 5 GHz (ath10k) ni du débit. Voir README.md.
#
#   backhaul-test.sh status
#   backhaul-test.sh wds-ap  <ip>      (ex. 10.77.0.1, sur le Deco qui sert de point d'accès)
#   backhaul-test.sh wds-sta <ip>      (ex. 10.77.0.2, sur le Deco client)
#   backhaul-test.sh mesh    <ip>      (sur les deux Deco, après swap-mesh)
#   backhaul-test.sh probe   <ip_du_pair>
#   backhaul-test.sh swap-mesh | swap-basic     (change de variante de wpad ; coupe le Wi-Fi ~30 s)
#   backhaul-test.sh stop                       (supprime tout l'essai)
# Variables : AUTOSTOP=<minutes> (défaut 20, 0 = désactivé) : « stop » automatique après ce délai ;
#            RADIO=radio0 CHAN=112 pour tester le 5 GHz (CHAN vide : canal inchangé) ; à répéter pour « stop ».

# Radio et canal : par défaut le 2,4 GHz (radio1, canal 1). Pour le 5 GHz : RADIO=radio0 CHAN=112 ...
# CHAN vide = ne pas toucher au canal (à utiliser sur le Deco dont la radio suit la Livebox).
RADIO="${RADIO:-radio1}"
CHAN="${CHAN-1}"
export RADIO CHAN
SSID=WDSTEST
KEY=wdstest-2026
SAVED=/root/backhaul-test.saved
SELF=/root/backhaul-test.sh
PKG=/root/pkg
AUTOSTOP="${AUTOSTOP:-20}"

die() { echo "ERREUR : $*" >&2; exit 1; }

net_setup() {
	uci -q delete network.wdstest_dev
	uci -q delete network.wdstest
	uci set network.wdstest_dev=device
	uci set network.wdstest_dev.type=bridge
	uci set network.wdstest_dev.name=br-wdstest
	uci set network.wdstest_dev.bridge_empty=1
	uci set network.wdstest=interface
	uci set network.wdstest.device=br-wdstest
	uci set network.wdstest.proto=static
	uci set network.wdstest.ipaddr="$1"
	uci set network.wdstest.netmask=255.255.255.0
	uci commit network
}

set_channel() {
	[ -n "$CHAN" ] || return 0
	[ -f "$SAVED" ] || uci -q get "wireless.$RADIO.channel" > "$SAVED"
	uci set "wireless.$RADIO.channel=$CHAN"
}

new_iface() {
	uci -q delete wireless.wdstest
	uci set wireless.wdstest=wifi-iface
	uci set wireless.wdstest.device="$RADIO"
	uci set wireless.wdstest.network=wdstest
	uci set wireless.wdstest.key="$KEY"
}

apply() {
	# Deux pièges rencontrés sur un Deco en relais (relayd + firewall4), temporaires (jusqu'à « stop ») :
	# - la chaîne d'entrée de fw4 est en « policy drop » et ignore un pont hors zone ;
	# - relayd met une règle « iif lo lookup 16800 » avant la table principale : le trafic produit par le Deco
	#   (réponses ping) part vers la Livebox au lieu du pont de test.
	nft insert rule inet fw4 input iifname "br-wdstest" accept comment "wdstest" 2>/dev/null
	ip rule del to 10.77.0.0/24 lookup main pref 1 2>/dev/null
	ip rule add to 10.77.0.0/24 lookup main pref 1 2>/dev/null
	uci commit wireless
	/etc/init.d/network reload
	wifi reload "$RADIO"
	if [ "$AUTOSTOP" != 0 ]; then
		setsid sh -c "sleep $((AUTOSTOP * 60)); $SELF stop" </dev/null >/dev/null 2>&1 &
		echo "arrêt automatique dans $AUTOSTOP min ($SELF stop)"
	fi
	echo "appliqué ; attendre ~20 s puis : $0 status"
}

need_ip() { [ -n "$1" ] || die "adresse IP attendue (ex. 10.77.0.1)"; }

case "$1" in
status)
	echo "== wpad : $(apk info 2>/dev/null | grep -E '^wpad' | tr '\n' ' ')"
	echo "== radio $RADIO : canal $(uci -q get wireless.$RADIO.channel)"
	echo "== interfaces Wi-Fi"; iw dev | grep -E "Interface|type|ssid|channel"
	echo "== pont de test"; ip addr show br-wdstest 2>&1 | head -4; brctl show br-wdstest 2>&1 | head -5
	echo "== stations associées (radio 2,4 GHz)"; iw dev 2>/dev/null | awk '/Interface/{i=$2} /channel .*2[0-9][0-9][0-9] MHz/{print i}' | while read -r i; do iw dev "$i" station dump 2>/dev/null | grep -E "^Station|signal:|tx bitrate"; done
	echo "== mesh"; iw dev 2>/dev/null | awk '/Interface/{i=$2} /type mesh point/{print i}' | while read -r i; do iw dev "$i" mpath dump 2>&1 | head -5; done
	;;
wds-ap)
	need_ip "$2"
	net_setup "$2"; set_channel; new_iface
	uci set wireless.wdstest.mode=ap
	uci set wireless.wdstest.ssid="$SSID"
	uci set wireless.wdstest.hidden=1
	uci set wireless.wdstest.encryption=psk2
	uci set wireless.wdstest.wds=1
	apply
	;;
wds-sta)
	need_ip "$2"
	net_setup "$2"; set_channel; new_iface
	uci set wireless.wdstest.mode=sta
	uci set wireless.wdstest.ssid="$SSID"
	uci set wireless.wdstest.encryption=psk2
	uci set wireless.wdstest.wds=1
	apply
	;;
mesh)
	need_ip "$2"
	apk info -e wpad-mesh-mbedtls >/dev/null 2>&1 || die "wpad-mesh absent : lancer d'abord '$0 swap-mesh'"
	net_setup "$2"; set_channel; new_iface
	uci set wireless.wdstest.mode=mesh
	uci set wireless.wdstest.mesh_id="$SSID"
	uci set wireless.wdstest.encryption=sae
	uci set wireless.wdstest.mesh_fwding=1
	apply
	;;
probe)
	need_ip "$2"
	br=br-wdstest
	mine=$(uci -q get network.wdstest.ipaddr); last=${mine##*.}
	mac=02:77:00:00:00:$(printf %02x "$last")
	ip link show "$br" >/dev/null 2>&1 || die "$br absent : lancer wds-ap / wds-sta / mesh d'abord"
	echo "adresse MAC du pont forcée à $mac (différente de celle de l'interface Wi-Fi) :"
	echo "des trames avec cette adresse source ne passent que si le lien est un vrai pont (4addr ou maillage)."
	ip link set dev "$br" address "$mac" || die "impossible de changer l'adresse du pont"
	sleep 3
	echo "== ping $2 depuis $mine"
	ping -c 5 -W 2 "$2"; rc=$?
	echo "== adresses vues par le pont"; brctl showmacs "$br" 2>&1 | head -8
	[ $rc = 0 ] && echo "RESULTAT : la liaison relaie une adresse MAC étrangère (pont réel)" || echo "RESULTAT : AUCUNE réponse (pas de pont réel, ou liaison non établie : voir status)"
	;;
swap-mesh|swap-basic)
	if [ "$1" = swap-mesh ]; then new=wpad-mesh-mbedtls; old=wpad-basic-mbedtls; else new=wpad-basic-mbedtls; old=wpad-mesh-mbedtls; fi
	apk info -e "$new" >/dev/null 2>&1 && die "$new est déjà installé"
	f=$(ls $PKG/$new-*.apk 2>/dev/null | head -1); [ -n "$f" ] || die "$PKG/$new-*.apk introuvable"
	echo "remplacement de $old par $new (Wi-Fi coupé ~30 s sur ce Deco)"
	apk del "$old" && apk add --allow-untrusted --no-network "$f" || { echo "ECHEC : retour à $old"; apk add --allow-untrusted --no-network $PKG/$old-*.apk; die "remplacement échoué"; }
	wifi reload
	apk info | grep -E '^wpad'
	;;
stop)
	ip rule del to 10.77.0.0/24 lookup main pref 1 2>/dev/null
	for h in $(nft -a list chain inet fw4 input 2>/dev/null | sed -n 's/.*comment "wdstest" # handle \([0-9]*\)/\1/p'); do
		nft delete rule inet fw4 input handle "$h"
	done
	uci -q delete wireless.wdstest
	uci -q delete network.wdstest
	uci -q delete network.wdstest_dev
	if [ -f "$SAVED" ]; then
		c=$(cat "$SAVED"); [ -n "$c" ] && uci set "wireless.$RADIO.channel=$c"
		rm -f "$SAVED"
	fi
	uci commit wireless; uci commit network
	/etc/init.d/network reload
	wifi reload "$RADIO"
	echo "essai supprimé ; canal de $RADIO restauré : $(uci -q get wireless.$RADIO.channel)"
	;;
*)
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
	;;
esac
