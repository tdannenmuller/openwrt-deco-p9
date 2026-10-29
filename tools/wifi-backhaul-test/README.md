# Essai : liaison Wi-Fi « pont » entre deux Deco P9 (WDS et 802.11s), sans relayd

**Statut : WDS essayé le 29/10/2026 sur le 2,4 GHz (phase 1) puis sur le 5 GHz ; maillage 802.11s (phase 2) non fait.** Voir « Résultats » en bas.
Les commandes `swap-mesh`, `swap-basic` et `mesh` n'ont pas été essayées. Le script modifié après la phase 1
(règles `nft` et `ip rule` ajoutées dans `apply`/`stop`, variables `RADIO` et `CHAN`) a été utilisé pour l'essai 5 GHz ; `stop` y a aussi servi.

## Pourquoi

Une station Wi-Fi standard ne peut pas être mise dans un pont (elle n'émet que sous sa propre adresse MAC) :
c'est la raison d'être de `relayd`. Si les deux extrémités sont des Deco sous OpenWrt, deux solutions
donnent un vrai pont : **WDS (4addr)** et le **maillage 802.11s**. Cet essai dit lesquelles marchent ici.

Vérifié (lecture seule) : les deux radios de chaque Deco (`ath10k` 5 GHz, `ath9k` 2,4 GHz) annoncent
`AP/VLAN` et `mesh point`. C'est nécessaire, pas suffisant.

## Ce que l'essai teste, et ne teste pas

- Teste : l'association WDS/maillage sur la **radio 2,4 GHz (`ath9k`)**, et surtout qu'une trame dont l'adresse
  MAC source est **étrangère** à l'interface Wi-Fi traverse la liaison (`probe`). C'est ce qui prouve un pont réel.
- Ne teste **pas** la radio 5 GHz (`ath10k-ct`), celle qui servirait en vrai : le résultat sur `ath9k` ne vaut
  pas pour `ath10k`. Cela demanderait de toucher à la radio 5 GHz du Deco 1, qui porte sa liaison avec la Livebox.
- Ne mesure **pas** le débit.

## Garde-fous

- Seule la radio `radio1` (2,4 GHz) est touchée. Le CPL, le câble et le Wi-Fi 5 GHz restent en place.
- Le pont de test `br-wdstest` (adresses `10.77.0.x`) n'est **jamais** relié à `br-lan` : pas de boucle avec le CPL.
- Réseau de test : SSID `WDSTEST` (caché), clé `wdstest-2026` (publique, sans importance : l'essai dure quelques minutes).
- **Arrêt automatique** au bout de 20 min (`AUTOSTOP=<minutes>`, 0 pour désactiver) : `backhaul-test.sh stop`
  supprime tout et restaure le canal de la radio. Il tourne dans un processus du Deco ; il ne protège pas d'un figement.
- Pendant l'essai, le Wi-Fi 2,4 GHz du Deco 2 passe sur le canal 1 (celui du Deco 1) puis revient au canal 11.
- Pas de `network restart` : le script utilise `network reload` et `wifi reload radio1`.

## Préparatifs déjà faits

- Script copié sur les deux Deco : `/root/backhaul-test.sh` (la copie du dépôt est `backhaul-test.sh`).
- Paquets `wpad-mesh-mbedtls` et `wpad-basic-mbedtls` téléchargés dans `/root/pkg/` sur les deux Deco
  (1,4 Mo de flash chacun ; `rm -r /root/pkg` pour les retirer), identiques (SHA-256 comparés).

## Déroulement (rôles : Deco 1 = 10.77.0.1, Deco 2 = 10.77.0.2)

Joindre le Deco 2 par le Wi-Fi ou le CPL (`ssh root@192.168.0.6`) et le Deco 1 (`ssh root@192.168.0.2`).

### Phase 1 : WDS (sans changer de paquet)

1. Deco 1 : `/root/backhaul-test.sh wds-ap 10.77.0.1`  (recharge le Wi-Fi 2,4 GHz du Deco 1 quelques secondes)
2. Deco 2 : `/root/backhaul-test.sh wds-sta 10.77.0.2`
3. Attendre ~20 s, puis sur chaque Deco : `/root/backhaul-test.sh status` (le Deco 2 doit voir la station / le
   Deco 1 doit voir le Deco 2, et une interface `phy1-ap0.sta1` côté point d'accès indique le mode 4addr).
4. Deco 2 : `/root/backhaul-test.sh probe 10.77.0.1`.
   - Réponses : le WDS relaie une adresse étrangère, **donc un pont réel**.
   - Aucune réponse alors que l'association existe : le mode 4addr ne fonctionne pas (ou n'est pas actif).
5. Sur les deux : `/root/backhaul-test.sh stop`.

### Phase 2 : maillage 802.11s (change `wpad`, coupe le Wi-Fi ~30 s par Deco)

1. Deco 2 d'abord : `/root/backhaul-test.sh swap-mesh`. Si tout va bien, puis sur le Deco 1 :
   **attention, cela coupe son Wi-Fi client vers la Livebox pendant ~30 à 60 s (donc son accès Internet et le
   relais).** Le faire depuis le Deco 2 par SSH (le CPL reste en place), pas depuis une connexion Wi-Fi du Deco 1.
2. Les deux : `/root/backhaul-test.sh mesh 10.77.0.1` (Deco 1) et `... mesh 10.77.0.2` (Deco 2).
3. `status` (la table `mpath` doit montrer le voisin), puis `probe` comme ci-dessus.
4. `stop` sur les deux, puis `swap-basic` pour remettre `wpad-basic` (sauf si on garde le maillage).

## Si quelque chose casse

- `/root/backhaul-test.sh stop` sur le Deco concerné (ou attendre l'arrêt automatique).
- `swap-basic` si le Wi-Fi ne remonte pas après `swap-mesh`.
- Les configurations d'origine ne sont pas sauvegardées : le script n'ajoute que les sections `wireless.wdstest`,
  `network.wdstest`, `network.wdstest_dev`, et ne change que le canal de `radio1` (mémorisé dans
  `/root/backhaul-test.saved`).

## À noter dans NOTES.md après l'essai

Pour chaque mode : association réussie ou non, résultat de `probe`, messages de `logread | grep -E "hostapd|wpa|mesh"`,
et rappeler que le résultat vaut pour `ath9k` (2,4 GHz), pas pour `ath10k` (5 GHz).

## Résultats de la phase 1 (WDS, 29/10/2026, radio 2,4 GHz `ath9k` seulement)

**Le WDS (4addr) fonctionne comme un vrai pont sur `ath9k`.** Deco 1 en point d'accès (`wds-ap`), Deco 2 en client (`wds-sta`) :
- association WPA2 réussie (signal −42 dBm), interface `phy1-ap1.sta1` créée côté point d'accès, `4addr: on` côté client ;
- le Deco 1 a appris sur son interface WDS l'adresse MAC **étrangère** `02:77:00:00:00:02` (celle que `probe` impose au pont du Deco 2),
  et les trames ICMP avec cette adresse source arrivent bien (capture `tcpdump` sur le Deco 1) ;
- `probe` : 5 réponses sur 5, 1 à 26 ms, dans le sens Deco 2 vers Deco 1 ; le ping dans l'autre sens (`ping -I br-wdstest`) : 3 sur 3.

Non mesuré : le débit. Non essayé : le 5 GHz (`ath10k-ct`), le maillage 802.11s, la durée de stabilité (l'essai a duré quelques minutes).

**Pièges rencontrés (propres à un Deco en relais, sans rapport avec le WDS)** : les premiers `probe` échouaient sans réponse.
1. `firewall4` a une chaîne d'entrée en `policy drop` qui n'accepte que `br-lan` et `phy0-sta0` : un pont hors zone est ignoré
   (la chaîne de sortie, elle, est en `policy accept`).
2. **Cause réelle de l'absence de réponse** : `relayd` installe `ip rule 2: from all iif lo lookup 16800`, avant la table principale.
   Le trafic produit par le Deco lui-même (les réponses ping) allait donc vers la Livebox au lieu du pont de test.
   Un ping fait avec `-I br-wdstest` contourne cette règle, d'où un diagnostic trompeur (les compteurs `OutEchoReps` augmentaient).
   Contournement : `ip rule add to 10.77.0.0/24 lookup main pref 1`.
   **À retenir pour une vraie utilisation** : sur un Deco relais, tout réseau local supplémentaire a ce même problème.
3. `ip route get` de BusyBox n'est pas fiable (il affichait une route par défaut alors que la route directe existait).

## Après l'essai

`stop` sur les deux Deco a restauré les canaux (Deco 1 : 2,4 GHz canal 1 ; Deco 2 : canal 11) et supprimé toute la config de test ;
les règles `nft` et `ip rule` ajoutées à la main ont été retirées. `tcpdump-mini` est resté installé sur les deux Deco.

## Résultats de l'essai WDS sur le 5 GHz (`ath10k-ct`, 29/10/2026)

Même montage (Deco 1 en point d'accès `wds-ap`, Deco 2 en client `wds-sta`), avec `RADIO=radio0` ; Deco 1 sans toucher au canal
(`CHAN=` vide, il suit la Livebox : canal 112, VHT80), Deco 2 forcé sur `CHAN=112`. Le Deco 1 était relié au Mac par câble pendant l'essai.

**Le WDS (4addr) fonctionne aussi sur `ath10k-ct`.**
- Association WPA2 réussie (−53 dBm, débit négocié 390 / 585 Mbit/s, `4addr: on` côté client, interface `phy0-ap1.sta1` côté point d'accès).
- `probe` : 5 réponses sur 5 (1,7 à 12,9 ms) avec l'adresse MAC étrangère `02:77:00:00:00:02`, apprise par le Deco 1 sur son interface WDS.
- **Débit mesuré (iperf3, TCP, un flux, 10 s) : 196 Mbit/s dans chaque sens**, sans retransmission.
  Il est probablement limité par le processeur des Deco (l'iperf3 lui-même, ~38 % du CPU, et la commutation) plus que par la liaison :
  les autres mesures sur ces Deco plafonnent aussi vers 200 Mbit/s (voir NOTES.md). À ne pas lire comme la capacité du lien radio.
- Effets de bord : la radio 5 GHz du Deco 1 a été rechargée (sa liaison avec la Livebox est restée en place) ; celle du Deco 2 est passée
  sur le canal DFS 112 (attente CAC de 60 s) avant de revenir sur le canal 36 avec `stop`.
- Non mesuré : la stabilité dans la durée (l'essai a duré quelques minutes), le maillage 802.11s, le passage d'un trafic réel ou multiple.
  Le test a été fait avec les deux Deco proches l'un de l'autre.

**Conséquence** : pour deux Deco sous OpenWrt, une liaison Wi-Fi 5 GHz en vrai pont (WDS) est possible **sans `relayd`**, si les deux extrémités sont OpenWrt.
Elle ne dépend pas de la Livebox, qui ne supporte probablement pas le 4addr (non testé). Reste à décider de ce que doit faire la liaison montante
si le Deco passerelle remplace la Livebox (voir les notes sur CPL + Wi-Fi).
