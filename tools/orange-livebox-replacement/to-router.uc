#!/usr/bin/ucode
// Convertit un Deco (pont / point d'accès) en routeur derrière l'ONT Orange, avec annulation automatique.
//
//   to-router.uc plan    [clé=valeur ...]   affiche ce qui serait modifié, ne touche à rien
//   to-router.uc dry-run [clé=valeur ...]   applique SEULEMENT le VLAN du commutateur et l'interface WAN, avec annulation
//                                            automatique après « timeout » secondes (jamais confirmée) : sert à voir ce qui
//                                            part sur le fil, sans ONT branché
//   to-router.uc diag                       état du VLAN, de l'interface WAN et du périphérique
//
// Paramètres (clé=valeur) : wan_port=3  vid=832  timeout=90  mac=02:00:00:00:00:00  auth=<hexa de l'option 90>
//                           qos=1 (marquage 802.1p)  force_link=1 (test sans câble)
//
// Annulation : « ubus call uci apply » avec rollback (rpcd) ; sans « uci confirm » dans le délai, rpcd restaure la configuration.
// Ne couvre ni les branchements physiques, ni l'activation des services au démarrage, ni un Deco figé.
// JAMAIS exécuté avec une vraie ligne Orange : voir README.md.
import * as ubus from "ubus";
import * as fs from "fs";
import { cursor } from "uci";

let opts = {
	wan_port: "3", vid: "832", timeout: "90",
	mac: "02:00:00:00:00:00",
	// jeton factice : sert seulement à voir le format de l'option sur le fil. Pas un vrai jeton Orange.
	auth: "00:00:00:00:00:00:00:00:00:00:00:1a:09:00:00:05:58:01:03:41:01:0b:66:74:69:2f:74:65:73:74:65:75:72"
};
// « Livebox4 » : option 77 = longueur (0x2b) + « FSVDSL_livebox.Internet.softathome.Livebox4 »
const USERCLASS77 = "2b46535644534c5f6c697665626f782e496e7465726e65742e736f66746174686f6d652e4c697665626f7834";

let cmd = shift(ARGV);
for (let a in ARGV) {
	let m = match(a, /^([a-z_0-9]+)=(.*)$/);
	if (m)
		opts[m[1]] = m[2];
}

function die(msg) { warn("ERREUR : ", msg, "\n"); exit(1); }

let conn = ubus.connect();
if (!conn) die("ubus indisponible");

function call(obj, method, args) {
	let r = conn.call(obj, method, args);
	if (r == null && conn.error())
		die(`${obj}.${method} : ${conn.error()}`);
	return r;
}

// --- état actuel (lecture directe, sans session) ---
let c = cursor();
c.load("network");

function ports_without(vlan_section, port) {
	let p = c.get("network", vlan_section, "ports");
	if (type(p) == "array") p = join(" ", p);
	return filter(split(p, " "), (x) => replace(x, /[a-z]/g, "") != port);
}

// --- opérations à effectuer, dans l'ordre ---
// chaque élément : [méthode, arguments]. « plan » les affiche, « dry-run » les exécute.
function build_ops() {
	let ops = [];
	let v1 = null, used = {};
	c.foreach("network", "switch_vlan", (s) => {
		used[s.vlan] = true;
		if (s.vlan == "1")
			v1 = s[".name"];
	});
	if (!v1)
		die("VLAN 1 du commutateur introuvable dans /etc/config/network");
	let idx = 2;
	while (used[idx])
		idx++;
	let eth = "eth0." + opts.vid;
	let mac_nc = replace(lc(opts.mac), ":", "");

	push(ops, ["set", { config: "network", section: v1, values: { ports: join(" ", ports_without(v1, opts.wan_port)) } }]);
	push(ops, ["add", { config: "network", type: "switch_vlan", name: "wan_vlan", values: {
		device: "switch0", vlan: "" + idx, vid: opts.vid, ports: "0t " + opts.wan_port + "t" } }]);
	// priorité 802.1p : sans marquage, Orange semble brider l'émission (non vérifié ici). À tester : qos=1
	if (opts.qos == "1")
		push(ops, ["add", { config: "network", type: "device", name: "wan_dev", values: {
			name: eth, type: "8021q", ifname: "eth0", vid: opts.vid,
			egress_qos_mapping: [ "0:6", "1:0", "6:6" ] } }]);
	push(ops, ["add", { config: "network", type: "interface", name: "wan", values: {
		proto: "dhcp", device: eth, auto: "1",
		hostname: "livebox", vendorid: "sagem",
		macaddr: opts.mac, clientid: "01" + mac_nc,
		// defaultreqopts=0 : sinon netifd ajoute 12, 42 et 121 à la liste d'options demandées (vu sur le fil)
		defaultreqopts: "0", reqopts: "1 3 6 15 28 51 58 59 90 119 120 125",
		sendopts: [ "77:" + USERCLASS77, "90:" + opts.auth ] } }]);
	// force_link=1 : démarre le client DHCP même sans câble (test sans ONT seulement ; inutile avec un vrai lien)
	if (opts.force_link == "1")
		ops[length(ops) - 1][1].values.force_link = "1";
	return ops;
}

function show_ops(ops) {
	for (let o in ops)
		print(o[0], " ", sprintf("%.0J", o[1]), "\n");
}

switch (cmd) {
case "plan":
	print("Opérations qui seraient mises en attente puis appliquées (rien n'est modifié par « plan ») :\n");
	show_ops(build_ops());
	break;

case "dry-run": {
	let ops = build_ops();
	let timeout = int(opts.timeout);
	let s = call("session", "create", { timeout: timeout + 600 });
	let sid = s.ubus_rpc_session;
	call("session", "grant", { ubus_rpc_session: sid, scope: "ubus", objects: [
		[ "uci", "get" ], [ "uci", "set" ], [ "uci", "add" ], [ "uci", "delete" ], [ "uci", "changes" ],
		[ "uci", "revert" ], [ "uci", "commit" ], [ "uci", "apply" ], [ "uci", "confirm" ], [ "uci", "rollback" ] ] });
	call("session", "grant", { ubus_rpc_session: sid, scope: "uci", objects: [ [ "*", "read" ], [ "*", "write" ] ] });
	for (let o in ops) {
		let a = o[1];
		a.ubus_rpc_session = sid;
		call("uci", o[0], a);
	}
	print("changements en attente : ", sprintf("%.0J", call("uci", "changes", { config: "network", ubus_rpc_session: sid })), "\n");
	call("uci", "apply", { rollback: true, timeout: timeout, ubus_rpc_session: sid });
	print(`appliqué ; annulation automatique dans ${timeout} s (aucune confirmation n'est envoyée en dry-run)\n`);
	break;
}

case "diag": {
	let sh = (cmdline) => { let p = fs.popen(cmdline + " 2>&1"); let o = p ? p.read("all") : "?"; if (p) p.close(); return o; };
	let eth = "eth0." + opts.vid;
	print("== VLAN du commutateur\n", sh("uci show network | grep -E \"switch_vlan|vlan|vid|ports\""));
	print("== périphérique ", eth, "\n", sh("ls /sys/class/net | grep -E \"^eth0\""), sh(`cat /proc/net/vlan/${eth}`));
	print("== interface wan\n", sh("ifstatus wan | head -30"));
	break;
}

default:
	die("commande attendue : plan | dry-run | diag");
}
