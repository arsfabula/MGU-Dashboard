# Handover — pont BLE Sigma → ANT+ *Bicycle Power* émis par Connect IQ

**À lire en premier si tu repars sans contexte.** Ce document s'adresse à la même IA, dans une
session neuve. Il ne suppose rien de la conversation précédente : chaque affirmation porte sa
source (fichier, offset, ligne, log). Il remplace le fil de discussion, pas le carnet de banc.

Date des mesures : 2026‑11‑26. Matériel de validation : **epix Pro 51 mm** (pièce `006-B4314-00`,
fw 28.08, id produit CIQ **`epix2pro51mm`**, produit FIT **4314**) et **Edge Explore**
(`006-B3011-00`, fw 5.40, CIQ 6.0.4, id produit **`edgeexplore`**). SDK Connect IQ
**`connectiq-sdk-win-9.3.0-2026-10-20-95888f262`** (Windows ; les chemins Linux de la section 8 sont
historiques). **État au 2026‑11‑26 soir : toutes les questions de la section 5 sont fermées sur
l'appareil par la sonde `tx.df1` (trois sorties sur l'Edge + trois `.FIT` relus). La suite est la
section 6 : écrire le pont dans `ebike-df`.**

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
| `deviceNumber` (ANT-id) | **252** pour *Bicycle Power*, **253** pour LEV — numéros fixés du produit (décision D6, 2026‑11‑26) | log `:23` (`OPEN id 252`) ; sonde `tx.df1` |
| `deviceType` | **11** (*Bicycle Power*) | `AntBp.DEVICE_TYPE` |
| `transmissionType` | **0x05** — Table 5‑2 du profil : un maître doit `MSN = 0` **et `LSN = 5`**. Joué tel quel sur l'appareil par la sonde `tx.df1` (2026‑11‑26) : l'epix s'appaire et enregistre. Le banc historique avait émis 0 sans conséquence visible, mais il n'y a plus de raison de déroger | exigence : `docs/ant/bicycle-power-5.1.txt` Table 5‑2 ; mesure : sonde `tx.df1`, relectures `CFG tt=5` |
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
| Chercher pendant que l'émetteur est en second plan | un Garmin ferme tous les canaux d'une app qui n'enregistre pas d'activité ; **une seule app à la fois** par appareil ; l'émetteur doit rester au premier plan. Nuance mesurée par `tx.df1` : pour un *data field*, la borne réelle est le passage « inactive » de l'app elle-même — un champ de données gardait ses deux canaux maîtres pendant toute l'activité qui l'hébergeait |
| L'Edge comme récepteur de capteurs de puissance | limite commerciale de la gamme : l'Edge ne voit pas les profils *Power*. C'est pourquoi l'Edge était l'émetteur et la montre la juge |

Deux points jamais élucidés, sans effet sur la suite : `tx.edgx` (v0.0.13) n'a jamais démarré
(`LOGS/BPTXEDGX.TXT` à 0 octet, aucune entrée `CIQ_LOG.YML`) ; la cause interne du `null` de
`sendBroadcast` sur PLUS.

---

## 5. Questions — fermées sur l'appareil par la sonde `tx.df1` (2026‑11‑26)

La sonde `tx.df1` (`ebike-sandbox/t1-bikepower/probe-datafield-ant/`, app `type="datafield"`,
v0.0.1→v0.0.5, **trois sorties sur l'Edge Explore**, trois `.FIT` de l'epix relus) a fermé ce qui
suit. Détail chronologique : README du banc ; règles consolidées : section 6 ci-dessous.

1. **Un *data field* obtient-il un canal maître, et le garde-t-il pendant un enregistrement ?**
   **Oui, mesuré, deux à la fois.** Sur l'Edge Explore, l'app de champ de données a obtenu
   252/type 11 **et** 253/type 20 en un seul essai chacun (`a=1`, `f=0` sur toute la sortie) et les
   a gardés `OPEN` de bout en bout des trois sorties, dont 8 min 17 s d'enregistrement actif sur
   l'Edge (`REC START`/`REC STOP` horodatés avec les deux canaux `OPEN`). La règle *Multitasking* de
   la doc ne s'applique qu'au passage « inactive » de l'app elle-même, pas à l'activité qui l'héberge.
   La sous-question « la montre émettrice se découvrirait-elle elle-même » ne se pose plus : décision
   D1, l'émetteur est l'Edge qui tient le BLE, le récepteur est l'epix en appairage natif sans champ
   de données — cas exactement rejoué par les sorties.
