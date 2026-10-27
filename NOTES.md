# Support OpenWrt pour le TP-Link Deco P9 (sans CPL par défaut)

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

- **Port switch du CPL (groupe b)** : écarté du réglage par défaut. Voir « CPL » plus bas. Tu veux pouvoir l'activer, donc la procédure est documentée.
- **FastPath / shortcut-fe (groupe c)** : écarté. Code lié au noyau 5.4, non maintenu, absent de main, source de bugs. Le fork lui-même l'a supprimé dans « move Deco-P9 to master ».
- **LED `red:wlan2g` sur le GPIO 1** : écartée. Elle est dans le dts du fork mais absente du M4R de main. Je ne peux pas confirmer le GPIO.
- **Modifs de `config-5.4` / `config-5.10`** : écartées, bruit de rebase du fork, sans lien avec l'appareil.
- **Essais de performance** : écartés, hors périmètre.

## Problèmes trouvés dans le fork

- L'entrée safeloader finale du fork a des virgules en trop à la fin de chaque ligne de la liste de support. Je n'ai pas testé si elle compile ; je l'ai corrigée (virgule seulement à la fin). Les valeurs n'ont pas changé.
- Le port switch du CPL est passé de **4** à **2** entre deux commits du fork, sans explication.

## CPL : activer ou désactiver

Par défaut le switch ne met que les ports 3 et 5 dans le LAN. Le port du CPL reste donc isolé (désactivé).

Pour **activer** (à adapter après avoir regardé `uci show network | grep -B1 -A4 switch_vlan`) :
```sh
uci add_list network.@switch_vlan[0].ports='2'   # port 2 = dernière valeur du fork
uci commit network && /etc/init.d/network restart
```
Pour **désactiver** :
```sh
uci del_list network.@switch_vlan[0].ports='2'
uci commit network && /etc/init.d/network restart
```
LuCI permet aussi de le faire : Réseau > Commutateur.

**Non vérifié** :
- Le numéro de port (2 ou 4). Test sans risque : brancher un câble sur chaque port et lire `swconfig dev switch0 show`.
- Si la puce CPL a besoin d'autre chose (GPIO de reset, alimentation, firmware propre). Le fork ne gère rien d'autre que le port.
- Ta puce CPL est défectueuse, donc je n'ai pas fait du CPL actif la valeur par défaut.

## Construire

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

## Liste de ce qui n'est PAS vérifié

- Que ton appareil a un `special_id` présent dans la liste (le firmware d'origine ne contient que ces valeurs).
- Que le firmware d'origine accepte l'image factory.
- Que l'image démarre (le build passe, mais aucun test matériel).
- Le numéro de port du CPL, et le fonctionnement du CPL.
- Les LED : seule la LED d'alimentation et la LED 5 GHz du M4R sont définies. La LED rouge 2,4 GHz (GPIO 1) n'est pas reprise.
- Le sysupgrade depuis une installation faite avec le fork sans `-F`.
- Le Wi-Fi 2,4 GHz et 5 GHz avec ath10k-ct sur le QCA9886.
- L'accès UART et la récupération TFTP.
