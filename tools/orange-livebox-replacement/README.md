# Remplacer une Livebox Orange (fibre) par un Deco P9

**Statut : jamais essayé sur l'installation réelle. Tout ce qui suit vient de recherches et de dépôts
communautaires (liens ci-dessous), adaptés à notre matériel (commutateur `swconfig`, pas `DSA`), pas d'un
test sur une vraie ligne Orange.** Le Deco 1 a déjà un câble Ethernet vers la Livebox (voir `NOTES.md`,
« Deco 1 relié à la Livebox par câble ») ; c'est ce même port qui devrait passer de la Livebox à l'ONT.

## Pourquoi ce n'est pas juste un câble et du DHCP

Orange authentifie le routeur comme une vraie Livebox, pas seulement par VLAN. Sans ça, le DHCP
n'aboutit pas, silencieusement (pas de message d'erreur, juste pas de bail).

## Ce qu'il faut, dans l'ordre

1. **Un port WAN dédié.** Notre configuration actuelle met les deux ports Ethernet du P9 en LAN. Il faut
   en retirer un (3 ou 5) pour en faire un port WAN, tagué sur un nouveau VLAN, dans **Réseau > Commutateur**
   (page `swconfig`, pas l'écran DSA d'un routeur plus récent) :
   - Retirer le port choisi du VLAN 1 (le LAN existant).
   - Créer le VLAN **832** avec le port CPU et ce port tous les deux **tagués** (`t`) : les trames de l'ONT
     arrivent déjà étiquetées, le port CPU doit l'être aussi pour que `eth0.832` apparaisse côté Linux.

