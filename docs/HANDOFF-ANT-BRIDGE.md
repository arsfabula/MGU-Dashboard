# Handover — pont BLE Sigma → ANT+ *Bicycle Power* émis par Connect IQ

**À lire en premier si tu repars sans contexte.** Ce document s'adresse à la même IA, dans une
session neuve. Il ne suppose rien de la conversation précédente : chaque affirmation porte sa
source (fichier, offset, ligne, log). Il remplace le fil de discussion, pas le carnet de banc.

Date des mesures : 2026‑11‑26. Matériel de validation : **epix Pro 51 mm** (pièce `006-B4314-00`,
fw 28.08, id produit CIQ **`epix2pro51mm`**, produit FIT **4314**) et **Edge Explore**
(`006-B3011-00`, fw 5.40, CIQ 6.0.4, id produit **`edgeexplore`**). SDK Connect IQ
**`connectiq-sdk-lin-9.3.0-2026-10-20-95888f262`**. Prochain poste : **Windows, avec le
simulateur qui fonctionne** (section 8).

**Décision de conception actée** : le projet émettra **deux profils ANT+** — *Bicycle Power*
(device type 11) pour la puissance du cycliste et la cadence, *LEV* (device type 20) pour la
vitesse, l'assistance, la batterie et l'autonomie. Le détail normatif des deux (configuration de
canal, pages obligatoires, motifs d'entrelacement, mises en page octet par octet, ce que LEV ne
peut **pas** transporter) et la correspondance ANT+ → FIT observée sur un appareil sont dans
**`docs/ANT-PROFILES.md`**. Ce handover ne garde que la recette et l'état.

---

## 1. Le but, et où on en est

**But produit** : la puissance et la cadence de l'eBike (reçues en BLE via le service
propriétaire Sigma `0000fd6d-…`, décodées par `source/Sigma.mc`) doivent entrer dans le
**pipeline natif** de la montre Garmin, pour que FTP, zones de puissance, records et Training
Load fonctionnent. Un *data field* peut afficher des nombres ; il ne peut pas, seul, créer un
capteur.

**État : atteint, mesuré.** Un profil ANT+ *Bicycle Power* (`deviceType 11`) **synthétisé par
Connect IQ est appairé par l'epix Pro comme capteur natif**, et l'activité enregistrée par la
montre contient `record.power` et `record.cadence` avec un `device_info` de source `antplus`.
La preuve est un fichier : `ebike-sandbox/t1-bikepower/logs/25205307891_ACTIVITY.fit`
(section 3). Ce qui restait bloqué depuis la v0.0.11 du banc était la **clé de réseau** :
la recette est la section 2.

Le travail qui reste est du **transport** : prendre la configuration gagnante du banc et la
faire vivre dans `ebike-df` avec de vraies valeurs vélo (section 6), puis la revérifier avec le
même protocole FIT (section 7).

---

## 2. La recette qui marche (recopie-la telle quelle)

Émetteur = **canal maître** sur un **réseau `NETWORK_PRIVATE`** auquel on a **posé la clé ANT+
en 64 et 128 bits** :

