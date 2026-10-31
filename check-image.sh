#!/bin/bash
# Checks the result of a Deco P9 build with the plc-bcm package (patch 0003).
# Run by build-image.sh; can also run alone: WORK=/path ./check-image.sh
# Exit code: 0 if everything is fine, 1 otherwise. Changes nothing.
set -uo pipefail
WORK="${WORK:-$HOME/openwrt-deco-p9-build}"
cd "$WORK" || { echo "directory not found: $WORK"; exit 1; }

fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# set +o pipefail in a subshell: avoids a false FAIL when a command such as
# `strings big_file | grep -q pattern` is cut short by SIGPIPE as soon as
# grep -q exits on the first match. grep did find what it was looking for;
# only its own exit code must count here.
chk() { if (set +o pipefail; eval "$2") >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

ROOT=$(find build_dir -maxdepth 2 -type d -name 'root-ath79' 2>/dev/null | head -1)
IMG=bin/targets/ath79/generic
SYSUP=$(ls $IMG/*deco-p9*sysupgrade.bin 2>/dev/null | head -1)
FACT=$(ls $IMG/*deco-p9*factory.bin 2>/dev/null | head -1)
MANIF=$(ls $IMG/*deco-p9*.manifest 2>/dev/null | head -1)

echo "== Package and images"
chk "plc-bcm package built" "ls bin/packages/*/base/plc-bcm-* 2>/dev/null | grep -q ."
chk "sysupgrade image present" "[ -n \"$SYSUP\" ]"
chk "factory image present"    "[ -n \"$FACT\" ]"
[ -n "$SYSUP" ] && chk "sysupgrade <= 13824k (14155776 bytes): $(stat -c %s "$SYSUP" 2>/dev/null) bytes" "[ $(stat -c %s "$SYSUP") -le 14155776 ]"
[ -n "$FACT" ]  && chk "factory: product_name P9" "strings -n 8 '$FACT' | grep -q 'product_name:P9'"
[ -n "$MANIF" ] && for p in plc-bcm ucode-mod-socket ucode-mod-uci ucode-mod-fs ucode relayd luci-proto-relay; do
	chk "manifest: $p" "grep -q '^$p ' '$MANIF'"
done

echo "== Rootfs content ($ROOT)"
if [ -z "$ROOT" ]; then
	bad "rootfs not found"
else
	chk "/usr/sbin/plc-nmk executable"  "[ -x '$ROOT/usr/sbin/plc-nmk' ]"
	chk "/usr/sbin/plc-nmk: ucode shebang" "head -1 '$ROOT/usr/sbin/plc-nmk' | grep -q '^#!/usr/bin/ucode'"
	chk "/etc/init.d/plc executable"    "[ -x '$ROOT/etc/init.d/plc' ]"
	chk "/etc/rc.d/S99plc (enabled at boot)" "[ -L '$ROOT/etc/rc.d/S99plc' ]"
	chk "/etc/config/plc: enabled 1"   "grep -q \"option enabled '1'\" '$ROOT/etc/config/plc'"
	chk "/etc/config/plc: default HomePlug AV NMK" "grep -q \"option nmk '50d3e4933f855b7040784df815aa8db7'\" '$ROOT/etc/config/plc'"
	for m in socket uci fs; do chk "ucode module $m.so" "[ -f '$ROOT/usr/lib/ucode/$m.so' ]"; done
	chk "/usr/sbin/relayd present"      "[ -x '$ROOT/usr/sbin/relayd' ]"
	chk "/etc/rc.d/S*relayd (enabled at boot)" "ls '$ROOT'/etc/rc.d/S*relayd"
	chk "02_network: port 2 for the P9" "awk '/deco-p9-v1v2/{f=1} f&&/2:lan:3/{ok=1} END{exit !ok}' '$ROOT/etc/board.d/02_network'"
fi

echo
if [ $fail = 0 ]; then echo "ALL GOOD"; else echo "FAILURES: see the FAIL lines above"; fi
exit $fail