2. **L'interface WAN**, avec les options DHCP qui imitent une Livebox. Gabarit : `network-wan-snippet.txt`
   dans ce dossier. Remplacer :
   - `11:22:33:AA:BB:CC` par l'adresse MAC **de la vraie Livebox** qu'on remplace (étiquette dessous, ou
     son interface d'administration). Le client DHCP doit se présenter avec cette MAC (option 61/`clientid`),
     pas celle du Deco : Orange authentifie via l'option 90, pas l'adresse de couche 2 (voir `orange-gen-auth.sh`).
   - `Livebox4` dans `userclass` (option 77) par le modèle réel si ce n'est pas une Livebox 4
     (`Livebox3`, `Livebox5`, `Livebox6`…) : seul le dernier caractère hexadécimal change (`33` → `34` pour
     passer de 3 à 4, etc.), le reste de la chaîne est fixe.

3. **Le jeton d'authentification (option 90 IPv4, option 11 IPv6).** Calculé par `orange-gen-auth.sh` à
   partir des identifiants du compte Orange (espace client, pas le Wi-Fi), stockés dans `orange-auth`
   **jamais commité avec de vraies valeurs**. Expire au bout de 5 à 8 semaines d'après les sources
   communautaires : `orange-auth-init.sh` (démarrage) et `97-orange-config` (hotplug sur coupure WAN)
   le régénèrent automatiquement. `99-wan6-delay` retarde `wan6` le temps que `wan` obtienne son bail.

4. **Le point non résolu : la priorité réseau (802.1p/PCP).** Les sources trouvées (routeurs à interface
   `8021q` gérée par le noyau, pas `swconfig`) disent qu'Orange bride l'émission à environ 6 Mbit/s si les
   trames DHCP ne sortent pas marquées en priorité 6. Une fonctionnalité de marquage par port existe pour
   la puce `ar8327/ar8337` de notre commutateur, mais sans confirmation qu'elle est présente dans cette
   version d'OpenWrt ni de syntaxe UCI vérifiée. **Ne rien inventer ici** : brancher d'abord sans ce
   réglage, mesurer le débit montant, et creuser seulement si besoin.

## Avant de débrancher la Livebox

- Garder la Livebox de côté, câble prêt à la rebrancher : en cas d'échec de l'authentification ou de
  VLAN refusé, rien n'est endommagé, mais la connexion s'arrête.
- Ce test concerne uniquement internet. Pas de décodeur TV Orange ni de ligne téléphonique fixe
  dans ce foyer : non traité ici, et probablement pas transposable sans travail supplémentaire
  (VLAN et `igmpproxy` pour la TV, matériel propre à la Livebox pour le téléphone).

## Ce qui n'est PAS vérifié

- Tout. Aucun branchement réel à l'ONT n'a eu lieu.
- Que `swconfig` sur ce commutateur a un équivalent du marquage PCP par port utilisé par les
  guides basés sur un périphérique `8021q` noyau (voir point 4).
- Qu'une Livebox 4 n'a pas d'autre différence que la chaîne `userclass` par rapport à une Livebox 3.
- Le calcul réel du jeton d'authentification avec de vrais identifiants Orange.
- Que l'adresse MAC clonée suffit, sans avoir besoin de notifier Orange du changement de matériel.

## Sources (communautaires, pas de documentation Orange officielle)

- https://github.com/golfromeo-fr/openwrt-turris-omnia-orange-france — référence principale pour le DHCP,
  le VLAN 832 et le marquage PCP (sur un routeur à périphérique `8021q`, pas `swconfig`).
- https://lig-membres.imag.fr/rousseau/tech/2021/02/28/fibre-orange-avec-routeur-er-x.html
- https://www.lafois.com/2021/10/09/replacing-orange-livebox-by-an-edgerouter-with-ftth/
- https://vincent.bernat.ch/en/blog/2019-orange-livebox-linux
- https://wiki.csnu.org/index.php/Fibre_orange_en_DHCP_avec_routeur_pfsense

## Essai à blanc sur un Deco sans ONT (30/10/2026)

`to-router.uc` (sur le Deco 2, avec annulation automatique) a appliqué **seulement** le VLAN 832 du commutateur et l'interface `wan`,
puis tout été annulé seul au bout du délai. Ce qui est **vérifié**, sans ONT ni câble :
- `swconfig` crée bien le périphérique **`eth0.832`** (VID 832) quand on ajoute `config switch_vlan` avec `vlan '2'`, `vid '832'`, `ports '0t 3t'` ;
- le client DHCP envoie sur ce VLAN un DISCOVER avec `Hostname livebox`, `Vendor-Class sagem`, `Client-ID ether <MAC>`, `User-Class
  FSVDSL_livebox.Internet.softathome.Livebox4` et l'option 90 (donc `vendorid` + `clientid` + `sendopts 77` et `90` suffisent) ;
- **priorité 802.1p** : avec une section `device` complète (`type '8021q'`, `ifname`, `vid`, `egress_qos_mapping`), les trames sortent en
  `vlan 832, p 6` et `/proc/net/vlan/eth0.832` affiche `EGRESS priority mappings: 0:6 1:0 6:6`. Sans `type/ifname/vid`, la section est
  ignorée (`p 0`). **Non vérifié** : que la puce `ar8327` conserve cette priorité sur le fil du port WAN (il faudrait une capture de
  l'autre côté du câble), et qu'Orange en tienne compte ;
- l'annulation automatique restaure bien tout (VLAN 1 à `2 3 5 0t`, plus d'`eth0.832`, plus d'interface `wan`).

**Erreurs trouvées dans le gabarit d'origine** (corrigées dans `network-wan-snippet.txt`) : `vendorclass` et `userclass` n'existent pas dans
le client DHCP d'OpenWrt ; `sendopts` 12, 60 et 61 faisaient doublon ; sans `defaultreqopts '0'`, `netifd` ajoute les options 12 et 42 à la liste
demandée. Le `clientid` DHCPv6 est à remplacer aussi (voir le gabarit). Le `/etc/config/orange-auth` et les scripts de jeton n'ont pas été exécutés.

## Conversion complète en routeur : `to-router.uc convert` (écrite le 30/10/2026, **jamais exécutée de bout en bout**)

Ce qu'elle fait, dans l'ordre : refuse sans rien toucher si `mac` ou `auth` manquent, ou si l'adresse LAN visée (`192.168.0.1`) répond déjà ;
sauvegarde `network`, `dhcp` et l'état des services dans `/root/backup-router` ; met en attente VLAN 832 + WAN (+ marquage 802.1p) + adresse
LAN `192.168.0.1` (sans passerelle ni DNS statiques) + serveur DHCP ; applique avec le rollback de `rpcd` (300 s) ; active et redémarre
`dnsmasq` et `firewall` ; et **ne confirme que si** l'interface `wan` a un bail IPv4, que `ping 1.1.1.1` passe et que le DNS résout, deux fois de
suite. Sinon `rpcd` restaure la configuration et le script remet `dnsmasq` et `firewall` dans leur état d'avant. Elle se lance détachée de la session
SSH (l'adresse LAN change). `to-router.uc restore` revient à l'état d'avant **après** une confirmation (ne remet pas les câbles).

**Vérifié sur un Deco relié à votre vrai réseau (donc sans appliquer la conversion)** :
`plan full=1` (opérations attendues), `check` (29 opérations réseau et 1 opération DHCP mises en attente, valides, puis annulées, aucun reliquat),
`guard` (refuse bien quand `192.168.0.1` répond, laisse passer sur une adresse libre), `selftest` (vérifications de succès et état des services lus
sans erreur), `restore` (refus sans sauvegarde ; avec une sauvegarde identique, fichiers inchangés), le générateur de jeton en mode `AUTH_ONLY=1` avec
des identifiants factices, et — par le `dry-run` plus haut — l'application avec rollback du VLAN et du WAN.

**Non vérifié, et ne peut pas l'être sans risque** : l'application de l'adresse LAN et du serveur DHCP (un serveur DHCP sur un Deco relié à votre
réseau répondrait aux appareils de la maison), la confirmation automatique, l'activation des services, la restauration après échec, et tout ce qui
concerne l'ONT et Orange.

### Ce que le rollback ne couvre pas
Les branchements physiques ; un Deco figé (le 29/10, un Deco s'est figé jusqu'à un redémarrage manuel) ; l'IPv6 (`wan6` non configuré, `odhcpd`
non touché) ; le renouvellement du jeton (5 à 8 semaines d'après les sources communautaires) : `orange-gen-auth.sh` et `97-orange-config` du
dossier modifient la configuration directement et n'ont pas été adaptés à ce flux ; les réservations DHCP et les adresses fixes de la Livebox.

### Procédure et liste de contrôle (jour J)
Avant :
1. **Internet indépendant pour la session de travail** : Wi-Fi du Mac sur le partage de connexion du téléphone, et un adaptateur Ethernet vers un port LAN
   du Deco (IP manuelle `192.168.0.10`, sans routeur). Sans cela, la session perd Internet pendant le test.
2. Noter l'adresse MAC de la Livebox (étiquette), garder la Livebox à côté avec ses câbles. Fenêtre courte, quand personne n'a besoin d'Internet.
3. Copier sur le Deco : `to-router.uc` (dans `/root/`), `orange-gen-auth.sh`, et créer `/etc/config/orange-auth` (identifiants Orange, **jamais commités**).
4. Trancher la question du **mot de passe** : essayer d'abord avec une valeur bidon (le README ne peut pas affirmer qu'Orange la vérifie encore).
5. `AUTH_ONLY=1 sh orange-gen-auth.sh` pour obtenir le jeton, puis `ucode /root/to-router.uc convert mac=AA:BB:.. auth=...` (sans `go=yes` : affiche le plan).

Le jour :
6. **Éteindre la Livebox** (ou débrancher son câble du Deco) : sinon `convert` refuse (`192.168.0.1` répond).
7. `ucode /root/to-router.uc convert mac=.. auth=.. go=yes` : la conversion démarre en arrière-plan (300 s pour réussir).
8. **Brancher le câble de l'ONT dans le port 3** du Deco dans la minute qui suit. Ne pas le brancher avant : le port 3 est encore dans le LAN.
9. Suivre : `logread -e to-router` (ou `tail -f /root/to-router.log`) jusqu'à « CONFIRMÉ » ou « ANNULÉ ».
10. Si « ANNULÉ » : débrancher l'ONT du Deco, remettre l'ONT sur la Livebox, la rallumer. Si on veut revenir plus tard : `to-router.uc restore`.

### Écarts connus à valider en réel
La priorité 802.1p sur le fil du port WAN, l'acceptation du jeton par Orange, l'IPv6, le décodeur TV et le téléphone fixe (non traités : pas dans ce foyer),
et le fait que `192.168.0.1` convienne (appareils à adresse fixe, plage DHCP `100` à `249` à confirmer).

## Résultat du test réel et enseignements (30/10/2026)

**La conversion a fonctionné sur une ligne Orange FTTH** : le Deco a pris la place de la Livebox et a obtenu l'adresse publique de celle-ci
(`/21`, passerelle, DNS d'Orange, bail de 3 jours), avec Internet et DNS. Ce qu'il a fallu comprendre pour y arriver :

1. **Un premier essai a échoué** (bail dans `172.16.0.0/16`, passerelle muette) avec un mot de passe bidon, le sel et l'octet du jeton
   générés par `orange-gen-auth.sh`, un nom d'hôte, l'option 121, sans option 125 et avec l'adresse MAC du Deco. La cause n'a **pas été isolée** :
   plusieurs choses ont changé à la fois avant le succès.
2. **Capture de la vraie Livebox** : `to-router.uc tap go=yes` met le Deco en pont transparent du VLAN 832 entre l'ONT et la Livebox (le processeur en
   tiers), puis `tcpdump` sur `eth0` (`vlan 832 and (udp port 67 or udp port 68)`) voit la requête DHCP de la Livebox, avec son **jeton réel** (option 90 : sel
   de 16 caractères imprimables aléatoires, octet aléatoire, condensat), son option 125, pas de nom d'hôte, 12 options demandées sans la 121, priorité 802.1p 6.
3. **Rejeu du jeton capturé** avec une requête alignée sur celle de la Livebox (y compris l'adresse MAC sur le fil, à régler dans la section `device`) :
   **adresse publique obtenue**. Le mot de passe n'a pas été nécessaire : le jeton contient déjà son condensat. Le jeton **expirera** (5 à 8 semaines d'après
   les sources communautaires, non vérifié) : il faudra le recapturer en remettant la Livebox derrière le Deco avec `tap`. Il est dans la configuration du Deco
   (`network.wan.sendopts`) : toute sauvegarde de configuration est sensible.
4. **La Livebox et le Deco ne peuvent pas être actifs ensemble** (même identité chez Orange) : éteindre la Livebox avant `convert`.

**Défauts connus de `to-router.uc`**
- **La confirmation automatique ne s'exécute pas jusqu'au bout** : le processus s'arrête après un ou deux passages de la boucle d'attente, sans erreur ni
  signe de mémoire saturée (deux essais, cause non trouvée ; la boucle isolée tourne bien). Il faut donc **confirmer à la main** : `to-router.uc confirm`,
  qui utilise la session mémorisée dans `/tmp/to-router.sid`. Sans confirmation, `rpcd` annule au bout du délai (300 s).
- **Seule la session qui a appliqué peut annuler ou confirmer** (une autre session reçoit « Permission denied ») : `untap` ne marche donc que si la session
  mémorisée existe ; sinon attendre l'expiration du délai.
- Ne pas tester `dry-run` avec `wan_port` égal au port où est branché le poste de travail : il en est coupé le temps du délai (arrivé une fois).

## Débit et marquage 802.1p : mesures (30/10/2026)

**Le marquage de tout le trafic en priorité 6 bride l'émission.** Même chemin (`iperf3`, 4 flux, depuis le Deco vers un serveur public à Paris) :

| Marquage | Réception | Émission |
|---|---|---|
| Tout en priorité 6 (mapping `0:6` sans règles) | 266 Mbit/s | **4,5 Mbit/s** |
| Données en 0, contrôle (ICMP, IGMP, DHCP) en 6 | 271 Mbit/s | **218 Mbit/s** |

**Réglage retenu (mesuré le 30/10/2026, voir plus bas pour l'accélération)** : le périphérique `eth0.832` n'a que le mapping `6:6`, donc le trafic ordinaire
(priorité 0) sort en priorité 0 sur le fil ; des règles `nft` (table `orange_prio` en hook `output`, service `orange-prio`) ne marquent en 6 que le contrôle généré par
le Deco (ICMP, IGMP, DHCP unicast). `convert` installe ce mapping, ces règles et active l'accélération logicielle. Un schéma antérieur (mapping `0:6 1:0 6:6` plus des
règles `postrouting` mettant les données en priorité 1) donnait les mêmes débits sans accélération mais **ne fonctionne pas avec elle** : les flux accélérés ne passent
plus par netfilter, ils auraient gardé la priorité 0 et le mapping `0:6` les aurait remis en priorité 6, donc bridés.
**Écart avec la Livebox** : la demande DHCP *broadcast* d'`udhcpc` (socket brut, invisible pour `nft`) part désormais en priorité 0 alors que la Livebox l'envoie en 6.
Orange l'a acceptée (bail obtenu en moins d'une seconde) et l'émission n'a pas été bridée ; c'est une mesure unique, rien ne garantit qu'Orange ne changera pas.
**Non vérifié** : le comportement après un redémarrage complet, et la reprise par un `sysupgrade` (le service et le fichier ne sont pas dans l'image).

**Plafond d'environ 320 Mbit/s en filaire, dû au processeur du Deco** : depuis un NAS filaire, un flux HTTPS donne 321 Mbit/s avec le processeur du Deco à 0 %
d'inactivité et 93 à 98 % de traitement d'interruptions. Quatre flux donnent 279 Mbit/s au total (processeur saturé aussi). Depuis le Wi-Fi d'un Mac (390 Mbit/s négociés),
environ 200 Mbit/s en émission avec le processeur libre à environ 60 % : là, c'est le Wi-Fi. Aucune mesure ne montre un plafond côté Orange à ce niveau.

**Pièges de mesure rencontrés** : `wget` de BusyBox est lent et en HTTPS il sature le processeur du Deco (il mesure le Deco, pas la ligne) ; utiliser `iperf3` ou un
client externe. Un serveur public peut être mauvais en réception (23 à 35 Mbit/s sur l'un, 177 sur un autre depuis le même Mac). `proof.ovh.net` redirige HTTP vers
HTTPS et ne sert qu'un flux de huit en parallèle. Des `wget` lancés en parallèle puis tués par `timeout` peuvent rester actifs : toujours les arrêter de force.

### Accélération logicielle des flux (`flow_offloading`) : mesures du 30/10/2026
`firewall.@defaults[0].flow_offloading='1'` (le pare-feu crée un `flowtable` sur `eth0` et les deux radios ; les modules `nf_flow_table` étaient déjà dans l'image).
Appliqué avec le rollback de `rpcd`, puis confirmé. Même client filaire (le NAS), même serveur, un flux HTTPS :

| | Sans accélération | Avec accélération |
|---|---|---|
| Réception | 321 puis 339 et 361 Mbit/s | **818 et 850 Mbit/s** |
| Émission (NAS vers Cloudflare) | 114 à 199 Mbit/s | 162 et 167 Mbit/s (non bridée) |
| Processeur du Deco pendant la réception | 0 % libre, 93 à 98 % d'interruptions | 0 à 4 % libre, 94 à 100 % d'interruptions |

37 flux marqués `OFFLOAD` dans conntrack ; les 60 trames TCP sortantes capturées étaient en `p 0`. Depuis le Mac en Wi-Fi : émission 214 Mbit/s (193 à 198 avant),
réception 151 Mbit/s (le Wi-Fi limite). **Le processeur reste saturé** : on ne sait pas ce que le Deco pourrait encore débiter, ni si 850 Mbit/s est limité par lui, par OVH ou par le NAS.
**Non vérifié** : la stabilité dans la durée (mesures sur quelques minutes), le comportement avec beaucoup de flux simultanés (huit flux vers OVH n'ont pas pu être mesurés),
et les effets de bord connus de l'accélération logicielle (par exemple sur des règles de pare-feu ou de QoS ajoutées plus tard).