| réglage | valeur | source |
|---|---|---|
| type de canal | `Ant.CHANNEL_TYPE_TX_NOT_RX` (0x10) | `t1-bikepower/source/AntBpTest.mc:539` |
| réseau | `Ant.NETWORK_PRIVATE` (index 2) | log `v0.0.14-BPTXEDPR.TXT:7` (`net 2 PRIVATE`) |
| clé 64 bits | `B9 A5 21 FB BD 72 C3 45` (clé ANT+) | `AntBp.NETWORK_KEY` |
| clé 128 bits | `B9 A5 21 FB BD 72 C3 45` **+ 8 octets à zéro** | log `:7` (`key128 [185,…,69,0×8]`) |
| `deviceNumber` (ANT-id) | **252** | log `:23` (`OPEN id 252`) |
| `deviceType` | **11** (*Bicycle Power*) | `AntBp.DEVICE_TYPE` |
| `transmissionType` | 0 — **écart à la norme, mesuré sans conséquence** : Table 5‑2 du profil demande à un maître `MSN = 0` **et `LSN = 5`**, donc **0x05**. Le banc a émis 0 et l'epix s'est appairé quand même (`ant_transmission_type` n'est d'ailleurs pas enregistré dans le `.FIT`). Une variante à 0x05 n'a pas été jouée | `AntBp.TRANSMISSION_TYPE = 0` (`AntBpTest.mc:44`) ; exigence : `docs/ant/bicycle-power-5.1.txt` Table 5‑2 |
| `messagePeriod` | **8182** ticks (= 8182/32768 s ≈ 4 Hz) | `AntBp.MESSAGE_PERIOD` |
| `radioFrequency` | **57** | `AntBp.RF_CHANNEL` |
| trame | **8 octets** de charge utile | `AntBp.PAYLOAD_LENGTH` |
| pages émises | 0x10 (Table 8‑1) + 0x50 + 0x51 en rotation | `AntBp.SEND_COMMON_PAGES` |

Pourquoi le réseau privé : la doc du SDK dit mot à mot « **Master Channels are not allowed on
the ANT+ Network** » et « **Both 64 and 128 bit keys are required** » pour un réseau privé
(`$SDK/doc/Toybox/Ant/ChannelAssignment.html`). Sur `NETWORK_PUBLIC` et `NETWORK_PLUS`, la même
configuration n'a jamais été découverte par la montre.

Pièges d'écriture déjà payés à ta place :

- un ANT-id tient sur **un octet** : ids déjà employés par le banc — 250 (public), 251 (PLUS),
  **252 (privé, celui qui marche)**. Choisis-en un, documente-le.
- la charge utile ANT fait **8 octets**, pas 9 (une trame à 9 octets a été refusée en v0.0.7).
- `Ant.DeviceConfig` **se construit** : `new Ant.DeviceConfig(config)`. Passer le dictionnaire
  directement à `setDeviceConfig()` est une erreur de compilation (vérifié avec SDK 9.3.0 sur
  `edgeexplore`, dans `t1-bikepower/probe-datafield-ant/`).

Page 0x10 (profil *Bicycle Power* 5.1, Table 8‑1) : octet 0 = 0x10, octet 1 = *update event
count*, octet 3 = cadence, octets 4‑5 = puissance cumulée (u16 LE, en **J**), octets 6‑7 =
puissance instantanée (u16 LE, en W). Pages 0x50/0x51 **requises** par le profil : 0x50 =
révision matérielle (octet 3), fabricant (4‑5), modèle (6‑7) ; 0x51 = révision logiciel
(octet 3), numéro de série u32 (4‑7). Ces valeurs sont **recopiées telles quelles** dans le
`.FIT` de la montre (section 3) — c'est le moyen le plus sûr de vérifier que c'est bien *ton*
émetteur qui a été appairé.

---

## 3. La preuve (à citer, ne pas redémontrer)

`ebike-sandbox/t1-bikepower/logs/25205307891_ACTIVITY.fit` — activité enregistrée par l'epix le
2026‑11‑26 13:21:28 UTC, 10 446 o, en‑tête 14 o avec CRC, profil FIT **21198**, décodée en
entier : « 36 définitions, 113 messages normaux, corps entier lu »
(`logs/v0.0.14-epix-activity-fit-decode.txt`).

**`device_info` à `@0x0cee`** (coupe octet par octet : `logs/v0.0.14-epix-fit-device-info-cut.txt`) :

