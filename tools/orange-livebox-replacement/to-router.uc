#!/usr/bin/ucode
// Convertit un Deco (pont / point d'accès) en routeur derrière l'ONT Orange, avec annulation automatique.
//
//   to-router.uc plan    [full=1] [clé=valeur ...]   affiche ce qui serait modifié, ne touche à rien
//   to-router.uc check   [clé=valeur ...]            met en attente toutes les modifications de la conversion complète puis les
//                                                    ANNULE (« uci revert ») : vérifie qu'elles sont valides, sans rien appliquer
//   to-router.uc dry-run [clé=valeur ...]            applique SEULEMENT le VLAN du commutateur et l'interface WAN, annulation
//                                                    automatique après « timeout » s (jamais confirmée) : sert à voir ce qui part sur
//                                                    le fil, sans ONT. Ne change ni l'adresse LAN ni le DHCP.
//   to-router.uc convert mac=.. auth=.. go=yes [clé=valeur ...]
//                                                    conversion COMPLÈTE en routeur. Sans « go=yes » : affiche le plan et s'arrête.
//   to-router.uc restore [reload=no]                 revient à la configuration d'avant « convert » (sauvegarde dans /root/backup-router)
//   to-router.uc guard   [lan_ip=..]                 dit si « lan_ip » répond déjà (ce que convert vérifie avant de toucher à quoi que ce soit)
//   to-router.uc selftest                            lit les vérifications de succès de convert (wan, ping, DNS) et l'état des services
//   to-router.uc diag                                état du VLAN, de l'interface WAN et du périphérique
//
// Paramètres (clé=valeur) :
//   wan_port=3  vid=832  timeout=90 (dry-run) / 300 (convert)  qos=1 (dry-run : marquage 802.1p ; toujours actif en convert)
//   mac=<MAC de la Livebox remplacée>  auth=<option 90, hexadécimal séparé par « : »>   (obligatoires pour convert)
//   lan_ip=192.168.0.1  netmask=255.255.255.0  dhcp_start=100  dhcp_limit=150  force_link=1 (dry-run, test sans câble)
//
// convert, dans l'ordre : refuse (sans rien toucher) si mac/auth manquent, si « lan_ip » répond déjà (la Livebox est encore là),
// puis met en attente VLAN + WAN + LAN + DHCP, applique avec rollback rpcd, active et redémarre dnsmasq et firewall, et ne CONFIRME que si
// l'interface wan a un bail IPv4, qu'un ping vers 1.1.1.1 passe et que le DNS résout (deux fois de suite). Sinon rpcd restaure la
// configuration au bout du délai, et le script remet dnsmasq et firewall dans leur état d'avant. Journal : /root/to-router.log et
// « logread -e to-router ».
//
// Ne couvre PAS : les branchements physiques, un Deco figé, l'IPv6 (wan6 non configuré), odhcpd. JAMAIS exécuté avec une vraie ligne Orange.
import * as ubus from "ubus";
import * as fs from "fs";
import { cursor } from "uci";

let opts = {
	wan_port: "3", vid: "832", timeout: "", mac: "", auth: "",
	lan_ip: "192.168.0.1", netmask: "255.255.255.0", dhcp_start: "100", dhcp_limit: "150",
	qos: "", force_link: "", go: "", force: "", full: ""
};
// « Livebox4 » : option 77 = longueur (0x2b) + « FSVDSL_livebox.Internet.softathome.Livebox4 »
const USERCLASS77 = "2b46535644534c5f6c697665626f782e496e7465726e65742e736f66746174686f6d652e4c697665626f7834";
// jeton factice (plan, check, dry-run) : sert seulement à voir le format de l'option sur le fil. Pas un vrai jeton Orange.
const DUMMY_AUTH = "00:00:00:00:00:00:00:00:00:00:00:1a:09:00:00:05:58:01:03:41:01:0b:66:74:69:2f:74:65:73:74:65:75:72";
const DUMMY_MAC = "02:00:00:00:00:00";

let cmd = shift(ARGV);
for (let a in ARGV) {
	let m = match(a, /^([a-z_0-9]+)=(.*)$/);
	if (m)
		opts[m[1]] = m[2];
}

