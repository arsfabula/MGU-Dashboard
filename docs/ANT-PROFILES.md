# Profils ANT+ du projet — *Bicycle Power* (11) et *LEV* (20)

**Document de référence**, pas un carnet : il décrit ce que les deux profils exigent et ce
qu'ils peuvent transporter, avec la source de chaque chiffre. Décision de conception actée :
**le projet émettra les deux** — *Bicycle Power* pour la puissance du cycliste et la cadence,
*LEV* pour la vitesse, l'assistance, la batterie et l'autonomie. L'état d'avancement et la
prochaine tâche sont dans `HANDOFF-ANT-BRIDGE.md`.

Sources locales, gardées avec le banc (`ebike-sandbox/t1-bikepower/docs/ant/`) :

| document | fichier | ancres citées ici |
|---|---|---|
| ANT+ *Bicycle Power Device Profile*, D00001086 rev 5.1, 112 p. | `bicycle-power-5.1.txt` | Table 5‑1 `:803-845`, Table 5‑2 `:919-945`, Table 7‑3 `:1120-1150`, Table 8‑1 `:1250+`, `[MD_0007]` `:4771`, `[MD_0014]` §22.3 |
| ANT+ *Light Electric Vehicle Device Profile*, 36 p. | `lev.txt` | Table 4‑1 `:445-475`, Table 4‑2 `:490-510`, Table 5‑2 (page 1) `:724`, Table 5‑8 (page 2) `:937`, Table 5‑10 (page 3) `:1049`, Table 5‑11 (page 4) `:1149`, `% Assist` `:1126-1130` |

Un mot sur le vocabulaire : un **profil ANT+** est un document de l'ANT+ *Managed Network*
(identité d'appareil + configuration de canal + mise en page des pages + motif d'émission +
comportement du récepteur). Il n'a **aucun rapport** avec le **profil FIT** (le dictionnaire du
format de fichier `.FIT`) — voir la section 5 pour la correspondance observée entre les deux.

---

## 1. Ce qu'un profil impose, et qui l'applique des deux côtés