| champ FIT (n°) | octets | valeur | provenance |
|---|---|---|---|
| `source_type` (25) | `01` | **antplus** | le tube d'entrée est ANT+, pas Connect IQ interne |
| `ant_network` (22) | `01` | **antplus** | réseau ANT+ (notre réseau privé + clé ANT+) |
| `device_type` (1) | `0b` | **11** | notre `deviceType` |
| `serial_number` (3) | `fc 00 00 00` | **252** | notre ANT-id (posé aussi en n° de série page 0x51) |
| `product` (4) | `31 54` | **0x5431** | `AntBp.MODEL_NUMBER` (page 0x50, octets 6‑7) |
| `software_version` (5) | `6e 00` | 110 → **1.1** | `AntBp.SW_REVISION = 11` (page 0x51, octet 3) |
| `hardware_version` (6) | `01` | **1** | `AntBp.HW_REVISION` (page 0x50, octet 3) |
| `manufacturer` (2) | `01 00` | 1 | `AntBp.MANUFACTURER_ID` (réserve, pas une revendication) |
| `ant_device_number` (21) | `00 00` | *non renseigné* (`uint16z` : 0 = invalide) | la montre met le numéro dans `serial_number`, pas là |
| `ant_transmission_type` (20) | `00` | *non renseigné* (`uint8z`) | notre type de transmission n'est pas stocké |

**Cinq valeurs à nous** (252, 0x5431, 1.1, 1, 11) revenues par la radio et rangées dans les
champs d'un capteur **appairé** : le pipeline est le natif.

**Les points, pas seulement les totaux** : 24 messages `record` sur 23 s ; `power` (champ 7)
présent 24/24, 140 → 236 W ; `cadence` (champ 4) + `fractional_cadence` (53) présents 24/24,
66 → 98 rpm. `session`/`lap` : `avg_power` 190, `max_power` 236, `avg_cadence` 82,
`max_cadence` 98, `sport` 2 = `cycling`, `sub_sport` 47 = `e_bike_mountain`,
`sport_profile_name` `eVTT`.

**Contrôle de cohérence** : les valeurs suivaient la rampe synthétique du banc
(+4,00 W/s, +1,333 rpm/s, `AntBpTest.mc:1255-1265`) ; régression sur les records :
**+3,95 W/s** et **+1,33 rpm/s**. Maxima identiques entre records et `session` (236 W, 98 rpm) ;
l'écart de moyenne (195,9 vs 190) vient de la pondération temporelle de `session`, pas d'un
problème. Trois `record` identiques d'affilée = secondes de radio manquées recopiées par la
montre, pas réinventées : les écarts d'`accumulated_power` valent `156, 0, 0, 492 (=3×164), …`.
Les trois premiers records (140, 222, 223 puis retour à 156) sont un artefact de démarrage
d'appairage, sans effet sur les maxima.

**Ce que le même `.FIT` dit du projet `ebike-df`** (utile, et contre-intuitif) : les colonnes
*developer* des records (`Cyclist Power` 0, `Cadence` 1, `Assistance` 2, `Battery` 3,
`Range` 4, `Motor Power` 10, + moyennes 5‑9) sont **exactement** le jeu déclaré par
`ebikedf-fit_contributions.json` et `source/EbikeFitContributor.mc`. Le fichier les attribue à
`application_id 4e184d99-01fc-4d09-bb44-7cf91195dd13`, `application_version 11`
(`developer_data_id @0x00e1`) — pas l'id du `manifest.xml` publié
(`5E8597AA-69D9-11EA-BC55-0242AC130003`) : la version installée sur la montre a été construite
avec un autre identifiant. Leurs valeurs sont **toutes à zéro, 24/24** : le data field du
projet écrivait bien ses colonnes pendant l'essai, ce qui manquait c'était la donnée BLE. Donc
l'ANT+ ne *remplace* pas le data field : avec les deux, la même activité aurait les champs
natifs **et** les colonnes moteur/assistance/batterie alimentées par le BLE.

---

## 4. Ce qui est mesuré faux — ne pas refaire ces pistes

