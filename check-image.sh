#!/bin/bash
# Vérifie le résultat d'un build du Deco P9 avec le paquet plc-bcm (patch 0003).
# Lancé par build-image.sh ; peut l'être seul : WORK=/chemin ./check-image.sh
# Code de sortie : 0 si tout est bon, 1 sinon. Ne modifie rien.
set -uo pipefail
WORK="${WORK:-$HOME/openwrt-deco-p9-build}"
cd "$WORK" || { echo "dossier introuvable : $WORK"; exit 1; }

fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# set +o pipefail en sous-shell : évite un faux FAIL quand une commande comme
# `strings gros_fichier | grep -q motif` est coupée par SIGPIPE au moment où
# grep -q sort dès la première correspondance trouvée. grep a quand même trouvé
# ce qu'il cherchait ; seul son exit code à lui doit compter ici.
chk() { if (set +o pipefail; eval "$2") >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

ROOT=$(find build_dir -maxdepth 2 -type d -name 'root-ath79' 2>/dev/null | head -1)
IMG=bin/targets/ath79/generic
SYSUP=$(ls $IMG/*deco-p9*sysupgrade.bin 2>/dev/null | head -1)
FACT=$(ls $IMG/*deco-p9*factory.bin 2>/dev/null | head -1)
MANIF=$(ls $IMG/*deco-p9*.manifest 2>/dev/null | head -1)

echo "== Paquet et images"
chk "paquet plc-bcm construit" "ls bin/packages/*/base/plc-bcm-* 2>/dev/null | grep -q ."
chk "image sysupgrade présente" "[ -n \"$SYSUP\" ]"
chk "image factory présente"    "[ -n \"$FACT\" ]"
[ -n "$SYSUP" ] && chk "sysupgrade <= 13824k (14155776 octets) : $(stat -c %s "$SYSUP" 2>/dev/null) octets" "[ $(stat -c %s "$SYSUP") -le 14155776 ]"
[ -n "$FACT" ]  && chk "factory : product_name P9" "strings -n 8 '$FACT' | grep -q 'product_name:P9'"
[ -n "$MANIF" ] && for p in plc-bcm ucode-mod-socket ucode-mod-uci ucode-mod-fs ucode relayd luci-proto-relay; do
	chk "manifeste : $p" "grep -q '^$p ' '$MANIF'"
done

echo "== Contenu du rootfs ($ROOT)"
if [ -z "$ROOT" ]; then
	bad "rootfs introuvable"
else
	chk "/usr/sbin/plc-nmk exécutable"  "[ -x '$ROOT/usr/sbin/plc-nmk' ]"
	chk "/usr/sbin/plc-nmk : shebang ucode" "head -1 '$ROOT/usr/sbin/plc-nmk' | grep -q '^#!/usr/bin/ucode'"
	chk "/etc/init.d/plc exécutable"    "[ -x '$ROOT/etc/init.d/plc' ]"
	chk "/etc/rc.d/S99plc (activé au démarrage)" "[ -L '$ROOT/etc/rc.d/S99plc' ]"
	chk "/etc/config/plc : enabled 1"   "grep -q \"option enabled '1'\" '$ROOT/etc/config/plc'"
	chk "/etc/config/plc : NMK par défaut HomePlug AV" "grep -q \"option nmk '50d3e4933f855b7040784df815aa8db7'\" '$ROOT/etc/config/plc'"
	for m in socket uci fs; do chk "module ucode $m.so" "[ -f '$ROOT/usr/lib/ucode/$m.so' ]"; done
	chk "/usr/sbin/relayd présent"      "[ -x '$ROOT/usr/sbin/relayd' ]"
	chk "/etc/rc.d/S*relayd (activé au démarrage)" "ls '$ROOT'/etc/rc.d/S*relayd"
	chk "02_network : port 2 pour le P9" "awk '/deco-p9-v1v2/{f=1} f&&/2:lan:3/{ok=1} END{exit !ok}' '$ROOT/etc/board.d/02_network'"
fi

echo
if [ $fail = 0 ]; then echo "TOUT EST BON"; else echo "ECHECS : voir les lignes FAIL ci-dessus"; fi
exit $fail
