# Support OpenWrt pour le TP-Link Deco P9

Branche : `deco-p9`, basée sur OpenWrt `main` au commit `6b7ea6896a`.
Deux patchs dans `patches/`. Rien n'a été flashé, aucun appareil touché.

## État : l'image est construite

Build fait le 27/10/2026 sur Ubuntu 24.04 (Linux, disque sensible à la casse), noyau 6.18.55, depuis main au commit `6b7ea6896a` plus les 2 patchs. Il n'y a pas eu de Docker (pas de démon ici) : `build-native.sh` fait le même travail directement sur une machine Linux. `build.sh` (Docker) n'a **pas** été testé.

Dossier `images/` :

| Fichier | SHA256 |
|---|---|
| `openwrt-ath79-generic-tplink_deco-p9-v1v2-squashfs-factory.bin` | `2fba753a8aae3ed5fdee48842709a9312a80be9da16ab6b08bc05d29256cdb0d` |
| `openwrt-ath79-generic-tplink_deco-p9-v1v2-squashfs-sysupgrade.bin` | `2880f4fed78ed7fba5da98e95149561bf23b52f56ec7f3afc6136cd74f19474e` |

Les SHA256 d'un autre build ne seront pas identiques (dates dans l'image). Garde ces deux fichiers.
Contenu : `luci`, `luci-ssl`, `kmod-ath10k-ct`, `ath10k-firmware-qca9888-ct`.

## Vérifications faites sur l'image (sans matériel)

- Le build passe. Le profil indique les appareils `tplink,deco-p9-v1v2` et `deco-p9-v1v2`, donc une installation du fork peut passer au sysupgrade sans `-F`.
- Taille du sysupgrade : 7 864 617 octets pour une limite de 14 155 776. Il reste environ 6 Mo.
- Le dtb contient `tplink,deco-p9-v1v2` et `TP-Link Deco P9 v1v2`.
- En-tête uImage valide (`27051956`, « MIPS OpenWrt Linux-6.18.55 »).
- Rootfs : squashfs valide (xz, 4,7 Mo), placé juste après le noyau, comme dans l'image M4R officielle.
- Image factory comparée à celle du M4R officiel (snapshot) : mêmes partitions de `fs-uboot` à `radio`, même structure d'en-tête. Seule la liste de support change : 12 lignes `P9` contre 16 lignes `M4R`.
- Le noyau fait 2,9 Mo. Il ne tiendrait pas dans l'ancienne partition fixe de 2 Mo du fork ; la partition `firmware` de 14 Mo de main n'a pas ce problème. Le M4R officiel a la même particularité.

## Vérifié avec le firmware d'origine P9 1.3.0 (Build 20250804)

Fichier : `P9_en_1.3.0 Build 20250804 Rel. 58832_US_EU_AU_JP_up.bin` (téléchargé sur le site TP-Link).
- **Liste de support : identique** à celle du fork et de mon patch (produit `P9`, versions 1.0.0 et 2.0.0, 6 special_id chacune, dans le même ordre).
- **Mise en page flash : identique** à l'entrée M4R de main : u-boot 0x80000, firmware 0x80000 à 0xe80000 (os-image 0x200000 + file-system 0xc00000), product-info 0xe80000, puis les mêmes partitions jusqu'à `radio` 0xff0000.
- Le firmware d'origine contient `fw-type:Cloud`. Je n'ai pas vérifié si l'image OpenWrt écrit la même chose.
- Les `special_id` couvrent seulement 6 régions pour chaque version. Si ton Deco a un autre `special_id` (étiquette ou `device-id`), l'image sera refusée par le firmware d'origine. À vérifier sur ton appareil.
- Le board id `DECO-P9-V1V2` est le nom donné par OpenWrt. Il n'apparaît pas dans le firmware d'origine, donc ce n'est pas vérifiable ainsi.
- Différence connue : le firmware d'origine sépare `os-image` et `file-system` à une adresse fixe (0x280000). L'outil OpenWrt, comme pour le M4R, place la limite selon la taille du noyau. C'est le fonctionnement normal des images OpenWrt pour ces appareils.

## Ce que j'ai fait et vérifié ici

- Compilé l'outil `tplink-safeloader` avec l'entrée P9 (sans erreur ni avertissement).
- Généré des images factices (noyau et rootfs aléatoires) pour `DECO-M4R-V1` et `DECO-P9-V1V2`.
  - Image factory : seule la liste de support change (`product_name:P9` au lieu de `M4R`).
  - Image sysupgrade : identique entre les deux (elle ne contient pas la liste de support).
- Ce ne sont que des tests de l'outil, pas de vraies images.

## Ce qui est repris du fork (groupe a)

| Élément | Source dans le fork | Dans mon patch |
|---|---|---|
| Board id `DECO-P9-V1V2` | `tplink-safeloader.c` (branche master du fork) | identique |
| Liste de support (12 lignes, produit `P9`, versions 1.0.0 et 2.0.0, 6 special_id chacune) | même fichier, commit « update safeloader with boardid's from oem firmware » | identique, mot pour mot |
| Compatible `tplink,deco-p9-v1v2` | dts du fork | identique |
| `SUPPORTED_DEVICES += deco-p9-v1v2` | `generic-tp-link.mk` du fork | identique |
| `IMAGE_SIZE := 13824k` | fork | identique (même valeur que le M4R de main) |
| Réseau : ports 3 et 5 en LAN | `02_network` du fork | identique au M4R de main |
| Calibration (art 0x1000 et 0x5000) et MAC (config 0x8) | dts + script caldata du fork | via le dts M4R de main (nvmem), mêmes adresses |

Choix de réutilisation :
- Le dts du fork est une copie exacte du dts M4R du fork (seuls le nom et le compatible changent).
- J'ai donc copié le dts M4R de **main** en changeant seulement le nom et le compatible. Je n'ai pas fait de `.dtsi` commun : cela aurait modifié le M4R, que je ne peux pas tester.
- L'entrée safeloader reprend la mise en page flash du M4R de main (partition `firmware` de 0xe00000, `soft_ver` par défaut). La version du fork était plus ancienne (`os-image` et `file-system` séparés, `soft_ver = NULL`) et ne correspond plus au code de main.
- L'entrée safeloader est dans un patch (`tools/firmware-utils/patches/`) car cet outil est maintenant téléchargé depuis un dépôt externe.

## Ce qui est écarté, et pourquoi