| impasse | preuve |
|---|---|
| Émettre sur `NETWORK_PUBLIC` avec la clé ANT+ demandée | `v0.0.14-BPTXEDGK.TXT` : 31+ trames parties, `f0`, pages 0x50/0x51 dans l'air, 0x46 *Set Network Key* acquitté (`k1`) → **la montre ne trouve rien** |
| Émettre sur `NETWORK_PLUS` comme maître | `v0.0.14-BPTXEDPK.TXT:72` : `tx 0 f91` = 0 trame, un refus par tick ; `sendBroadcast` lève `UnexpectedTypeException: … given null` à `AntBpTest.mc:664` ; `close()` lève aussi. Cause interne non établie, non bloquante |
| Croire `getDeviceConfig()` sur les clés | il renvoie `key64 null` **aussi sur la variante qui fonctionne** (`v0.0.14-BPTXEDPR.TXT:8`) : indicateur à jeter |
| Croire l'acquittement 0x46 | `k1` (acquitté) et non découvert d'un côté, `k0` (jamais envoyé) et appairé de l'autre : **ni nécessaire ni suffisant** |
| Compter sur `Sensor.SensorDelegate` / une API d'injection | `grep setPower|setCadence` dans le SDK 9.3.0 = 0 occurrence ; `Sensor`/`AntPlus` en lecture seule ; `SensorLogging` = accéléro/gyro/magnéto. Aucun essai nécessaire |
| Un *data field* qui serait périphérique / GATT server | non : c'est la contrainte initiale, elle tient |
| Chercher pendant que l'émetteur est en second plan | un Garmin ferme tous les canaux d'une app qui n'enregistre pas d'activité ; **une seule app à la fois** par appareil ; l'émetteur doit rester au premier plan |
| L'Edge comme récepteur de capteurs de puissance | limite commerciale de la gamme : l'Edge ne voit pas les profils *Power*. C'est pourquoi l'Edge était l'émetteur et la montre la juge |

Deux points jamais élucidés, sans effet sur la suite : `tx.edgx` (v0.0.13) n'a jamais démarré
(`LOGS/BPTXEDGX.TXT` à 0 octet, aucune entrée `CIQ_LOG.YML`) ; la cause interne du `null` de
`sendBroadcast` sur PLUS.

---

## 5. Questions ouvertes pour la suite (la plus importante d'abord)

1. **Sur quel appareil tourne le porteur ANT+ ?** Le banc a prouvé *Edge → montre*. Dans le
   produit, c'est la **montre** qui tient le lien BLE avec le vélo, donc elle devrait être
   l'émetteur ANT+ vers elle‑même. **Non testé.** Une montre peut-elle être maître ANT+ *pendant
   qu'elle enregistre une activité* et s'appairer elle-même ? C'est la première question à
   trancher, avant tout refactor. Le banc miroir était prévu pour ça et n'a pas été joué.
   Deux sous-questions, séparées : (a) un appui `Application.AppBase` d'un *data field* peut-il
   ouvrir un canal maître ; (b) un appareil peut-il découvrir son propre émission.
2. **La voie « data field » compile** (mesuré aujourd'hui, pas joué) :
   `t1-bikepower/probe-datafield-ant/` — manifest `type="datafield"`, entrée
   `Application.AppBase`, permission `Ant`, et dans `onStart()` : `Ant.ChannelAssignment`,
   `Ant.GenericChannel`, `Ant.DeviceConfig`, `setDeviceConfig`, `open`, `sendBroadcast`.
   `BUILD SUCCESSFUL` pour `edgeexplore` avec le SDK 9.3.0. La doc n'interdit depuis une *data
   field app* que `sendBurst()` et `setBurstListener()` (`Lang.SymbolNotAllowedException`,
   `$SDK/doc/Toybox/Ant/GenericChannel.html`). **Reste à exécuter** : le simulateur Windows
   répond à ça sans radio (section 8).
3. **Que faire quand le BLE Sigma tombe** : continuer d'émettre des trames valides (0 W,
   cadence 0, *update event count* qui continue) ou rendre l'antenne ? Non décidé.
4. **Quel ANT-id publier** (252 est celui du banc ; un id figé dans le produit se heurte à un
   autre émetteur à proximité), et la coexistence avec d'autres profils émis.
