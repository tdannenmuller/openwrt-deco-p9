#!/usr/bin/ucode
// Parle à la puce CPL Broadcom du TP-Link Deco P9 (ethertype 0x8912).
//   plc.uc get-nmk | set-nmk <32 hex> | pushbutton | sync
// sync : lit /etc/config/plc (enabled, nmk) et écrit la NMK sur la puce si elle diffère.
import * as socket from "socket";
import * as fs from "fs";
import { cursor } from "uci";

const TX_IF = "eth0.1";
const RX_IF = "eth0";
const SET_NMK_DELAY = 8;

function mac_of(ifname) {
	return lc(trim(fs.readfile("/sys/class/net/" + ifname + "/address")));
}
function colon(h) {
	let o = [];
	for (let i = 0; i < 12; i += 2)
		push(o, substr(h, i, 2));
	return join(":", o);
}
// MAC de la puce = MAC du Deco + 5 (règle du firmware d'origine)
function plc_mac(m) {
	let b = map(split(m, ":"), (x) => hex(x));
	let carry = 5;
	for (let i = 5; i >= 0 && carry; i--) {
		let s = b[i] + carry;
		b[i] = s & 0xff;
		carry = s >> 8;
	}
	return join("", map(b, (x) => sprintf("%02x", x)));
}

let src_mac = mac_of(TX_IF);
let src = replace(src_mac, ":", "");
let own = [ src, replace(mac_of(RX_IF), ":", "") ];
let dst = plc_mac(mac_of(RX_IF));
let seq = time() & 0xff;

let tx = socket.create(socket.AF_PACKET, socket.SOCK_RAW, 0x8912);
if (!tx || !tx.bind({ family: socket.AF_PACKET, protocol: 0x8912, interface: TX_IF, address: src_mac })) {
	warn("socket d'envoi: ", socket.error(), "\n");
	exit(1);
}
let rx = socket.create(socket.AF_PACKET, socket.SOCK_RAW, 0x0003);
if (!rx || !rx.bind({ family: socket.AF_PACKET, protocol: 0x0003, interface: RX_IF, address: "00:00:00:00:00:00" })) {
	warn("socket de réception: ", socket.error(), "\n");
	exit(1);
}

// Renvoie la charge utile (en hexadécimal) de la réponse, ou null.
function mme(mmtype, payload) {
	seq = (seq + 1) & 0xff;
	let frame = dst + src + "8912" + "02" + mmtype + "0000" + "001f84" + sprintf("%02x", seq) + payload;
	while (length(frame) < 120)
		frame += "00";
	tx.send(hexdec(frame));
	let end = time() + 4;
	while (time() < end) {
		let p = socket.poll(200, [ rx, socket.POLLIN ]);
		if (!length(p) || !p[0][1])
			continue;
		let d = hexenc(rx.recv(2048));
		let off = (substr(d, 24, 4) == "8100") ? 8 : 0;
		if (substr(d, 24 + off, 4) != "8912" || (substr(d, 12, 12) in own))
			continue;
		return substr(d, 28 + off + 18);	// après version(1) type(2) 0000 OUI(3) seq(1)
	}
	return null;
}

function get_nmk() {
	let r = mme("5ca0", "2400");
	// r : statut(1) longueur(2, LE) NMK(16)
	if (!r || substr(r, 0, 2) != "01" || substr(r, 2, 4) != "1000")
		return null;
	return substr(r, 6, 32);
}

let cmd = ARGV[0];
if (cmd == "get-nmk") {
	let n = get_nmk();
	if (!n) {
		warn("pas de réponse (après une écriture, attendre 5 s)\n");
		exit(1);
	}
	print(n, "\n");
} else if (cmd == "set-nmk") {
	let n = lc(ARGV[1] ?? "");
	if (!match(n, /^[0-9a-f]{32}$/)) {
		warn("set-nmk attend 32 caractères hexadécimaux\n");
		exit(1);
	}
	if (mme("18a0", n + "0000") == null) {
		warn("pas de réponse à l'écriture\n");
		exit(1);
	}
	sleep(SET_NMK_DELAY * 1000);
	let back = get_nmk();
	if (back != n) {
		warn("relecture différente : ", back ?? "aucune réponse", "\n");
		exit(1);
	}
	print("NMK écrite et relue : ", back, "\n");
} else if (cmd == "pushbutton") {
	let r = mme("8ca0", "00");
	print("réponse : ", r ?? "aucune", "\n");
} else if (cmd == "sync") {
	function log(msg) {
		system([ "/usr/bin/logger", "-t", "plc", msg ]);
		print(msg, "\n");
	}
	let uci = cursor();
	let want = lc(uci.get("plc", "main", "nmk") ?? "");
	if (uci.get("plc", "main", "enabled") != "1") {
		log("désactivé (plc.main.enabled != 1)");
		exit(0);
	}
	if (!match(want, /^[0-9a-f]{32}$/)) {
		log("plc.main.nmk absente ou invalide : 32 caractères hexadécimaux attendus");
		exit(1);
	}
	// La puce peut mettre du temps à répondre après le démarrage.
	let cur = null;
	for (let i = 0; i < 24 && !cur; i++) {
		cur = get_nmk();
		if (!cur)
			sleep(5000);
	}
	if (!cur) {
		log("la puce CPL ne répond pas, NMK inchangée");
		exit(1);
	}
	if (cur == want) {
		log("NMK déjà à jour");
		exit(0);
	}
	if (mme("18a0", want + "0000") == null) {
		log("pas de réponse à l'écriture de la NMK");
		exit(1);
	}
	sleep(SET_NMK_DELAY * 1000);
	if (get_nmk() != want) {
		log("la NMK relue ne correspond pas à celle écrite");
		exit(1);
	}
	log("NMK écrite et relue");
} else {
	warn("usage : plc.uc get-nmk | set-nmk <32 hex> | pushbutton | sync\n");
	exit(1);
}