2. **La voie « data field » compile et s'exécute** : non seulement compilée, mais exécutée sur
   l'appareil, émission réelle (`n` croît d'une trame par tick pendant que l'écran est actif) et
   enregistrement complet côté récepteur : `device_info` **nommé** (`serial_number=252`,
   `manufacturer=1`, `product=21553`) et `record.power`/`cadence`/`enhanced_speed`/
   `ebike_battery_level`/`ebike_travel_range` aux valeurs posées par la sonde.
3. **Que faire quand le BLE Sigma tombe** : **décidé** — continuer d'émettre les valeurs invalides
   `0xFF` plutôt que de rendre l'antenne, pour ne pas casser l'appairage côté récepteur.
4. **Quel ANT-id publier** : **décidé** (D6) — 252 et 253, fixes. Reste à trancher à l'écriture, sans
   bloquer : la politique de collision si un capteur réel du réseau porte le même (id, device type).
5. **Le profil *LEV*** : conçu et payé — pages 1/2/3 construites et vérifiées octet par octet, et
   l'epix les enregistre (`ebike_battery_level`, `ebike_travel_range`, `enhanced_speed`). Les colonnes
   FIT attendues sont **`ebike_battery_level` (118) et `ebike_travel_range` (117)**, pas
   `motor_power`/`battery_soc` (absents du dictionnaire comme de l'enregistrement).
6. `minSdkVersion` : la sonde a tourné avec `minSdkVersion="3.1.0"` sur l'Edge Explore (CIQ 6.0.4) —
   la valeur du produit convient pour cette cible. Les autres produits restent à vérifier à
   l'export, comme d'habitude.

## 5bis. Deux acquis qui changent la forme du pont (mesurés, pas devinés)

- **Un récepteur fige au démarrage de son activité ce qu'il enregistre.** À la sortie n° 2, le canal
  était ouvert et émetteur et l'epix l'a déclaré — sans `serial_number` et sans `power` : les pages
  d'identification n'étaient pas encore parties. Donc : le pont ouvre ses canaux au démarrage de
  l'app, **avant** tout enregistrement, et la **première trame après chaque ouverture doit être la
  page fabricant 0x50, suivie de la page produit 0x51** (la sonde, en décalant sa phase d'une trame,
  a fait attendre l'identification 2 min 57 s — c'est le `.FIT` qui l'a montré, pas un test).
- **Le pompage par l'écran ne suffit pas.** Le dessin d'un champ de données s'arrête écran éteint :
  `PUMP GAP` mesurés jusqu'à 43 s, le canal reste ouvert mais **aucune trame ne part** pendant ce
  temps. `Toybox.Timer` n'est pas disponible dans une app de champ de données (mesuré : l'app meurt
  au premier `start()`). Le pont doit être pomé par l'arrivée des trames BLE — celles du produit
  continuent pendant l'écran éteint (le produit affiche des données à jour au réveil ; à confirmer
  par compteur sur la première sortie réelle avec le pont).

Deux corrections de mes propres notes, pour que rien ne se répète : `accumulated_power` 80 104 J
relevé dans un `.FIT` **n'était pas notre compteur** (nous n'avions émis que 59 850 J) — c'est le
total que le récepteur intègre depuis la puissance instantanée ; le champ cumulé u16 de la page 0x10
boucle à 65 535 et ce récepteur l'ignore. Et « MD_0015 » n'existe pas dans le profil *Bicycle
Power* : la source du « au moins 1 fois sur 121 » est la Table 7‑3 (`:1066-1141`, `:2493`).

---

## 6. La tâche concrète, dans l'ordre (le pont dans `ebike-df`)

**Étape 0 jouée** : la sonde a tourné sur l'appareil, les questions de conception sont fermées
(section 5). Les règles complètes à respecter sont celles de la section 5bis plus celles-ci,
détaillées dans le document de design `~/.opencode/plan/ant-bridge-design.md` §4 — si ce fichier
n'est pas sous la main, cette section suffit.