5. **Le second profil, *LEV* (`deviceType 20 = 0x14`)** : décidé, pas encore conçu.  Ses
   règles de canal ne sont **pas** celles de *Bicycle Power* (période **8192**, type de
   transmission **0x05**), et il ne porte **ni cadence ni puissance absolue** — seulement un
   ratio `% Assist`, la batterie, l'autonomie, la vitesse.  Tout le détail (pages 1/2/3/4,
   coexistence des deux maîtres, pièges) est dans **`docs/ANT-PROFILES.md`** §3 et §4.  Les
   colonnes `motor_power` (FIT 82) et `battery_soc` (81) étaient **absentes** du `.FIT` testé :
   leur correspondance avec les pages LEV reste à vérifier, pas à supposer.
6. `minSdkVersion` : le banc a tourné avec `minSdkVersion="1.2.0"` sur Edge (CIQ 6.0.4) et la
   montre à 28.08 ; `ebike-df` est à 3.1.0. À vérifier pour la variante qui émet.

---

## 6. La tâche concrète, dans l'ordre

**Étape 0 (le plus tôt possible, sur Windows)** : jouer `t1-bikepower/probe-datafield-ant/`
dans le simulateur. Attendre les lignes affichées : `start`, `channel ok`, `cfg true`,
`open true`, `tx true`. Un `throw …` ou `cfg false` ferme la question 5.2 pour moins de rien.

