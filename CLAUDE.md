# Instructions pour l'agent de build (Deco P9, paquet plc-bcm)

Ce dépôt contient trois patchs `git am` pour OpenWrt (base `6b7ea6896a3a83c9ae80d31e8d35d911e032268f`) :
`0001` outil de signature, `0002` support du TP-Link Deco P9, `0003` paquet `plc-bcm` (CPL) et port 2 dans le LAN.
**Ta mission : construire le firmware avec les trois patchs, le vérifier, et rapporter honnêtement.**
Lis d'abord `docs/status.md` et `docs/powerline.md` (CPL et paquet `plc-bcm`).

## Ce qui est vérifié, ce qui ne l'est pas

- Vérifié : les trois patchs s'appliquent sans conflit sur la base. Le contenu du paquet (`package/utils/plc-bcm/files/`) a été testé sur de vrais Deco (lecture et écriture de la NMK, correction au démarrage) ; mais installé à la main, pas depuis une image.
- **Jamais exécuté** : le `Makefile` de `plc-bcm`, la sélection par `DEVICE_PACKAGES`, l'image complète. Si quelque chose casse, c'est probablement là. Tu es la première exécution.
- Le dépôt n'a aucun accès au matériel. **Tu ne peux pas flasher** et tu ne dois pas prétendre que le firmware « fonctionne » : il est seulement construit et vérifié statiquement. Le test réel est fait par l'utilisateur sur ses Deco.

## Construire

```sh
./build-image.sh        # clone OpenWrt, applique les patchs, configure, compile, lance check-image.sh
```
Machine Linux avec la toolchain OpenWrt (paquets listés dans `docs/build.md`). Variables : `WORK` (dossier de travail), `PUBLISH=1` (copie aussi dans `images/` et régénère `SHA256SUMS`, seulement après vérification). Le premier build est long. Le résultat est copié dans `out/` (ignoré par git).

`check-image.sh` vérifie : paquet construit, images présentes, taille du sysupgrade ≤ 13824k, `product_name:P9`, manifeste (plc-bcm, ucode-mod-socket, -uci, -fs, relayd, luci-proto-relay), contenu du rootfs (`/usr/sbin/plc-nmk`, `/etc/init.d/plc`, lien `/etc/rc.d/S99plc`, `/usr/sbin/relayd` et son lien `S*relayd`, `/etc/config/plc` avec la NMK par défaut, modules `ucode`), et `02_network` avec le port 2. Il n'écrit rien.

Fais aussi les contrôles manuels de `docs/build.md` (« Verify the image ») : comparaison d'en-têtes avec une image M4R officielle, magic `hsqs`.

## Points de rupture probables (à regarder en premier si ça échoue)

1. **`/etc/rc.d/S99plc` absent** : en principe impossible, car `default_postinst` (injecté automatiquement par `include/package-pack.mk`, défini dans `package/base-files/files/lib/functions.sh`) active chaque script de `/etc/init.d` du paquet à la construction de l'image. Si le lien manque, c'est que `/etc/init.d/plc` n'est pas dans la liste de fichiers du paquet ou que son en-tête `#!/bin/sh /etc/rc.common` / `START=99` est cassé : regarder l'étape `install` du `Makefile`.
2. **Erreur du `Makefile`** de `plc-bcm` (suivi de `package/network/config/gre/Makefile`) : `PKGARCH:=all`, `conffiles`, `INSTALL_CONF`.
3. **Module `ucode` absent de l'image** : `check-image.sh` signale `socket.so`, `uci.so` ou `fs.so` manquant. Les dépendances sont dans le `Makefile`.
4. **Image trop grande** (limite 13824k) : `luci-ssl` pèse ; le réduire seulement avec l'accord de l'utilisateur.
5. **Feeds** : `make download` ou `feeds update` peuvent échouer sans réseau.

## Si tu dois corriger le paquet

Le patch `0003` est la source de vérité pour l'image. Dans le dossier de travail (`$WORK`, commit local `deco-p9`) :
1. Corrige les fichiers sous `package/utils/plc-bcm/` (ou `target/linux/ath79/...`).
2. `git commit --amend` (le dernier commit est le patch 0003).
3. Régénère le patch dans le dépôt : supprime l'ancien `patches/0003-…`, puis `git format-patch -1 --start-number 3 -o <dépôt>/patches/`.
4. Vérifie sur une base neuve que `git am patches/*.patch` redonne le même arbre (`git rev-parse HEAD^{tree}`).
5. Si le script de l'outil change, mets aussi à jour `tools/plc.uc` (copie de `files/plc-nmk.uc`) et `tools/plc-service/`.
Ne contourne jamais une erreur en modifiant `check-image.sh` pour qu'il passe.

## Règles

- **Pas de secret** : aucune NMK privée n'est dans le dépôt, n'en invente pas et n'en écris pas. La NMK dans `/etc/config/plc` est la valeur publique HomePlug AV (mot de passe « HomePlugAV ») ; c'est voulu et documenté.
- Travaille sur une branche (`git switch -c build-AAAA-MM-JJ`). **Ne pousse pas sur `main`** et ne pousse nulle part sans accord. Ne réécris pas l'historique.
- Commits en anglais, message qui dit ce qui a été fait ET ce qui n'a pas été vérifié. N'ajoute les binaires à `images/` (PUBLISH=1) que si `check-image.sh` passe entièrement ; sinon dis-le.
- Rapporte les échecs tels quels (sortie des erreurs), sans les minimiser.

## Ce que tu dois rapporter à l'utilisateur

1. Le résultat de `check-image.sh` (copie intégrale) et la taille des images.
2. Le `sha256` des fichiers de `out/` et le commit OpenWrt utilisé.
3. Ce que tu as corrigé (et le nouveau patch 0003 s'il a changé), ce qui reste cassé.
4. Les vérifications **à faire sur le matériel** (tu ne peux pas les faire) :
   - flash par la méthode TFTP de `docs/install.md` ;
   - sur le Deco : `ls /etc/rc.d | grep plc`, `logread | grep plc:` (attendu : `NMK écrite et relue` ou `NMK déjà à jour`), `uci show plc`, `swconfig dev switch0 vlan 1 show` (port 2 présent sans réglage manuel) ;
   - deux Deco neufs : ping de l'un à l'autre par le CPL ;
   - **changer la NMK par défaut** : `uci set plc.main.nmk='<32 hex>'; uci commit plc; /etc/init.d/plc restart`.