1. `iq:uses-permission id="Ant"` dans `manifest.xml` (le produit ne l'a pas).
2. Un module de pont dans `source/` : la **mise en page des pages** et la **machine à états du
   canal** se reprennent telles quelles de la sonde de banc v0.0.5
   (`t1-bikepower/probe-datafield-ant/source/Pages.mc`, `MasterChannel.mc` — décodage de
   `channelClosed` 0x40/7, phase `sinceOpen` avec 0x50 à la trame 0 et 0x51 à la 1, puis une fois
   par 121 ; deux canaux **indépendants**, périodes 8182/8192 non unifiées, RF 57, réseau privé +
   clé ANT+ 64 et 128). Les **valeurs** viennent du modèle existant (`Sigma.mc:15-25`,
   `EbikeData`), pas d'une rampe ; le pompage se fait **à l'arrivée des trames BLE**, jamais sur une
   horloge d'écran (section 5bis). Cadence = cadence de la donnée (D8, écart au 4 Hz du profil
   assumé et mesuré sans effet sur l'enregistrement) ; données périmées → `0xFF` sans fermer le
   canal ; champ cumulé u16 émis avec son wrap de 65 535, sans lui prêter de sens.
3. Toggle du pont dans `EbikeSettings`, **désactivé par défaut** (D5), chaînes dans les quatre
   langues (piège n° 19 du `HANDOFF-NOUVELLE-SESSION.md`) ; indicateur d'état (D7) : aucun canal /
   1 canal / 2 canaux + compteur de reprises.
4. Journal : transitions de canal et échecs nommés uniquement. **Jamais les rotations de pages** —
   une rotation n'est pas une transition ; le journal de l'appareil tourne à ~5 ko et perd sa tête.
5. **Jalon de taille avant d'aller plus loin** : build `enduro` avec `--build-stats 1` sur arbre
   propre (gen/mir/bin vidés) — le plafond qui compte est **32 768**, pas le « 131 072 available »
   (piège n° 22) ; marge actuelle du produit : **9 101 B**. Ordre de grandeur connu : la sonde
   complète (UI + Trace + tests embarqués) fait 10 549 B ; le pont, lui, doit rester sous la marge.
   Builds `-l 2` sans avertissement sur `edgeexplore` + les cibles du produit.
6. Sortie réelle avec le FD6D, puis **vérification par `.FIT`** (section 7) : `device_info` nommés
   aux deux ids, `record.power`/`cadence`, `ebike_battery_level`/`ebike_travel_range`. Toute
   variation validée sur le vélo avant `git push`, version incrémentée à chaque publication.

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

Le banc `ebike-sandbox/` **est devenu un dépôt git** le 2026‑11‑26 (local, jamais poussé) :
`C:\Users\greg\git\ebike-sandbox`, base `55f3bca` → `ec2d5a1` et la suite. Son README est le
carnet chronologique complet. Contenu utile, chemins relatifs à `t1-bikepower/` :

```
probe-datafield-ant/source/          ← Pages.mc (pages vérifiées octet par octet) et
                                       MasterChannel.mc (machine à états du canal, v0.0.5) :
                                       le modèle à reprendre pour le pont
source/AntBpTest.mc                  ← la watch-app de banc, tx.edgpr = configuration connue bonne
tools/                               ← fitpeek.py, fitfields.py, fitprobe.py, fit-profile-export.py
docs/fit/profile-21.171.json         ← dictionnaire FIT (SDK 21.171) utilisé par les outils
docs/ant/                            ← profils ANT+ Bicycle Power 5.1 et LEV (PDF + texte)
logs/                                ← logs de tournées + les .FIT de preuve et leurs décodages
README.md                            ← le carnet complet (chronologique)
```

Chemins actuels (Windows) : `C:\Users\greg\git\ebike-df` (dépôt produit),
`C:\Users\greg\git\ebike-sandbox\t1-bikepower` (banc),
`C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262`
(SDK ; `bin/monkeyc.bat`, `bin/monkeydo.bat`, `bin/simulator.exe` — le simulateur s'appuie sur le
port 1234, pas 1200). Les chemins Linux (`/media/greg/media/kDrive/...`) sont historiques.

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

1. **Écrire le pont dans `ebike-df`** en suivant la section 6 : plus aucune question ANT+ n'est
   ouverte. Modèles à reprendre : `Pages.mc` et `MasterChannel.mc` de la sonde v0.0.5 ; valeurs du
   modèle existant (`EbikeData`, `Sigma.mc`), pompage sur les trames BLE.
2. **Premier jalon avant toute sortie** : taille `enduro` sur arbre propre (plafond 32 768, marge
   9 101 B), builds `-l 2` sans avertissement, tests unitaires. Puis sortie réelle avec le FD6D et
   vérification par `.FIT` (section 7) : `device_info` nommés 252/253, `record.power`/`cadence`,
   `ebike_*`.
3. Toute question ANT+ neuve se juge au banc, pas dans le code produit : `tx.edgpr` reste la
   configuration connue bonne, `tx.df1` le modèle de cycle de vie (pas de cadence), `tx.edgk` /
   `tx.edgpk` / `tx.edgp` les négatifs documentés. Son README est le détail chronologique ; ce
   document est l'état.