**Étape 1** : un module `BpBridge` (nom libre) dans `ebike-df/source/`, calqué sur
`BpTxChannel` de `t1-bikepower/source/AntBpTest.mc` (lignes 530‑700 pour l'acquisition et
l'envoi, 1255‑1265 pour le générateur de pages) avec les constantes de la section 2. Les
valeurs viennent du modèle existant : `source/Sigma.mc:15-25` (`TreadlePower` u16 W aux octets
6‑7, `Cadence` u8 à l'octet 9 → `model.setPower(...)`, `model.cadenceRpm`), pas d'une rampe.
Calculer la puissance cumulée en J à partir de la puissance instantanée (intégrale) et faire
monter l'*update event count* à chaque trame.

**Étape 2** : le **second canal**, *LEV* (device type 20, période **8192**, type de transmission
0x05, pages 1/2/3/4) pour la vitesse, l'assistance, la batterie et l'autonomie — décidez d'abord
quelles valeurs du modèle Sigma vont dans quelle page, voir `docs/ANT-PROFILES.md` §3 et §4.
Ne pas unifier les périodes ni les ids des deux canaux.

**Étape 3** : garder un journal sur l'appareil (section 9) et **vérifier avec un `.FIT`**, pas
avec l'écran (section 7).

**Étape 4** : une variable par tourne.  Les constantes de conformité de *Bicycle Power*
(`SPEC_PAGE_10`, `SEND_COMMON_PAGES`, période 8182) sont déjà justes : ne pas les reprendre, et
ne pas les partager avec le canal *LEV* (période 8192, type de transmission 0x05).

---

## 7. Protocole de vérification (le seul qui compte)

Le critère n'est pas « des watts s'affichent dans l'app ». C'est : une activité
**Cycling / e‑Bike / Indoor Bike** enregistrée par la montre contient `record.power` **et**
`record.cadence`, avec un `device_info` dont `source_type` = `antplus` et `serial_number` =
l'ANT-id choisi.

Outils — Python 3, sans dépendance, transférables tels quels :

```sh
python3 tools/fitpeek.py <activité.fit>                 # messages, capteurs déclarés, recoupements
python3 tools/fitpeek.py --records <activité.fit>       # tous les records, offsets @0x…
python3 tools/fitfields.py <activité.fit> <@offset>     # un enregistrement, champ par champ
python3 tools/fit-profile-export.py                     # régénère docs/fit/profile-21.171.json
```

`tools/` et `docs/fit/profile-21.171.json` sont dans `ebike-sandbox/t1-bikepower/`. Le
dictionnaire vient du **profil généré du SDK FIT 21.171** (redistribué par `fitdecode` 0.11.0) :
120 messages, 1 386 champs, 17 types de base, 143 champs avec énumération résolue par nom de
champ. **Règle absolue : aucun numéro de champ récité de mémoire.** Trois tables recopiées
étaient fausses (`record.power` cru champ 5, `record.timestamp` cru champ 0 — le champ 0 est
`position_lat`). Le décodeur est validé sur un fichier qui n'est pas à nous :
`docs/fit/validation-sdk-pitchcounter.txt` (l'exemple `pitch_counter_8_pitches.FIT` du SDK,
21 définitions / 123 messages, lu en entier).

Points de contrôle dans l'ordre : en-tête (le 1ᵉʳ octet **est** la longueur d'en-tête, 12 ou 14 ;
taille du corps aux octets 4‑8 ; magie `.FIT` en 8‑12 ; contrôle
`en-tête + corps + 2 == taille du fichier`, affiché `COHÉRENT`) ; tableau « capteurs déclarés » ;
`recoupement records ↔ session/lap` (les maxima doivent tomber juste) ; horodatages FIT =
secondes UTC depuis 1989‑12‑31.

---

## 8. Copier le banc sur Windows, et ce que le simulateur décide (ou pas)

Le banc n'est **pas un dépôt git** : `ebike-sandbox/` est un dossier de travail. À copier sur
Windows, si tu veux le garder sous la main :

```
ebike-sandbox/t1-bikepower/source/AntBpTest.mc     ← la source de référence, v0.0.14
ebike-sandbox/t1-bikepower/{manifest.xml,monkey.jungle,build.sh,install-edge.sh}
ebike-sandbox/t1-bikepower/tools/                 ← fitpeek.py, fitfields.py, fitprobe.py, fit-profile-export.py
ebike-sandbox/t1-bikepower/docs/fit/profile-21.171.json
ebike-sandbox/t1-bikepower/docs/ant/              ← profils ANT+ Bicycle Power 5.1 et LEV (PDF + texte)
ebike-sandbox/t1-bikepower/logs/                  ← logs de tournes + le .FIT de la preuve
ebike-sandbox/t1-bikepower/probe-datafield-ant/   ← la sonde « data field → canal ANT+ »
ebike-sandbox/t1-bikepower/README.md              ← le carnet complet (chronologique)
```

Chemins Linux cités dans ce document : `/media/greg/media/kDrive/git/ebike-df` (dépôt réel),
`/media/greg/media/kDrive/git/ebike-sandbox/t1-bikepower` (banc),
`/home/greg/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.3.0-2026-10-20-95888f262` (SDK).
Sur Windows : `bin/monkeyc.bat`, `bin/monkeydo.bat`, et le chemin SDK différent — ne pas
reprendre les commandes Linux telles quelles.

**Sur le simulateur, sois explicite sur ce qu'il prouve.** Il décide, sans radio : est-ce que le
code compile pour la cible ; est-ce que les API ANT sont *autorisées* au type d'app (data field /
watch‑app) et ce qu'elles renvoient (`cfg true` / `open true` / `tx true` ou une exception) ;
est-ce que la construction des pages et l'intégrale de puissance sont justes ; est-ce qu'un
crash existe. **Il ne décide pas** : la découverte et l'appairage par la pile native (c'est une
histoire de réseau, de clé et de radio), ni le contenu réel d'un `.FIT` d'activité sur
l'appareil. Sur ce banc, le simulateur Linux était inutilisable (`libwebkit2gtk-4.0.so.37`
absent), donc **tout ce qui est écrit ici vient de l'appareil réel** — garde cette discipline :
le simulateur pour la logique, l'appareil pour la radio et le `.FIT`.

