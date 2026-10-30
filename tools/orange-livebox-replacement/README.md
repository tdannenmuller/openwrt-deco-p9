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