- **Port switch du CPL (groupe b)** : écarté des patchs 0001 et 0002 (les images de `images/` n'ont pas le CPL). Le patch 0003 le met dans le LAN par défaut et ajoute le paquet `plc-bcm`. Voir « CPL » plus bas.
- **FastPath / shortcut-fe (groupe c)** : écarté. Code lié au noyau 5.4, non maintenu, absent de main, source de bugs. Le fork lui-même l'a supprimé dans « move Deco-P9 to master ».
- **LED `red:wlan2g` sur le GPIO 1** : écartée. Elle est dans le dts du fork mais absente du M4R de main. Je ne peux pas confirmer le GPIO.
- **Modifs de `config-5.4` / `config-5.10`** : écartées, bruit de rebase du fork, sans lien avec l'appareil.
- **Essais de performance** : écartés, hors périmètre.

## Problèmes trouvés dans le fork

- L'entrée safeloader finale du fork a des virgules en trop à la fin de chaque ligne de la liste de support. Je n'ai pas testé si elle compile ; je l'ai corrigée (virgule seulement à la fin). Les valeurs n'ont pas changé.
- Le port switch du CPL est passé de **4** à **2** entre deux commits du fork, sans explication. Le port 2 est le bon (vérifié sur le matériel).

## CPL : activer, désactiver, configurer

### Réseau (switch)

Le CPL est sur le **port 2** du switch (vérifié le 28/10/2026 : lien actif à 1000 Mbit/s sans câble branché, ports 4 et autres à l'arrêt). Par défaut le switch ne met que les ports 3 et 5 dans le LAN, donc le port 2 reste isolé.

**Piège** : les ports doivent être dans **une seule valeur** `option ports`. Avec `list ports '3 5 0t'` plus `list ports '2'` (ce que faisait la commande `uci add_list` des anciennes notes), le VLAN 1 du switch restait **vide** (`swconfig dev switch0 vlan 1 show` affichait `ports:` sans rien) : même les ports 3 et 5 n'étaient plus dans le LAN. Le Deco restait joignable seulement parce qu'il passe par le Wi-Fi (relayd). Je n'ai pas testé `list ports '3 5 0t'` seul : la cause exacte (liste de deux entrées, ou entrée contenant des espaces) n'est pas isolée ; la valeur unique `'2 3 5 0t'` fonctionne.

Pour **activer** :
```sh
uci delete network.@switch_vlan[0].ports
uci set network.@switch_vlan[0].ports='2 3 5 0t'
uci commit network && /etc/init.d/network reload
swconfig dev switch0 vlan 1 show     # attendu : ports: 0t 2 3 5
```
Pour **désactiver** : même commande avec `ports='3 5 0t'`.

### La puce CPL est un Broadcom (pas Qualcomm)

`open-plc-utils` (`plctool`) ne marche **pas** : il parle le protocole Qualcomm/Atheros (ethertype `0x88e1`, OUI `00:B0:52`) et la puce ne répond pas. Elle répond en revanche à des trames HomePlug AV standard (`CC_DISCOVER_LIST`) et au protocole propriétaire ci-dessous. Le firmware d'origine (`libplcapi.so`, `plcManager`) gère les deux familles. Le chiffrement « Broadcom » est une déduction (ethertype `0x8912` et OUI `00:1F:84`, lu dans `hpMakeBCMPacket`) ; je n'ai pas vu la référence de la puce.

Le stock ne pilote **aucun GPIO** pour le CPL : il lui parle par des trames brutes sur le port 2 (interface `eth0-p2`). Le MAC de la puce est le MAC LAN du Deco **+ 5** (règle du script `plc_mac_fix` du stock ; ici `1c:3b:f3:16:d2:c8` + 5 = `1c:3b:f3:16:d2:cd`).

### Protocole Broadcom (déduit du désassemblage de `libplcapi.so`)

Source : fonctions `hpMakeBCMPacket`, `hpBCMPushButtonStart`, `hpGetBCMNmk`, `hpSetBCMNmk` (firmware 1.3.0, désassemblées avec `llvm-mc` ; adresses `0x11b80`, `0xf77c`, `0xe008`, `0xe10c`).

Trame Ethernet (complétée à 60 octets) :

| Offset | Taille | Contenu |
|---|---|---|
| 0 | 6 | MAC de la puce (MAC du Deco + 5) |
| 6 | 6 | MAC source (interface d'envoi) |
| 12 | 2 | ethertype `0x8912` |
| 14 | 1 | version `0x02` |
| 15 | 2 | type de message, **little-endian sur le fil** (ex. `8C A0` = `0xA08C`) |
| 17 | 2 | `00 00` |
| 19 | 3 | OUI `00 1F 84` |
| 22 | 1 | numéro de séquence |
| 23 | n | charge utile |

La réponse a le même format : type + 1 (`0xA08C` → `0xA08D`), même OUI. Envoyer sur `eth0.1` (VLAN 1, taggé).

| Message | Type (octets sur le fil) | Charge utile | Réponse | Vérifié |
|---|---|---|---|---|
| Pushbutton start | `0xA08C` (`8C A0`) | `00` | `0xA08D`, charge `00` | oui, réponse reçue ; effet sur l'appairage non vérifié (pas de partenaire) |
| Lire la NMK | `0xA05C` (`5C A0`) | `24 00` (paramètre 36) | `0xA05D` : `01` (statut), `10 00` (longueur 16), puis 16 octets de NMK | oui |
| Écrire la NMK | `0xA018` (`18 A0`) | 16 octets de NMK + `00 00` | `0xA019` : `00` | oui |

Remarques :
- Après une écriture, la puce met **plus de 3 s** à répondre. Attendre ~5 s avant de relire, sinon les réponses se décalent.
- La NMK écrite **survit à un redémarrage du Deco** (testé : écriture, `reboot`, relecture). Non testé : coupure de courant complète.
- `hpSetBCMNmk` a un paramètre qui déclenche ensuite un second message (type `0xA060`, charge qui commence par `04` + constante `01 02 …`). Non décodé et non nécessaire : l'écriture seule suffit.
- Autres messages vus dans le code mais **non testés** : `hpGetNwInfoFromBCM`, `hpSetBCMMac`, `hpBCMGetEthSts`, `hpResetBCMFacDef` (remise à zéro d'usine, à éviter), `hpRebootBCMDev`.

### Paquet OpenWrt `plc-bcm` et patch 0003 (firmware « prêt à l'emploi »)

Le patch `patches/0003-…` (à appliquer avec `git am`, `build.sh` le fait déjà) ajoute :
- le paquet `package/utils/plc-bcm` : `/usr/sbin/plc-nmk` (l'outil `ucode`, identique à `tools/plc.uc`), le service `/etc/init.d/plc` (démarrage en arrière-plan) et `/etc/config/plc` (conservé au `sysupgrade`, car dans `CONFFILES`). Dépendances : `ucode`, `ucode-mod-fs`, `ucode-mod-socket`, `ucode-mod-uci` (chaque module `ucode` est un paquet séparé : `uci` n'est pas garanti sans `luci`) ;
- `plc-bcm` dans `DEVICE_PACKAGES` du Deco P9 : il est donc dans l'image sans modifier `.config` ;
- le port 2 dans le LAN par défaut pour cette carte (`02_network`, nouvelle entrée `tplink,deco-p9-v1v2` séparée de M4R et S4).

**NMK par défaut** : `/etc/config/plc` est livré avec `enabled '1'` et la NMK standard HomePlug AV (`50d3e4933f855b7040784df815aa8db7`, mot de passe « HomePlugAV », vérifiée avec `hpavkey -M HomePlugAV`), celle de tous les adaptateurs CPL neufs. Deux Deco neufs se voient donc sans réglage. **Conséquence de sécurité** : cette clé est publique, tout appareil CPL branché sur le même circuit électrique peut rejoindre le réseau, donc le LAN. À changer sur chaque Deco dès l'installation :
```sh
uci set plc.main.nmk='<32 caractères hexadécimaux>'; uci commit plc; /etc/init.d/plc restart
```
Pour désactiver le CPL : `uci set plc.main.enabled='0'` (le port 2 reste dans le LAN, sans effet sans puce active).

**Vérifié** : les trois patchs s'appliquent sans conflit (`git am`) sur la base `6b7ea6896a` et donnent l'arbre attendu ; les fichiers du paquet sont ceux testés sur les Deco (lecture, écriture, démarrage avec correction de la NMK).

**NON vérifié : le paquet et l'image n'ont pas été construits.** Le `Makefile` de `plc-bcm` suit celui d'un paquet existant sans compilation (`gre`), mais n'a pas été exécuté (pas de machine Linux disponible pendant ce travail ; macOS n'est pas supporté par OpenWrt). Restent à faire, sur une machine de build : construire l'image, la flasher, et vérifier que `/etc/config/plc`, `/etc/init.d/plc` (activé au démarrage, lien `S99plc`) et `/usr/sbin/plc-nmk` sont présents, que le service journalise `plc: NMK écrite et relue` (ou « déjà à jour »), que le port 2 est dans le VLAN 1 sans intervention, et que deux Deco neufs se joignent par le CPL. Le défaut « pas de réponse à l'écriture de la NMK » (la puce répond parfois après le délai) est corrigé : `plc.uc` écrit puis vérifie par relecture (jusqu'à 5 essais), l'absence d'accusé n'est plus une erreur ; ce cas « accusé en retard » n'a **pas** pu être reproduit pour le tester (les écritures de test ont été acquittées à temps). Pas testé non plus : une image sans `luci`, le comportement quand la puce ne répond pas dans les 2 minutes d'attente, et une puce dont le MAC n'est pas « MAC du Deco + 5 » (le stock le corrigeait ; ce service ne le fait pas).

### Appairer deux Deco : utiliser la même NMK

Il n'y a pas d'appairage manuel sur le Deco. Le stock fixe la NMK à partir d'un nom de réseau (valeur par défaut `decoP93pack` remplacée par une valeur aléatoire à chaque démarrage). Sous OpenWrt, on fixe la **même NMK de 16 octets** sur les deux puces ; pas de bouton nécessaire.

La NMK de ce réseau est dans `deco-p9/plc-nmk.txt` (hors dépôt, ne pas la publier). Son écriture sur le premier Deco a été vérifiée par relecture. **Vérifié le 28/10/2026 avec deux Deco P9 sous OpenWrt** : après avoir écrit la même NMK sur les deux puces (`set-nmk`), le second Deco (192.168.1.1, sans accès Internet) a répondu au ping du premier et de la Livebox, et le switch du second a appris le MAC du premier **sur son port 2** (CPL). Les deux NMK d'origine étaient différentes, donc le lien vient bien de la NMK commune. Mesures : environ 3 ms vers le premier Deco, 7 à 10 ms vers la Livebox (3 essais, 0 % de perte). Débit et stabilité non mesurés.

Python ne tient pas sur la flash du Deco (14,7 Mo pour 5,8 Mo libres) : préférer `tools/plc.uc` (voir plus bas). Pour utiliser `mme.py`, on installe Python dans la RAM (perdu au redémarrage, sans importance puisque la NMK persiste) :
```sh
apk update
mkdir -p /tmp/py /tmp/dl && cd /tmp/dl
apk fetch python3-light python3-base libpython3-3.14 libatomic1
apk extract --allow-untrusted --destination /tmp/py /tmp/dl/*.apk
export LD_LIBRARY_PATH=/tmp/py/usr/lib:/tmp/py/lib PYTHONHOME=/tmp/py/usr
```
Puis le script `tools/mme.py` (copié sur le Deco, par exemple `ssh root@<ip> 'cat > /tmp/mme.py' < tools/mme.py`) :
```sh
python3 /tmp/mme.py get-nmk
python3 /tmp/mme.py set-nmk <32 caractères hexadécimaux>   # écrit, attend 8 s, relit et compare
python3 /tmp/mme.py pushbutton
```
Par défaut il écrit sur `eth0.1` et vise le MAC du Deco + 5 (options `-i` et `-d`). Testé le 28/10/2026 : `get-nmk` et `set-nmk` sur le premier Deco.

**Sans Python : `tools/plc.uc`** (même protocole, en `ucode`, déjà présent dans l'image de base). Il ne manque que `ucode-mod-socket` (24 Ko, contre 14,7 Mo pour Python), qui tient dans la flash du Deco :
```sh
apk add ucode-mod-socket          # Deco avec accès Internet ; sinon, extraire dans /tmp (voir ci-dessus)
ucode /tmp/plc.uc get-nmk
ucode /tmp/plc.uc set-nmk <32 caractères hexadécimaux>
ucode /tmp/plc.uc pushbutton
```
Testé le 28/10/2026 : `get-nmk` sur les deux Deco, `set-nmk` (même valeur, avec relecture) sur le premier. `pushbutton` non relancé depuis cette version. Particularités de l'API `ucode` : le socket doit être lié par `interface` (nom) avec une adresse MAC valide, pas par `ifindex` ; et un filtre `0x8912` ne livre aucune trame (cause non élucidée), donc le script reçoit tout (`ETH_P_ALL`) sur `eth0` et filtre lui-même.

**Service de démarrage** (`tools/plc-service/` + `tools/plc.uc`) : à chaque démarrage, il lit `/etc/config/plc` et, si la NMK de la puce est différente, l'écrit puis la relit. Il tourne en arrière-plan (procd) sans bloquer le démarrage, attend l'interface `eth0.1` (jusqu'à 60 s) puis la réponse de la puce (jusqu'à 2 min), et journalise sous l'étiquette `plc` (`logread | grep plc:`).

Installation (Deco avec accès Internet pour `apk`) :
```sh
apk add ucode-mod-socket
cp tools/plc.uc /usr/sbin/plc-nmk && chmod +x /usr/sbin/plc-nmk
cp tools/plc-service/etc/init.d/plc /etc/init.d/plc && chmod +x /etc/init.d/plc
cp tools/plc-service/etc/config/plc /etc/config/plc
uci set plc.main.nmk='<32 caractères hexadécimaux>'; uci set plc.main.enabled='1'; uci commit plc
/etc/init.d/plc enable && /etc/init.d/plc start
```
La NMK reste sur le Deco (dans `/etc/config/plc`), jamais dans l'image ni dans le dépôt. Le fichier fourni a `enabled '0'` et une NMK vide : sans configuration, le service ne fait rien.

Testé le 28/10/2026 sur le premier Deco : (1) service désactivé : ne fait rien ; (2) NMK déjà à jour : rien n'est écrit ; (3) NMK différente : écrite et relue, puis restaurée de la même façon ; (4) démarrage : avec une mauvaise NMK volontairement écrite sur la puce puis un `reboot`, le service l'a corrigée tout seul (journal `NMK écrite et relue`) et le second Deco est redevenu joignable par le CPL.

**Non fait / non testé** : installation sur le second Deco (sans accès Internet, il faudrait y copier `ucode-mod-socket`) ; un vrai paquet OpenWrt (aucun `Makefile` : les fichiers se copient à la main, rien n'est ajouté à l'image) ; démarrage à froid après coupure de courant ; image fraîche jamais passée par le firmware d'origine. Le service n'écrit la NMK que si la puce répond ; si elle ne répond jamais, il abandonne après 2 minutes et ne réessaie pas avant le prochain démarrage ou `service plc restart`.

**Non vérifié** :
- La persistance de la NMK après coupure de courant complète.
- Le débit et la stabilité du lien CPL dans la durée.
- Le fabricant exact de la puce (déduit, pas lu).

## Construire

Le plus simple, sur une machine Linux avec la toolchain : `./build-image.sh` (applique les **trois** patchs sur le commit `6b7ea6896a3a83c9ae80d31e8d35d911e032268f`, configure, compile, puis lance `./check-image.sh` qui vérifie le paquet `plc-bcm` et le rootfs). `CLAUDE.md` décrit la procédure pour un agent. Ces deux scripts n'ont **pas encore été exécutés**. Les scripts plus anciens ci-dessous (`build.sh`, `build-native.sh`) donnent le même résultat pour le reste.


```sh
cd out && ./build.sh        # Docker (non testé)
./build-native.sh              # Linux direct (testé), après : apt install build-essential gawk flex bison libncurses-dev libssl-dev python3-setuptools swig rsync unzip zlib1g-dev file wget libelf-dev
```
Le script Docker utilise un volume Docker (`openwrt-src`) sur disque Linux, donc pas de problème de casse sur macOS.
Il fixe le commit de main `6b7ea6896a` pour que le build soit reproductible, applique les deux patchs, active `luci`, `luci-ssl` et le profil P9, puis compile.

Fichiers produits dans le volume :
`bin/targets/ath79/generic/openwrt-ath79-generic-tplink_deco-p9-v1v2-squashfs-factory.bin` et `...-sysupgrade.bin`.
Pour les copier sur le Mac :
```sh
docker run --rm -v openwrt-src:/src -v "$PWD":/out debian:12 sh -c 'cp /src/openwrt/bin/targets/ath79/generic/*deco-p9* /out/'
shasum -a 256 *deco-p9*
```

### Variante non-ct
Par défaut : `kmod-ath10k-ct` et `ath10k-firmware-qca9888-ct` (comme le M4R). Pour la variante standard, dans `build.sh` ajoute au `.config` :
```
# CONFIG_PACKAGE_kmod-ath10k-ct is not set
# CONFIG_PACKAGE_ath10k-firmware-qca9888-ct is not set
CONFIG_PACKAGE_kmod-ath10k=y
CONFIG_PACKAGE_ath10k-firmware-qca9888=y
```
Le fork utilisait la variante non-ct. Je n'ai pas vérifié si QCA9886 se comporte pareil.

## Vérifier l'image (à faire après le build)

1. Le build se termine sans erreur et produit les deux fichiers `factory` et `sysupgrade`.
2. Taille : `ls -l` du sysupgrade doit rester sous `IMAGE_SIZE`, soit 13824k (14155776 octets). Avec `luci-ssl`, c'est à surveiller.
3. En-têtes : compare avec une image M4R officielle (`openwrt-ath79-generic-tplink_deco-m4r-v1-squashfs-factory.bin` du site OpenWrt). Attendu : mêmes partitions et mêmes tailles, seule la liste `SupportList` change (`P9`).
   ```sh
   strings -n 20 factory.bin | grep product_name
   ```
4. Rootfs : `binwalk` ou `unsquashfs -s` sur la partie squashfs. Le magic `hsqs` doit être présent et la partition doit finir en `0xe80000` au plus.
5. Compare les octets de l'en-tête (`xxd | head`) des deux factory.

## Méthode TFTP (à privilégier si le flash par l'interface web est ignoré)

Constat : le firmware d'origine 1.3.0 a ignoré notre image factory sans message d'erreur. Il contient `fw-type:Cloud` et un bloc final de 4 Ko qui ressemble à une signature, que notre image n'a pas (hypothèse, non confirmée).

Source : [guide selfhosthero pour le M4R](https://selfhosthero.com/openwrt-tp-link-deco-m4r/), qui utilise le fichier `deco_all_webfailsafe_faux_fw_tftp_v2.bin` du développeur « naf » (forum OpenWrt). **Non vérifié sur le P9.** Je n'ai pas ce fichier et je n'ai pas pu l'inspecter.

Principe : le mode récupération du Deco (bouton reset au branchement) propose une page web `192.168.0.1`. Le faux firmware fait télécharger par TFTP un fichier `initramfs-kernel.bin` depuis `192.168.0.2`. OpenWrt démarre alors **en RAM seulement**. Rien n'est écrit dans la flash tant qu'on ne lance pas le sysupgrade.

Étapes (adaptées à notre image) :
1. Avant tout, vérifie le fichier exploit : télécharge-le depuis le message d'origine sur le forum OpenWrt et envoie-le-moi. Je regarde sa liste de support : si elle ne contient pas `P9`, la page de récupération le refusera.
2. Sur le Mac : Ethernet direct vers le Deco, IP fixe `192.168.0.2`, masque `255.255.255.0`, sans routeur. Serveur TFTP sur le port 69 qui sert un fichier nommé exactement `initramfs-kernel.bin` : copie dedans `openwrt-ath79-generic-tplink_deco-p9-v1v2-initramfs-kernel.bin` renommé. Le TFTP intégré à macOS ou `dnsmasq` conviennent. Pare-feu désactivé. Non testé de mon côté.
3. Deco débranché, appuie sur reset avec un trombone, rebranche en gardant reset appuyé 10 à 15 secondes, jusqu'à ce que la LED s'éteigne.
4. Ouvre `http://192.168.0.1`, envoie le faux firmware. « Upgrade Failed » est le résultat attendu. Le Deco télécharge alors `initramfs-kernel.bin` et démarre dessus.
5. IP du Mac en DHCP, puis ouvre `http://192.168.1.1` (sans mot de passe). Mets un mot de passe root dans Système > Administration pour pouvoir utiliser SSH.

**Sauvegarde complète sans soudure** (à faire ici, avant l'étape 6, depuis le système en RAM) : la table des partitions du dts couvre toute la flash de 16 Mo (u-boot, firmware, product-info, config, art). Depuis le Mac :
```sh
ssh root@192.168.1.1 'cat /proc/mtd' | tee mtd-liste.txt
for n in 0 1 2 3 4; do ssh root@192.168.1.1 "cat /dev/mtd${n}ro" > mtd$n.bin; done
for n in 0 1 2 3 4; do ssh root@192.168.1.1 "cat /dev/mtd${n}ro" | shasum -a 256; done; shasum -a 256 mtd*.bin
```
Les deux séries de SHA256 doivent être identiques. Vérifie que la somme des tailles fait 16 777 216 octets. Garde les fichiers en deux endroits. Cette sauvegarde est celle du firmware d'origine, `art` comprise.

6. Seulement après la sauvegarde : LuCI > Système > Sauvegarde / Flasher le firmware, choisis le fichier **sysupgrade**, **décoche « Conserver la configuration »**, puis lance. Compte 3 minutes sans couper le courant.

Si le courant est coupé avant l'étape 6, l'appareil retrouve le firmware d'origine : on recommence à l'étape 3.

Risques propres à cette méthode :
- On exécute un fichier binaire tiers. Ne l'utilise qu'après que je l'aie inspecté.
- Notre initramfs contient LuCI et fait 7,5 Mo, plus gros que celui du guide. Je ne sais pas si le chargeur TFTP du Deco l'accepte.
- Le geste exact du bouton reset sur le P9 n'est pas vérifié.

## Flasher (à faire seulement après sauvegarde)

1. Le **sysupgrade** ne sert que si OpenWrt tourne déjà. Depuis le firmware d'origine, il faut le **factory**.
2. Interface web du Deco / firmware d'origine : mise à jour manuelle avec le fichier factory. Les Deco récents demandent parfois une version de firmware d'origine précise : **non vérifié** pour le P9.
3. Premier démarrage : connexion à `192.168.1.1`.
4. Les installations faites avec l'image du fork : sysupgrade normal. Le compatible est resté `tplink,deco-p9-v1v2`, donc `-F` ne devrait pas être nécessaire. **Non vérifié.**
5. Ne coupe jamais le courant pendant l'écriture.

## Sauvegarde avant de flasher (obligatoire)

**Limite importante :** le firmware d'origine du Deco n'a pas de shell. Pour lire les mtd *avant* de flasher, il y a deux possibilités :

### Option A (recommandée) : lecture directe de la flash avec une pince SOIC8
Avec un programmateur CH341A (3,3 V, vérifier l'adaptateur) et `flashrom` :
```sh
flashrom -p ch341a_spi -r deco_p9_full_1.bin
flashrom -p ch341a_spi -r deco_p9_full_2.bin
flashrom -p ch341a_spi -r deco_p9_full_3.bin
shasum -a 256 deco_p9_full_*.bin     # les 3 doivent être identiques
```
Le fichier complet contient `art` et `config`. Garde-le sur au moins deux supports.
Attention : appareil débranché de l'alimentation, et ne l'alimente pas pendant que la pince est posée (sauf indication contraire de ton programmateur).

### Option B : sauvegarde depuis OpenWrt, après le premier flash
`art` (0xff0000) et `config` (0xe85000) ne sont pas réécrites par une image safeloader (hypothèse : **non vérifiée**), mais les partitions `firmware`, `support-list` et `soft-version` d'origine le sont. Cette option ne sauve donc pas le firmware d'origine.
```sh
cat /proc/mtd
for p in $(sed -n 's/^\(mtd[0-9]*\):.*/\1/p' /proc/mtd); do dd if=/dev/${p}ro of=/tmp/$p.bin 2>/dev/null; done
# puis copie /tmp/mtd*.bin sur ton ordinateur avec scp
sha256sum /tmp/mtd*.bin
```
Les partitions `art`, `config`, `product-info` sont les plus importantes. **Sans la partition `art`, le Wi-Fi n'est plus calibré** et la MAC est perdue.

## Plan de récupération

1. **Ne pas paniquer** : le U-Boot (0x000000–0x080000) n'est pas touché par l'image.
2. Accès série (UART) 3,3 V sur la carte, 115200 bauds : emplacement des pastilles **non vérifié** pour le P9. Il permet de voir le démarrage et d'accéder à U-Boot.
3. Récupération TFTP via U-Boot : le M4R en a une, le P9 devrait l'avoir. **Non vérifié.** N'utilise pas les .bin précompilés du fork pour ça : prends ton propre fichier factory.
4. Dernier recours : réécrire la sauvegarde complète avec `flashrom -p ch341a_spi -w deco_p9_full_1.bin`.
5. Si `art` est perdue : aucune image ne la remplace. Seule la sauvegarde permet de restaurer le Wi-Fi.

## Journal des essais sur matériel réel (27-28/10/2026)

- **Flash par l'interface web du firmware d'origine (1.3.0) : refusé.** Aucun message d'erreur, mais au redémarrage le Deco était toujours sur le firmware d'origine. Rien n'a été écrit (comportement sans risque). Hypothèse retenue : le firmware d'origine vérifie une signature que notre image n'a pas (voir « Méthode TFTP » ci-dessus pour le détail de la comparaison d'en-têtes).
- **Flash par TFTP avec l'exploit `naf419/tplink_deco_exploits` (fichier `deco_all_webfailsafe_faux_fw_tftp_v2.bin`) : fonctionne.** Le fichier a été vérifié avant usage : ses seules chaînes lisibles sont les commandes U-Boot `setenv serverip/ipaddr`, `tftpboot` et `bootm`, sans aucune commande d'écriture flash (`erase`, `cp.b`, `mtd`, `nand`). Le dépôt liste explicitement le Deco P9 v1.80 et v2.0 pour cette méthode.
- **Sauvegarde complète des 5 partitions (`mtd0` à `mtd4`, dont `art` et `config`) faite depuis le système démarré en RAM, avant toute écriture.** Les SHA256 ont été vérifiés deux fois (lecture directe + copie locale) avant de continuer. C'est la seule méthode qui donne une sauvegarde complète du firmware d'origine sans soudure.
- **Sysupgrade (sans conserver la configuration) : a tenu.** Redémarrage confirmé sur OpenWrt après coupure du courant. L'installation est permanente.
- **Gestionnaire de paquets : `apk`, pas `opkg`**, sur cette version de main (confirmé par le manifeste du build et par l'appareil).
- **Wi-Fi client (mode station) vers une Livebox 4 : fonctionne.**

## Extension Wi-Fi d'une Livebox 4 avec relayd

But : prolonger le Wi-Fi de la Livebox via le Deco, même sous-réseau, sans mesh (la Livebox ne parle pas les protocoles mesh d'OpenWrt) et sans double NAT.

### Ce qui ne fonctionnait pas, et pourquoi

Premier essai : interface `wwan` en client vers la Livebox (`192.168.0.1/24`), interface `relay_bridge` (protocole « Relay bridge », paquet `relayd`) regroupant `lan` et `wwan`, mais `lan` restée à son adresse d'usine OpenWrt `192.168.1.1/24` avec son propre serveur DHCP actif.

Résultat : `relay_bridge` restait sans adresse IP (« Carrier: Absent »). `relayd` relie deux segments au niveau 2 et fait transiter les requêtes DHCP entre eux, mais ne change rien aux adresses IP : il faut que les deux côtés soient le même sous-réseau. Comme le serveur DHCP du Deco, toujours actif sur `lan`, répondait immédiatement aux appareils connectés en `192.168.1.x`, aucune requête n'avait de raison de passer par le relais vers la Livebox (en `192.168.0.0/24`). `relay_bridge` n'avait donc jamais l'occasion de s'y rattacher.

### Ce qui a corrigé le problème

1. Interface `lan` passée en IP statique dans le sous-réseau de la Livebox (`192.168.0.0/24`), hors de sa plage DHCP, avec passerelle et DNS pointant sur la Livebox (`192.168.0.1`).
2. Serveur DHCP désactivé sur `lan` (case « Ignorer cette interface »), pour que seule la Livebox distribue des adresses.
3. `wwan` reste en protocole « Non géré » (`none`), sans IP propre : c'est `relayd`, via `relay_bridge`, qui gère l'adresse pour l'ensemble du pont.

Après ce changement : `relay_bridge` a obtenu une adresse, et les appareils connectés au Deco (Ethernet ou Wi-Fi local sur l'autre bande) reçoivent une adresse `192.168.0.x` distribuée par la Livebox.

**Non vérifié** : la stabilité dans la durée du pont relais, le roaming entre la Livebox et le Deco quand un appareil se déplace (pas de 802.11r/k configuré), et le comportement si la Livebox change de canal ou redémarre.

## Second Deco en bridge simple, par le CPL (28/10/2026)

Deux Deco P9 sous OpenWrt, reliés par le CPL (même NMK, voir « CPL »). Le premier (`192.168.0.2`) est un relais Wi-Fi vers la Livebox (`relayd`). Le second (`192.168.0.6`) est un point d'accès en **bridge simple** : il n'a plus de DHCP ni de pare-feu et laisse tout à la Livebox.

Configuration du second Deco :
- `network.lan` : `proto static`, `ipaddr 192.168.0.6`, `netmask 255.255.255.0`, `gateway` et `dns 192.168.0.1`, sans `ip6assign`.
- Switch : `ports='2 3 5 0t'` (le port 2 est le CPL). Pas de câble vers la Livebox : le CPL est le seul lien montant (sinon boucle réseau).
- DHCP : `dhcp.lan.ignore='1'`, `dhcpv6` et `ra` à `disabled`. `firewall`, `dnsmasq` et `odhcpd` désactivés au démarrage (`/etc/init.d/<service> disable`).
- Wi-Fi : même SSID et même clé que le premier Deco, `country FR`. Canaux différents pour ne pas se gêner : 5 GHz canal 36 et 2,4 GHz canal 11 (le premier est sur 5 GHz canal 112 et 2,4 GHz canal 1).

Vérifié après un redémarrage à froid : adresse et passerelle en place, ping de la Livebox en environ 5 ms à travers le CPL, aucun DHCP local, et un Mac branché en Ethernet sur le port 3 a reçu `192.168.0.60` de la **Livebox**. Le premier Deco voit le second à son MAC (`00:31:92:22:a0:40`).

Pas vérifié : un appareil en Wi-Fi sur le second Deco, la stabilité dans la durée, le roaming entre les deux Deco (non configuré), et l'adresse IP `192.168.0.6` hors de la plage DHCP de la Livebox (j'ai évité `192.168.0.4`, déjà prise par une autre machine du réseau).

### Incident : le redémarrage du réseau par SSH peut figer un Deco

En appliquant cette configuration au second Deco avec `/etc/init.d/network restart` suivi de `wifi reload` (lancés en arrière-plan depuis une session SSH), le Deco a cessé de répondre sur `192.168.1.1` comme sur `192.168.0.6`, et n'est revenu qu'après une coupure d'alimentation (hard restart). L'utilisateur a constaté que le même `network restart` par SSH plante aussi le premier Deco. La cause n'est **pas diagnostiquée** : aucun log n'a été conservé (la RAM est perdue au redémarrage).

À l'inverse, `/etc/init.d/network reload` lancé en SSH a fonctionné sans problème sur les deux Deco pour la seule correction du VLAN (`ports='2 3 5 0t'`) ; ce n'est pas la même opération qu'un `restart` avec changement d'adresse IP et de Wi-Fi.

Précautions pour la suite :
- Éviter `network restart` à distance ; préférer `reload`, ou redémarrer le Deco avec `reboot` après avoir enregistré la configuration (`uci commit`).
- Armer un retour arrière **avant** de changer l'adresse IP ou le Wi-Fi, et vérifier qu'il tourne. Ici, un minuteur en RAM (`sleep 600` puis restauration de `/etc/config`) n'a pas permis de retrouver le Deco ; il ne protège pas d'un figement complet ni d'un redémarrage.
- Sauvegarder `/etc/config` avant (fait ici dans `/root/backup-avant-bridge/`, sur la flash).
- Un script avec `set -e` s'est arrêté en cours de route à cause d'un `uci -q delete` d'une option absente (code de retour 1) : ne pas combiner `set -e` et `uci delete`.
- L'accès SSH par une nouvelle adresse IP demande d'accepter la clé de l'hôte (`ssh -o StrictHostKeyChecking=accept-new`) ; un script en `BatchMode` échoue sinon.

## Débits mesurés avec deux Deco en relais + bridge (28/10/2026)

Montage : Livebox, puis Deco 1 en relais Wi-Fi (`relayd`, 5 GHz canal 112, signal −45 dBm, 650 Mbit/s négocié), puis le CPL, puis Deco 2 en bridge. Les deux Deco sont sur la même multiprise (avec une ampoule LED et un chargeur de MacBook).

| Chemin | Débit (Mbit/s, envoi / réception) |
|---|---|
| iPhone sur le Wi-Fi de la Livebox | ~270 / ~270 |
| iPhone sur le Wi-Fi du Deco 1 | 123 / 89 |
| iPhone sur le Wi-Fi du Deco 2 | ~40 / ~40 |
| iperf3 Deco 1 vers un Mac derrière la Livebox (Wi-Fi client seul) | 208 / 196 |
| iperf3 CPL seul, Deco 2 vers Deco 1 | 174 (92 retransmissions) / 200 (26) |
| iperf3 Deco 2 vers le même Mac (CPL + `relayd` + Wi-Fi client du Deco 1) | 79 (71 retransmissions) / 141 (206) |

Mesures de l'iPhone : speed test, à des endroits proches mais pas identiques. Mesures iperf3 : 8 à 10 s, TCP, un seul flux, `iperf3` installé en RAM (`apk fetch --recursive iperf3` puis `apk extract --destination /tmp/ip`).

Constats :
- Le CPL n'est pas le goulot : 174 à 200 Mbit/s entre les deux Deco malgré l'ampoule LED et le chargeur.
- Le Wi-Fi du Deco 1 vers la Livebox est bon (208 / 196).
- Le trajet complet du Deco 2 (CPL, `relayd`, Wi-Fi) tombe à 79 Mbit/s en envoi alors que chaque tronçon fait 175 à 210. Pendant un transfert CPL d'environ 200 Mbit/s, le processeur du Deco 1 est à 0 % d'inactivité (84 % de softirq) : le Deco 1 est le suspect principal. `relayd` lui-même n'a pas été profilé.
- Sur le Deco 1, le Wi-Fi client et le point d'accès partagent la même radio 5 GHz (canal 112) : le trafic de ses clients passe deux fois par cette radio, ce qui explique en grande partie 123 / 89.
- Le Deco 2 perd encore environ la moitié (de 79 à 141 mesurés derrière lui à environ 40 avec l'iPhone) : cause non isolée (processeur du Deco 2, iPhone, retransmissions).
- Amélioration non testée : relier le Deco 1 à la Livebox par Ethernet ou CPL pour supprimer `relayd` (voir le journal ci-dessus).

## Roaming Wi-Fi entre les deux Deco (28/10/2026)

Les deux Deco diffusent le même SSID (`Trauma_EXT`, même clé) sur chaque bande. Pour que les clients passent de l'un à l'autre plus vite, 802.11k et 802.11r (Fast BSS Transition) sont activés sur les interfaces point d'accès des deux Deco, sur les deux radios (`wireless.default_radio0` et `default_radio1`) :

```sh
uci set wireless.default_radio0.ieee80211k='1'
uci set wireless.default_radio0.ieee80211r='1'
uci set wireless.default_radio0.mobility_domain='4f57'     # identique sur les deux Deco
uci set wireless.default_radio0.ft_over_ds='0'
uci set wireless.default_radio0.ft_psk_generate_local='1'  # pas de r0kh/r1kh à configurer
uci set wireless.default_radio0.nasid='deco1-radio0'       # unique par radio et par Deco
uci commit wireless && wifi reload
```
(même chose sur `default_radio1`, et `deco2-radioN` sur le second Deco.) Sauvegarde de l'ancien fichier sur chaque Deco : `/root/wireless.avant-roaming`.

Vérifié dans la configuration hostapd générée des deux Deco : `wpa_key_mgmt=WPA-PSK FT-PSK`, `mobility_domain=4f57`, `ft_psk_generate_local=1`, `rrm_neighbor_report=1`, et le Wi-Fi des deux Deco `ENABLED` après le rechargement. Canaux différents pour éviter les interférences : Deco 1 en 5 GHz canal 112 et 2,4 GHz canal 1, Deco 2 en 5 GHz canal 36 et 2,4 GHz canal 11. Le SSID du second Deco avait été renommé `Trauma_EXT_D2` pour des tests de débit, puis remis à `Trauma_EXT`.

Limites :
- **802.11v n'est pas disponible** : `wpad-basic-mbedtls` (hostapd 2.12) rejette l'option `bss_transition` (`unknown configuration item`). Hostapd a alors refusé toute la configuration et le Wi-Fi du second Deco est resté éteint environ une minute, jusqu'à la suppression de l'option. Il n'y a donc pas de demande de changement de point d'accès envoyée aux clients (BSS Transition). Le paquet `wpad` complet pourrait le permettre : non essayé.
- **Pas de partage de voisinage** entre les deux Deco (pas de `usteer` ni de `dawn`) : chaque Deco n'annonce que lui-même dans ses rapports 802.11k. Le client décide seul quand changer.
- **Non testé avec un vrai client** : je n'ai pas mesuré un passage d'un Deco à l'autre (ni la durée de coupure). Certains vieux appareils peuvent refuser de se connecter à un SSID en `FT-PSK` ; si cela arrive, retirer `ieee80211r` sur les deux Deco.
- `network restart` n'est pas utilisé : seul `wifi reload` a été lancé (voir « Incident »). Sur le Deco 1, `wifi reload` coupe quelques secondes son Wi-Fi client vers la Livebox, et donc l'accès SSH par ce chemin.

## Incident du premier sysupgrade avec le paquet `plc-bcm` (29/10/2026)

Après un `sysupgrade` avec « conserver la configuration » vers la première image avec CPL, les deux Deco ont cessé de répondre sur leurs adresses. Causes trouvées (vérifiées sur les Deco) :

1. **`relayd` avait disparu du Deco 1.** Il avait été installé à la main après le premier flash, il n'est pas dans l'image, et un `sysupgrade` ne conserve que la configuration (`/etc/config`), pas les paquets ajoutés. La configuration `relay_bridge` restait, sans le programme : le Deco 1 était coupé de la Livebox, donc sans Internet pour réinstaller le paquet. Remède appliqué : copie de l'`.apk` par câble (`cat > /tmp/relayd.apk`) puis `apk add --allow-untrusted --no-network /tmp/relayd.apk`. Correctif durable : `relayd` et `luci-proto-relay` sont maintenant dans le `.config` de `build-image.sh` (et contrôlés par `check-image.sh`). Dans cette version, `relayd` n'a pas de gestionnaire netifd séparé : c'est son script d'init qui lit les interfaces `proto relay`.
2. **Les deux Deco n'avaient plus la même NMK.** Le service `plc` n'avait été installé à la main que sur le Deco 1 : sa config privée a été conservée. Le Deco 2 n'avait pas ce fichier, il a reçu celui du paquet (NMK HomePlug AV publique) : deux réseaux CPL différents, le Deco 2 était isolé. Remède : même NMK dans `/etc/config/plc` des deux Deco. Test de diagnostic : écrire temporairement la clé par défaut sur la puce du Deco 1 a fait réapparaître le Deco 2.
3. **Les liens `/etc/rc.d` ne sont pas conservés** : `firewall`, `dnsmasq` et `odhcpd` ont été réactivés par l'image sur les deux Deco (le Deco 2 les avait désactivés). Sans effet visible ici (DHCP ignoré), à re-désactiver si voulu.

Après un `sysupgrade` : vérifier `which relayd`, `uci show plc` (même NMK sur tous les Deco), `ls /etc/rc.d`.

**Piège du Mac branché en Ethernet sur le Deco pour le dépanner** : si le Wi-Fi du Mac et l'Ethernet sont dans le même sous-réseau (`192.168.0.0/24`), macOS envoie tout par le Wi-Fi et `ping 192.168.0.2` échoue alors que le câble fonctionne. Forcer l'interface : `ping -b en5 192.168.0.2`, `ssh -o ProxyCommand='nc -b en5 %h %p' root@192.168.0.2`.

### Peut-on se passer de `relayd` ?

Pas avec une liaison Wi-Fi « client » vers la Livebox : une station Wi-Fi standard ne peut émettre que des trames avec sa propre adresse MAC, donc on ne peut pas la mettre dans un pont ; `relayd` est le contournement (pseudo-pont en espace utilisateur). Options :
- **Pont réel via WDS/4addr** (`option wds '1'` sur l'interface client) : exige que la Livebox accepte les trames 4-adresses. Je ne sais pas si la Livebox 4 le fait ; **non testé**.
  Entre **deux Deco sous OpenWrt**, le WDS a été essayé le 29/10/2026 : il fonctionne en pont réel sur le 2,4 GHz (`ath9k`) et sur le 5 GHz (`ath10k-ct`, 196 Mbit/s mesurés, limités par le processeur), sans `relayd`. Le maillage 802.11s fonctionne sur le 2,4 GHz mais échoue sur le 5 GHz (canal DFS 112) pour une cause non établie. Détails et pièges dans `tools/wifi-backhaul-test/README.md`.
- **Maillage 802.11s** : la Livebox ne le parle pas.
- **Routage avec NAT** (double NAT) : écarté (voir plus haut).
- **Ne pas passer par le Wi-Fi pour la liaison montante** : un Deco relié à la Livebox par Ethernet ou CPL est un vrai pont, sans `relayd`. C'est aussi ce qui supprimerait la perte de débit due à la radio partagée et au processeur du Deco 1 (voir les mesures). Recommandé si un Deco peut être placé près de la Livebox ; **non essayé**.

### Construire sur le Mac : non réalisable pour l'instant

Le Mac n'a que 4,8 Go libres sur 460 Go (disque plein à 99 %, pas d'autre volume), alors qu'un build OpenWrt demande environ 30 à 40 Go. Docker et Colima n'ont donc **pas** été installés. Il faudrait libérer au moins 40 Go ou utiliser un disque externe, puis une machine virtuelle Linux (Colima/Docker) avec `build.sh`. Le build se fait pour l'instant sur une machine Linux séparée (`CLAUDE.md`).

## Build avec relayd intégré (patch 0003 à jour) — 29-30/10/2026

Reconstruit (`./build-image.sh`, main à `6b7ea6896a3a83c9ae80d31e8d35d911e032268f`) avec les correctifs qui suivent l'incident ci-dessus : `relayd` et `luci-proto-relay` dans le `.config`, `write_nmk()` qui retente la relecture au lieu d'échouer sur une non-réponse à l'écriture. `check-image.sh` donne `TOUT EST BON`, y compris les deux nouveaux contrôles (`/usr/sbin/relayd`, lien `S*relayd`).

**Un bug du script de vérification a dû être corrigé une seconde fois.** Ma correction du 29/10 (le faux `FAIL` de `strings | grep -q` sous `pipefail`, voir plus bas) n'avait été commitée que sur une branche à moi, jamais fusionnée dans `main` : l'agent de test est reparti de l'ancien `main` et l'a réintroduite sans le savoir en ajoutant les contrôles `relayd`. Réappliquée à l'identique. **Leçon à en tirer : un correctif de `check-image.sh` doit être fusionné dans `main`, pas laissé sur une branche de build isolée, sinon il se reperd à chaque nouvelle branche de travail.**

**Images dans `images/` (remplacent celles du 29/10 sans `relayd`) :**

| Fichier | SHA256 |
|---|---|
| `openwrt-ath79-generic-tplink_deco-p9-v1v2-squashfs-factory.bin` | `82f631b1daccdf60e35db48df7ca9dd41be2c2ddb2c2f0dff268911ffd01f3c1` |
| `openwrt-ath79-generic-tplink_deco-p9-v1v2-squashfs-sysupgrade.bin` | `9552842c8c2833bd33895a8e53ca1b43f2273cd7706f75cfcf18e6b575ab134f` |
| `openwrt-ath79-generic-tplink_deco-p9-v1v2-initramfs-kernel.bin` | `8875c3ea37468d10669b87c11faadb1c73b17602ecee3149d57d7635cf64c3e2` |

Sysupgrade : 7 864 608 octets, marge de 6,3 Mo sous la limite de 13 824 ko (luci, luci-ssl, plc-bcm, relayd et luci-proto-relay inclus).

**Non vérifié :** rien de tout ça n'a tourné sur un vrai Deco. C'est la première image qui contient `relayd` de façon native plutôt qu'installé à la main ; l'incident ci-dessus montre que cette différence a un effet réel sur un sysupgrade, donc à surveiller particulièrement au premier flash de cette version.

## Deco 1 relié à la Livebox par câble (30/10/2026)

Le Deco 1 a quitté la liaison Wi-Fi + `relayd` pour un câble Ethernet vers la Livebox : c'est un simple pont, comme le Deco 2. Script réversible : `tools/uplink-ethernet.sh` (`on`, `off`, `status`).

- `on` désactive (sans supprimer) le client Wi-Fi, `wwan` et `relay_bridge`, arrête `relayd`, fixe la radio 5 GHz sur un canal sans DFS (36), sauvegarde dans `/root/backup-uplink`. **Lancer `on` avant de brancher le câble** : avec le Wi-Fi client et `relayd` encore actifs, le câble créerait deux chemins vers la Livebox (boucle). Non vérifié : ce qui se serait passé dans l'autre ordre.
- Vérifié après bascule : lien du port 5 actif, `relayd` arrêté, pont sans interface Wi-Fi cliente, pas de tempête (processeur 90 % libre, ~11 paquets/s), Livebox à 0,5 ms, Deco 2 joignable par le CPL.
- **Route par défaut manquante** après `network reload` (le noyau n'avait pas réinstallé celle de `lan`, que `netifd` listait) : `ifup lan` la rétablit, ajouté au script. Validé à la main, pas en relançant le script.
- **Caches ARP périmés** : après la bascule, mon Mac gardait l'ancienne adresse MAC du relais (`1e:3b:f3:…`) pour `192.168.0.6` et ne joignait plus le Deco 2 pendant une vingtaine de minutes (le Deco 1 le joignait). D'autres appareils peuvent faire de même ; `sudo arp -d <ip>` le force.
- Le script `/root/uplink-ethernet.sh` du Deco 1 a été vidé par erreur (0 octet) lors d'un renvoi mal rédigé, puis renvoyé à l'identique.
- Latence du CPL (Deco 2 vers Livebox) : toujours irrégulière, 5,5 à 47,5 ms (moyenne 20 ms) ; cause non établie.

**Maillage 802.11s 5 GHz** : avec cette radio libre sur le canal 36, il s'établit (146 / 140 Mbit/s, pont réel). Voir `tools/wifi-backhaul-test/README.md` pour le détail, y compris l'échec précédent sur le canal DFS 112 dont la cause reste ambiguë (canal et rôle de la radio ont changé en même temps).

## Remplacer la Livebox par un Deco P9 (recherche, 30/10/2026)

**Essayé le 30/10/2026 sur la ligne réelle : le Deco a pris la place de la Livebox (adresse publique, Internet, DNS), avec le jeton de la Livebox rejoué ; voir `tools/orange-livebox-replacement/README.md` pour ce qui est vérifié, les défauts connus (confirmation automatique défaillante) et les mesures de débit (plafond d'environ 320 Mbit/s en filaire dû au processeur ; marquage 802.1p à ne pas appliquer à tout le trafic).** Instructions, gabarits de configuration et scripts dans
`tools/orange-livebox-replacement/` (README détaillé là-bas). Résumé :

- Orange authentifie le routeur comme une vraie Livebox (VLAN 832 + options DHCP spécifiques + un jeton
  calculé à partir des identifiants du compte), pas seulement par DHCP simple sur le bon VLAN.
- Le gabarit d'interface WAN et les scripts de génération/renouvellement du jeton viennent d'un projet
  communautaire pour un routeur Turris Omnia (périphérique `8021q` noyau). Adaptés à notre commutateur
  `swconfig` (VLAN créé dans Réseau > Commutateur, pas via un device DSA).
- **Point non résolu** : le marquage de priorité réseau (802.1p/PCP) qu'Orange semble exiger sur les
  trames DHCP pour ne pas brider l'émission à ~6 Mbit/s. Aucune méthode confirmée pour `swconfig` sur la
  puce `ar8327` de ce P9 ; à tester sans ce réglage d'abord, puis mesurer.
- La chaîne `userclass` (option 77) dépend du modèle de Livebox ; celle fournie correspond à une
  Livebox 4.
- Pas de décodeur TV Orange ni de téléphone fixe à reproduire dans ce foyer : non traité.
- Aucune vraie donnée (MAC de la Livebox, identifiants Orange) n'est dans les fichiers du dépôt : à
  remplacer sur le Deco lui-même, jamais à committer.

Le Deco 1 a déjà un câble Ethernet vers la Livebox actuelle (voir plus haut, « Deco 1 relié à la Livebox
par câble ») : c'est ce même port qui recevrait l'ONT si l'essai a lieu.

## Liste de ce qui n'est PAS vérifié

- Que ton appareil a un `special_id` présent dans la liste (le firmware d'origine ne contient que ces valeurs).
- Confirmé : le firmware d'origine 1.3.0 refuse l'image factory sans erreur visible (voir journal). La méthode TFTP contourne ce blocage.
- Le fonctionnement du CPL de bout en bout (le port 2 et le protocole Broadcom sont vérifiés, voir la section CPL ; l'appairage entre deux Deco ne l'est pas).
- Les LED : seule la LED d'alimentation et la LED 5 GHz du M4R sont définies. La LED rouge 2,4 GHz (GPIO 1) n'est pas reprise.
- Le sysupgrade depuis une installation faite avec le fork sans `-F`.
- Le Wi-Fi 2,4 GHz et 5 GHz avec ath10k-ct sur le QCA9886.
- L'accès UART et la récupération TFTP.
- Le sysupgrade via l'interface web du firmware d'origine (contourné par la méthode TFTP, jamais testé directement).
- La stabilité du pont relayd dans la durée, et le roaming entre la Livebox et le Deco.
- La cause du figement d'un Deco au `network restart` par SSH, et le Wi-Fi du second Deco en bridge (voir « Second Deco en bridge simple »).
- Le roaming 802.11k/r entre les deux Deco avec un vrai client (durée de coupure, appareils incompatibles FT-PSK), et 802.11v (indisponible avec `wpad-basic`).
- La cause de l'échec du maillage 5 GHz sur le canal DFS 112 (DFS, ou radio portant aussi la liaison vers la Livebox), et la stabilité de tous ces liens dans la durée.