| ce que le profil fixe | côté émetteur (nous) | côté récepteur (la montre) |
|---|---|---|
| identité : `device type`, `transmission type`, `device number` | nous les posons dans `Ant.DeviceConfig` | la montre les met dans son masque de recherche |
| configuration de canal : type (maître 0x10 / récepteur 0x00), canal RF, période, clé de réseau | idem | idem — **c'est là que tout s'est joué** |
| mise en page des pages de données (8 octets, n° de page à l'octet 0) | nous construisons les trames | le récepteur les décode |
| pages requises / interdites et motif d'entrelacement | à respecter | à recevoir |
| comportement de recherche (timeout, wildcard, ce qui est mémorisé après appairage) | — | imposé au fabricant de la montre |

Un récepteur natif **conforme** applique la table « Slave Channel Configuration » du profil.
C'est pour ça qu'une émission Connect IQ sur le réseau *Public* n'a jamais été trouvée : la
montre cherchait, mot à mot, avec la clé du réseau géré ANT+.

---

## 2. Profil *Bicycle Power* 5.1 — ce que le banc a émis et ce qui reste à corriger

**Identité et canal.** Table 5‑2 (maître) : type de canal **master 0x10 bidirectionnel**
`[MD_0004]` ; **clé du réseau géré ANT+** ; **RF canal 57** (2457 MHz) ; `device type`
**11 (0x0B)** `[MD_0001]` ; `device number` **1‑65535, jamais 0x0000** ; période de canal
**8182 counts** (8182/32768 s ≈ 4,005 Hz) ; `transmission type` « MSN = 0 **et LSN = 5** »,
donc **0x05**.

> **Écart connu du banc, à corriger dans le produit** : nous avons émis `transmissionType = 0`
> (`t1-bikepower/source/AntBpTest.mc:44`). L'appairage a réussi quand même, et la montre n'a
> pas enregistré de `ant_transmission_type` dans son `.FIT`. Une variante à 0x05 n'a **pas**
> été jouée : la corriger est propre, pas prouvé nécessaire.

**Côté récepteur** (Table 5‑1, ce que l'epix a fait) : canal *receive* 0x00 — « power sensors
require bi-directional communication » — ; clé du réseau géré ANT+ ; RF 57 ;
`transmission type` **0 pendant la recherche d'appairage**, puis mémorisé ; `device type` 11
`[SD_0001]` ; `device number` **0 = wildcard** pendant la recherche ; période **8182**
`[SD_0003]` (« all receivers shall use the 8182 period »), 4091 autorisé seulement en
reconnexion à un capteur déjà connu. §5.1.3 rend obligatoire la réception des pages communes
*fabricant* et *produit*.

**Pages.** Émises par le banc : **0x10 *Power Only***, **0x50 *Manufacturer's Information***,
**0x51 *Product Information***.

| page | mise en page (octets 0‑7) | exigence du profil |
|---|---|---|
| 0x10 | `0x10`, *update event count* (7 bits, bit 7 = drapeau *Pedal Differentiation*), `0xFF` (pas de répartition gauche/droite), cadence (1 rpm), puissance cumulée u16 LE (**J**), puissance instantanée u16 LE (**W**) | page principale, **requise**, entrelacée **au moins 1 fois sur 9** trames, préférée 1 sur 5 `[MD_0008]` (Table 7‑3, Table 8‑1) |
| 0x50 | `0x50`, `0xFF`, `0xFF`, révision matérielle, fabricant u16 LE (LSB, MSB), modèle u16 LE (LSB, MSB) | page commune **requise**, au moins **1 fois sur 121** (≈30,25 s à 4 Hz) |
| 0x51 | `0x51`, `0xFF`, `0xFF`, révision logicielle, numéro de série u32 LE | page commune **requise**, au moins **1 fois sur 121** |

Optionnelles non émises : 0x13 (*Torque Effectiveness / Pedal Smoothness*), 0x52 (*Battery
Voltage*). Non applicables à un capteur « power only » : 0x11/0x12 (*Torque at Wheel/Crank*).
**Interdites** : pages 4‑15, 21‑31, 33‑111 `[MD_0007]`. Réserve utile : §22.3 — un capteur
`[MD_0014]` n'ouvre pas d'autre canal maître sur la clé ANT+ gérée **sauf si ce canal est
conforme à un profil ANT+ publié**. C'est ce qui autorise, en droit, d'émettre *Bicycle Power*
**et** *LEV* en même temps (les deux sont des profils publiés), et ce que la doc Connect IQ
traduit brutalement par « les canaux maîtres ne sont pas permis sur le réseau ANT+ ».

---

## 3. Profil *LEV* — device type 20, et ce qu'il ne peut **pas** dire

**Identité et canal** (Tables 4‑1 récepteur / 4‑2 maître) : maître 0x10 ; clé du réseau géré
ANT+ ; **RF canal 57 (0x39)** ; `device type` **20 (0x14)** ; `device number` 1‑65535, jamais
0 ; `transmission type` **0x05** ; période de canal **8192 counts** (≈4 Hz) — **pas 8182** ;
timeout de recherche 30 s. Motif d'émission décrit par le profil : pages 1 et 2 à 1 Hz
chacune, optionnel à 1 Hz.

**Pages qui nous intéressent** (extraits, positions d'octets telles que Table 5‑2 / 5‑8 /
5‑10 / 5‑11 ; les tables complètes sont dans `lev.txt`) :

| page | contenu, octet par octet |
|---|---|
| **1** *Speed & System Information 1* | `0x01`, état de température, mode de marche (Table 5‑4 : 000 = *assist off*, 001‑110 = assist 1‑6), état du système, état des vitesses/rapport, message d'erreur, vitesse u16 LE 1.5 o /0,1 km/h (bits 4‑7 du dernier octet = réservé, `0xF`) |
| **2** *Speed & Distance* | `0x02`, odomètre 3 octets /0,01 km, autonomie restante 1.5 o /1 km, vitesse (même encodage que page 1). Page 34 = variante optionnelle |
| **3** *Speed & System Information 2* | `0x03`, **état de charge batterie** (bits 6‑0 = %, bit 7 = alerte vide), mode de marche, état système, rapport, **% d'assistance** |
| **4** *Battery Information* | `0x04`, réservé `0xFF`, cycles de charge 1.5 o, consommation **Wh/km** 1.5 o /0,1, tension batterie /¼ V |
| 5 | capacités (modes supportés, circonférence de roue) ; page 16 = données destinées à l'afficheur |

**Ce que LEV ne transporte pas — la phrase la plus importante de ce document** : *aucune* de ses
pages ne contient de **cadence** ni de **puissance absolue**. La seule trace de puissance est un
**ratio**, page 3 : `% Assist = Motor power / (Motor Power + User Power)` (`lev.txt:1126-1130`),
plus une consommation en Wh/km. Donc :

* *LEV* seul ⇒ pas de FTP, pas de zones de puissance, pas de records de puissance, pas de
  cadence. **C'est *Bicycle Power* qui porte les deux.**
* *Bicycle Power* seul ⇒ pas d'assistance, pas de batterie, pas d'autonomie, pas de vitesse.
* Les deux ensemble ⇒ tout ce que le protocole Sigma `0xFD6D` sait déjà dire
  (`source/Sigma.mc` : `TreadlePower`, `TreadleTorque`, `Cadence`, `MotorPower`,
  `MotorTorque`, vitesse, distance, batterie).

Ne pas s'attendre à un pendant côté SDK : `Toybox.AntPlus` n'expose **aucune classe LEV**
(inventaire complet de `doc/Toybox/AntPlus/`, aucun « ebike » ni « light electric » dans toute
l'arborescence `doc/`) — on construit les trames à la main, comme pour *Bicycle Power*.

---

## 4. Émettre les deux depuis la même app Connect IQ

Ce qui est mesuré, et ce qui ne l'est pas :

* **Acquis** : un canal maître avec `deviceType 11` sur un **réseau `NETWORK_PRIVATE` portant
  la clé ANT+ en 64 et 128 bits** est découvert et appairé par un hôte natif
  (`HANDOFF-ANT-BRIDGE.md` §2‑3). Maîtres sur `NETWORK_PUBLIC` et `NETWORK_PLUS` : non
  découverts / refusés.
* **À traiter comme deux canaux indépendants** : deux `Ant.GenericChannel`, deux
  `Ant.DeviceConfig`, deux périodes (**8182** et **8192** — ne pas les unifier, elles viennent
  des deux profils), même canal RF 57, même clé de réseau, **numéros d'appareil différents**
  (rappel : un ANT-id tient sur un octet côté Connect IQ ; le banc a utilisé 250 public,
  251 PLUS, **252 privé**).
* **Non mesuré** : le nombre de canaux maîtres qu'un appareil accepte simultanément. Une
  acquisition qui échoue lève `Ant.UnableToAcquireChannelException` ; prévoir de ne pas ouvrir
  le second canal au premier plan si le premier n'est pas pris, et de le re-tenter plus tard.
* **Attention piège du SDK** : `Ant.DeviceConfig.DEFAULT_MESSAGE_PERIOD = 8192`. C'est la
  valeur LEV, pas celle de *Bicycle Power*. Ne pas s'en servir comme défaut.
* **Minutage** : la pile radio retransmet la dernière trame à la fréquence de la période de
  canal ; le banc n'écrivait une nouvelle trame que par seconde (l'Edge Explore refuse un
  `Timer` plus court que 1 s, erreur fatale `Invalid Value` à `timer.start`). Deux profils
  tournant sur deux périodes différentes, un seul minuteur à 1 s avec entrelacement suffit
  largement pour satisfaire les minimums (1 sur 9 pour 0x10 ; 1 sur 121 pour 0x50/0x51).
* Une app qui n'est pas en train d'enregistrer une activité voit **tous ses canaux fermés**
  (`doc/docs/Core_Topics/Application_and_System_Modules.html`, API 4.2.0) — valable pour les
  deux canaux.

---

## 5. Correspondance ANT+ → FIT, observée dans le `.FIT` d'une activité de l'epix

Numéros de champs pris dans `docs/fit/profile-21.171.json` (dictionnaire exporté du profil
généré du SDK FIT **21.171**), vérifiés sur `t1-bikepower/logs/25205307891_ACTIVITY.fit`
(fichier écrit, lui, avec un profil 21198). **Aucun numéro récité de mémoire** : une ancienne
version de ces notes donnait `record.power` au champ 5 et `accumulated_power` au champ 87 —
le champ 87 est `cycle_length16`, sans rapport.

| page ANT+ émise | message FIT | champ (n°) | relevé |
|---|---|---|---|
| 0x10 octets 6‑7 (W) | `record` (20) | `power` (**7**) | 24/24 points, 140 → 236 W |
| 0x10 octet 3 (rpm) | `record` | `cadence` (**4**), `fractional_cadence` (**53**, /128) | 24/24, 66 → 98 rpm |
| 0x10 octets 4‑5 (J) | `record` | `accumulated_power` (**29**, uint32) | 22/24 ; écarts `156, 0, 0, 492, 172, 0, 0, 540…` |
| 0x50 octet 3 | `device_info` (23) | `hardware_version` (**6**) | 1 |
| 0x50 octets 4‑5 | `device_info` | `manufacturer` (**2**) | 1 |
| 0x50 octets 6‑7 | `device_info` | `product` (**4**) | 0x5431 |
| 0x51 octet 3 | `device_info` | `software_version` (**5**) | 110 → 1.1 |
| 0x51 octets 4‑7 | `device_info` | `serial_number` (**3**) | 252 = notre ANT-id |
| — (aucun émetteur LEV) | `record` | `motor_power` (**82**), `battery_soc` (**81**) | **absents des enregistrements testés** : la montre n'avait pas de source pour ces colonnes |
| — (aucun émetteur) | `record` | `speed` (6), `distance` (5) | présents mais à 0 dans l'essai : l'activité se fiait à l'accéléromètre |

Conséquence directe pour le projet : **la page 0x50 et la page 0x51 sont le meilleur contrôleur
d'essai**. Leur contenu revient octet pour octet dans `device_info`, donc un `.FIT` suffit à
prouver que c'est bien *notre* émetteur qui a été appairé — avant même de regarder les watts.
Pour *LEV*, aucun de ces champs n'est encore apparu : la correspondance pages LEV →
`motor_power`/`battery_soc` est une **hypothèse à vérifier**, pas une observation.

---

## 6. Règle de lecture pour la suite

Tout ce qui est écrit ici est soit une citation de profil (avec table et ligne), soit un relevé
d'appareil (avec fichier et offset). Les deux sont signalés. Si une affirmation future contredit
le profil, c'est l'affirmation qui est fausse ; si elle contredit l'appareil, c'est l'appareil
qui décide, et il faut le mesurer.