const LOG = "/root/to-router.log";
function ts() {
	let d = gmtime();
	return sprintf("%04d-%02d-%02d %02d:%02d:%02d", d.year, d.mon, d.mday, d.hour, d.min, d.sec);
}
function log(msg) {
	print(msg, "\n");
	system([ "/usr/bin/logger", "-t", "to-router", msg ]);
	let f = fs.open(LOG, "a");
	if (f) { f.write(ts() + " " + msg + "\n"); f.close(); }
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
c.load("dhcp");

function ports_without(vlan_section, port) {
	let p = c.get("network", vlan_section, "ports");
	if (type(p) == "array") p = join(" ", p);
	return filter(split(p, " "), (x) => replace(x, /[a-z]/g, "") != port);
}

// --- opérations à effectuer, dans l'ordre ---
// chaque élément : [méthode, arguments]. « plan » les affiche, les autres les exécutent.
// full = true : ajoute l'adresse LAN et le serveur DHCP (conversion complète).
function build_ops(full, mac, auth) {
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
	let mac_nc = replace(lc(mac), ":", "");

	push(ops, ["set", { config: "network", section: v1, values: { ports: join(" ", ports_without(v1, opts.wan_port)) } }]);
	push(ops, ["add", { config: "network", type: "switch_vlan", name: "wan_vlan", values: {
		device: "switch0", vlan: "" + idx, vid: opts.vid, ports: "0t " + opts.wan_port + "t" } }]);
	// priorité 802.1p : sans « type/ifname/vid » la section est ignorée (vérifié : p 0 sur le fil)
	if (full || opts.qos == "1")
		push(ops, ["add", { config: "network", type: "device", name: "wan_dev", values: {
			name: eth, type: "8021q", ifname: "eth0", vid: opts.vid,
			egress_qos_mapping: [ "0:6", "1:0", "6:6" ] } }]);
	let wan = {
		proto: "dhcp", device: eth, auto: "1",
		hostname: "livebox", vendorid: "sagem",
		macaddr: mac, clientid: "01" + mac_nc,
		// defaultreqopts=0 : sinon netifd ajoute 12 et 42 à la liste d'options demandées (vu sur le fil)
		defaultreqopts: "0", reqopts: "1 3 6 15 28 51 58 59 90 119 120 125",
		sendopts: [ "77:" + USERCLASS77, "90:" + auth ]
	};
	// force_link=1 : démarre le client DHCP même sans câble (test sans ONT seulement)
	if (!full && opts.force_link == "1")
		wan.force_link = "1";
	push(ops, ["add", { config: "network", type: "interface", name: "wan", values: wan }]);

	if (full) {
		// le Deco devient la passerelle : adresse LAN de la Livebox, plus de passerelle ni de DNS statiques sur le LAN
		push(ops, ["set", { config: "network", section: "lan", values: { ipaddr: opts.lan_ip, netmask: opts.netmask } }]);
		let del = filter([ "gateway", "dns" ], (o) => c.get("network", "lan", o) != null);
		if (length(del))
			push(ops, ["delete", { config: "network", section: "lan", options: del }]);
		// serveur DHCP du LAN
		push(ops, ["set", { config: "dhcp", section: "lan", values: {
			ignore: "0", start: opts.dhcp_start, limit: opts.dhcp_limit, leasetime: "12h", dhcpv4: "server" } }]);
	}
	return ops;
}

function show_ops(ops) {
	for (let o in ops)
		print(o[0], " ", sprintf("%.0J", o[1]), "\n");
}

function open_session(timeout) {
	let s = call("session", "create", { timeout });
	let sid = s.ubus_rpc_session;
	call("session", "grant", { ubus_rpc_session: sid, scope: "ubus", objects: [
		[ "uci", "get" ], [ "uci", "set" ], [ "uci", "add" ], [ "uci", "delete" ], [ "uci", "changes" ],
		[ "uci", "revert" ], [ "uci", "commit" ], [ "uci", "apply" ], [ "uci", "confirm" ], [ "uci", "rollback" ] ] });
	call("session", "grant", { ubus_rpc_session: sid, scope: "uci", objects: [ [ "*", "read" ], [ "*", "write" ] ] });
	return sid;
}

function stage(sid, ops) {
	for (let o in ops) {
		let a = o[1];
		a.ubus_rpc_session = sid;
		call("uci", o[0], a);
	}
}

function service_enabled(name) { return system([ "/etc/init.d/" + name, "enabled" ]) == 0; }
function service(name, action) { return system([ "/etc/init.d/" + name, action ]); }

// --- vérifications de succès de la conversion ---
function wan_ok() {
	let r = conn.call("network.interface.wan", "status", {});
	return r && r.up && length(r["ipv4-address"] ?? []) > 0;
}
function net_ok() {
	return system("ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1") == 0 && system("nslookup openwrt.org >/dev/null 2>&1") == 0;
}

// la Livebox (ou autre) répond-elle déjà à l'adresse que va prendre ce Deco ?
function lan_ip_taken() { return system(`ping -c 2 -W 2 '${opts.lan_ip}' >/dev/null 2>&1`) == 0; }

function convert_run() {
	let timeout = int(opts.timeout || "300");
	let ops = build_ops(true, opts.mac, opts.auth);
	let dnsmasq_was = service_enabled("dnsmasq"), firewall_was = service_enabled("firewall");
	log(`convert : début (dnsmasq actif au démarrage=${dnsmasq_was}, firewall=${firewall_was}, annulation dans ${timeout} s)`);

	// sauvegarde pour « restore » (retour en arrière APRÈS une confirmation, par exemple si la Livebox revient)
	system("mkdir -p /root/backup-router && cp /etc/config/network /etc/config/dhcp /root/backup-router/");
	fs.writefile("/root/backup-router/services", `dnsmasq=${dnsmasq_was ? 1 : 0}\nfirewall=${firewall_was ? 1 : 0}\n`);
	let sid = open_session(timeout + 900);
	stage(sid, ops);
	log("convert : modifications en attente, application avec rollback");
	call("uci", "apply", { rollback: true, timeout: timeout, ubus_rpc_session: sid });
	let t0 = time();

	// services : non couverts par le rollback de rpcd
	service("dnsmasq", "enable"); service("dnsmasq", "restart");
	service("firewall", "enable"); service("firewall", "restart");

	let good = 0, confirmed = false;
	while (time() - t0 < timeout - 25) {
		sleep(5000);
		if (wan_ok() && net_ok()) {
			if (++good >= 2) {
				call("uci", "confirm", { ubus_rpc_session: sid });
				confirmed = true;
				log("convert : bail WAN, ping 1.1.1.1 et DNS OK deux fois de suite : CONFIRMÉ");
				break;
			}
		} else
			good = 0;
	}
	if (!confirmed) {
		log("convert : WAN ou Internet KO dans le délai : pas de confirmation, rpcd va annuler la configuration");
		sleep((timeout - (time() - t0) + 20) * 1000);
		// la configuration est restaurée : remettre les services dans leur état d'avant
		if (!dnsmasq_was) { service("dnsmasq", "stop"); service("dnsmasq", "disable"); } else service("dnsmasq", "restart");
		if (!firewall_was) { service("firewall", "stop"); service("firewall", "disable"); } else service("firewall", "restart");
		log("convert : ANNULÉ, services remis dans leur état d'avant ; remettre les câbles d'origine (Livebox sur l'ONT)");
	}
}

switch (cmd) {
case "plan":
	print("Opérations qui seraient mises en attente puis appliquées (rien n'est modifié par « plan ») :\n");
	show_ops(build_ops(opts.full == "1", opts.mac || DUMMY_MAC, opts.auth || DUMMY_AUTH));
	break;

case "check": {
	let ops = build_ops(true, DUMMY_MAC, DUMMY_AUTH);
	let sid = open_session(120);
	stage(sid, ops);
	for (let cfg in [ "network", "dhcp" ]) {
		let r = call("uci", "changes", { config: cfg, ubus_rpc_session: sid });
		print("  ", cfg, " : ", length(r.changes ?? []), " opération(s) valide(s) mise(s) en attente\n");
		call("uci", "revert", { config: cfg, ubus_rpc_session: sid });
	}
	print("après revert, changements restants : ", system("uci changes | grep -q .") == 0 ? "OUI (anormal)" : "aucun", "\n");
	break;
}

case "dry-run": {
	let ops = build_ops(false, opts.mac || DUMMY_MAC, opts.auth || DUMMY_AUTH);
	let timeout = int(opts.timeout || "90");
	let sid = open_session(timeout + 600);
	stage(sid, ops);
	call("uci", "apply", { rollback: true, timeout: timeout, ubus_rpc_session: sid });
	print(`appliqué ; annulation automatique dans ${timeout} s (aucune confirmation n'est envoyée en dry-run)\n`);
	break;
}

case "convert": {
	if (!opts.mac || !opts.auth)
		die("mac=<MAC de la Livebox> et auth=<option 90> sont obligatoires pour convert");
	if (!match(opts.mac, /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/))
		die("mac au format AA:BB:CC:DD:EE:FF attendu");
	if (opts.go != "yes") {
		print("Conversion COMPLÈTE : voici ce qui serait fait. Rien n'est modifié sans go=yes.\n");
		show_ops(build_ops(true, opts.mac, opts.auth));
		break;
	}
	// garde-fou : la Livebox répond-elle encore à l'adresse que va prendre ce Deco ?
	if (opts.force != "yes" && lan_ip_taken())
		die(`${opts.lan_ip} répond déjà (la Livebox est-elle encore branchée sur le réseau ?). Rien n'a été modifié. force=yes pour passer outre.`);
	// lancement détaché : l'adresse LAN change et coupe la session SSH ; le script doit survivre
	let args = join(" ", map(keys(opts), (k) => opts[k] != "" ? `${k}='${opts[k]}'` : ""));
	system(`setsid ucode /root/to-router.uc convert-run ${args} </dev/null >>${LOG} 2>&1 &`);
	print("conversion lancée en arrière-plan ; suivre : tail -f " + LOG + " ou logread -e to-router\n");
	break;
}

case "restore": {
	// revient à la configuration d'avant « convert » (réseau, DHCP, dnsmasq, firewall). Ne remet PAS les câbles.
	const B = "/root/backup-router";
	if (!fs.access(B + "/network") || !fs.access(B + "/dhcp") || !fs.access(B + "/services"))
		die("pas de sauvegarde dans " + B + " (convert n'a jamais été lancé ici)");
	system(`cp ${B}/network ${B}/dhcp /etc/config/`);
	let was = {};
	for (let l in split(fs.readfile(B + "/services"), "\n")) {
		let m = match(l, /^([a-z]+)=([01])$/);
		if (m) was[m[1]] = m[2] == "1";
	}
	for (let s in [ "dnsmasq", "firewall" ]) {
		if (was[s]) { service(s, "enable"); service(s, "restart"); }
		else { service(s, "stop"); service(s, "disable"); }
	}
	if (opts.reload != "no")
		system("/etc/init.d/network reload");
	log(`restore : configuration d'avant convert remise (dnsmasq=${was.dnsmasq}, firewall=${was.firewall}) ; remettre les câbles d'origine`);
	break;
}

case "guard":
	print(opts.lan_ip, lan_ip_taken() ? " RÉPOND : convert refuserait (la Livebox est encore là)\n" : " ne répond pas : convert pourrait continuer\n");
	break;

case "selftest":
	print("wan_ok() = ", wan_ok() ? "oui" : "non", "\n");
	print("net_ok() = ", net_ok() ? "oui" : "non", "  (ping 1.1.1.1 et DNS)\n");
	for (let s in [ "dnsmasq", "firewall", "odhcpd" ])
		print("service ", s, " actif au démarrage : ", service_enabled(s) ? "oui" : "non", "\n");
	break;

case "convert-run":
	convert_run();
	break;

case "diag": {
	let sh = (cmdline) => { let p = fs.popen(cmdline + " 2>&1"); let o = p ? p.read("all") : "?"; if (p) p.close(); return o; };
	let eth = "eth0." + opts.vid;
	print("== VLAN du commutateur\n", sh("uci show network | grep -E \"switch_vlan|vlan|vid|ports\""));
	print("== périphérique ", eth, "\n", sh("ls /sys/class/net | grep -E \"^eth0\""), sh(`cat /proc/net/vlan/${eth}`));
	print("== interface wan\n", sh("ifstatus wan | head -30"));
	break;
}

default:
	die("commande attendue : plan | check | dry-run | convert | restore | guard | selftest | diag");
}
