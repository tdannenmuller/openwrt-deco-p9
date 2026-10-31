#!/usr/bin/ucode
// Talks to the Broadcom powerline chip of the TP-Link Deco P9 (ethertype 0x8912).
//   plc.uc get-nmk | set-nmk <32 hex> | pushbutton | sync
// sync: reads /etc/config/plc (enabled, nmk) and writes the NMK to the chip if it differs.
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
// Chip MAC = Deco MAC + 5 (rule from the stock firmware)
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
	warn("send socket: ", socket.error(), "\n");
	exit(1);
}
let rx = socket.create(socket.AF_PACKET, socket.SOCK_RAW, 0x0003);
if (!rx || !rx.bind({ family: socket.AF_PACKET, protocol: 0x0003, interface: RX_IF, address: "00:00:00:00:00:00" })) {
	warn("receive socket: ", socket.error(), "\n");
	exit(1);
}

// Returns the payload (hex) of the reply, or null.
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
		return substr(d, 28 + off + 18);	// after version(1) type(2) 0000 OUI(3) seq(1)
	}
	return null;
}

function get_nmk() {
	let r = mme("5ca0", "2400");
	// r: status(1) length(2, LE) NMK(16)
	if (!r || substr(r, 0, 2) != "01" || substr(r, 2, 4) != "1000")
		return null;
	return substr(r, 6, 32);
}

// Writes the NMK and verifies it by reading it back. The chip often replies late
// (sometimes after the timeout) to a successful write: a missing acknowledgement is
// therefore not an error, only the read-back counts.
function write_nmk(n) {
	mme("18a0", n + "0000");
	sleep(SET_NMK_DELAY * 1000);
	for (let i = 0; i < 5; i++) {
		let back = get_nmk();
		if (back == n)
			return true;
		sleep(2000);
	}
	return false;
}

let cmd = ARGV[0];
if (cmd == "get-nmk") {
	let n = get_nmk();
	if (!n) {
		warn("no reply (after a write, wait 5 s)\n");
		exit(1);
	}
	print(n, "\n");
} else if (cmd == "set-nmk") {
	let n = lc(ARGV[1] ?? "");
	if (!match(n, /^[0-9a-f]{32}$/)) {
		warn("set-nmk expects 32 hexadecimal characters\n");
		exit(1);
	}
	if (!write_nmk(n)) {
		warn("the NMK read back does not match the one written\n");
		exit(1);
	}
	print("NMK written and verified: ", n, "\n");
} else if (cmd == "pushbutton") {
	let r = mme("8ca0", "00");
	print("reply: ", r ?? "none", "\n");
} else if (cmd == "sync") {
	function log(msg) {
		system([ "/usr/bin/logger", "-t", "plc", msg ]);
		print(msg, "\n");
	}
	let uci = cursor();
	let want = lc(uci.get("plc", "main", "nmk") ?? "");
	if (uci.get("plc", "main", "enabled") != "1") {
		log("disabled (plc.main.enabled != 1)");
		exit(0);
	}
	if (!match(want, /^[0-9a-f]{32}$/)) {
		log("plc.main.nmk missing or invalid: 32 hexadecimal characters expected");
		exit(1);
	}
	// The chip can take a while to reply after boot.
	let cur = null;
	for (let i = 0; i < 24 && !cur; i++) {
		cur = get_nmk();
		if (!cur)
			sleep(5000);
	}
	if (!cur) {
		log("the powerline chip does not reply, NMK unchanged");
		exit(1);
	}
	if (cur == want) {
		log("NMK already up to date");
		exit(0);
	}
	if (!write_nmk(want)) {
		log("the NMK read back does not match the one written");
		exit(1);
	}
	log("NMK written and verified");
} else {
	warn("usage: plc.uc get-nmk | set-nmk <32 hex> | pushbutton | sync\n");
	exit(1);
}