Transfert sur les appareils : l'Edge se monte en vfat (`/media/greg/GARMIN`, absent entre les
builds) ; **la montre ne expose pas de volume**, c'est du MTP, pris en main à la main par
l'utilisateur (`gvfsd-mtp`, `pkill -x gvfsd-mtp` si bloqué).

---

## 9. Pièges d'API Connect IQ (SDK 9.3.0) déjà payés

- `Ant.DeviceConfig` : `new Ant.DeviceConfig(dictionnaire)`. Le dictionnaire seul est refusé,
  qu'il soit à forme fixe ou `new Dictionary()`.
- Une clé « non demandée » = **ne pas mettre la clé** dans le sac : `networkKey64Bit` refuse
  `null` à la compilation.
- La trame ANT = **8** octets. `Ant.Message.DATA_PAYLOAD_LENGTH` n'est pas résoluble à la
  compilation ; déclare la constante toi-même.
- Un `catch` **ne voit pas** les variables déclarées dans son `try`, et le type d'une variable
  locale est toujours inféré (`var ch as Ant.GenericChannel?` → « Invalid explicit typing of a
  local variable »). D'où : le canal est pris par le constructeur, stocké dans un membre typé,
  et tout `close()`/`release()` est protégé — `close()` sur un canal acquis mais jamais
  configuré lève.
- Pas de mot-clé `foreach` : `for (var i = 0; i < list.size(); i += 1)`. `or`/`and` sont
  réservés. `[Number]` est un tableau **figé**.
- Alignement de texte : `Graphics.TEXT_JUSTIFY_LEFT` (pas `TEXT_ALIGNMENT_LEFT`).
- Un projet `type="datafield"` a une entrée `Application.AppBase` (cf. `source/EbikeField.mc:658`)
  ; une classe `WatchUi.DataField` *qui n'est pas l'entrée* garde `onUpdate(dc)` ;
  `setString`/`setReturnValue` ne sont pas résolus sur une classe prise comme entrée.
- Journal d'app : `System.println` + un fichier `.TXT` **du même nom que le `.PRG`** dans
  `Garmin/Apps/LOGS/`, **créé à l'avance** (`CIQ_LOG.YML` ne sert qu'aux crashs non gérés et
  est cumulatif). Le nom du `.PRG` fait **8 caractères maximum**. Le `.TXT` tourne vers ~5 ko
  en `.BAK`, et ce qui disparaît est **le début** — là où sont les lignes utiles. Écris une
  erreur **une fois** (`Speaker.failure()`), `printStackTrace()` une fois, et budgette
  (`TRACE_LIMIT = 60` lignes par canal) : une exception relancée par tick écrivait sa pile à
  chaque tick.
- Le `.PRG.debug.xml` annote les piles : garde-le à côté du `.PRG` quand tu joues une variante.
- **Identité par variante** : chaque variante du banc a son propre `iq:application id`, son
  `@Strings.AppName` et son nom de `.PRG`, écrits par `build.sh` (sinon l'appareil ne garde
  qu'une seule entrée). Les constantes de conformité, elles, ne varient pas.

---

## 10. Où reprendre, en trois lignes

1. Sur Windows : jouer `probe-datafield-ant/` dans le simulateur → fermer la question 2 de la
   section 5 (une app de type *data field* peut-elle ouvrir un canal ANT+ maître).
2. Écrire le porteur ANT+ dans `ebike-df` avec la recette de la section 2 et les valeurs de
   `Sigma.mc`, en répondant d'abord à la question 1 de la section 5 (montre comme émetteur).
3. Vérifier avec un `.FIT` (section 7), en comparant `device_info.serial_number`, `product`,
   `software_version` aux valeurs posées dans les pages 0x50/0x51.

Le banc `t1-bikepower` reste utilisable comme témoin : `tx.edgpr` est la configuration connue
bonne ; `tx.edgk` (public), `tx.edgpk`/`tx.edgp` (PLUS) et les variantes sans clé sont les
négatifs documentés. Son README est le détail chronologique ; ce document est l'état.
