# PASSATION — reprendre ce projet dans une NOUVELLE session opencode

> **STATUT 2026-09-21.** Le data field Sigma/FD6D est **fonctionnel et validé
> terrain**. Depuis la session précédente : la **vitesse a été retirée** et
> remplacée par la **puissance moteur (RX2)** ; le **mode d'assistance (RX7)** est
> décodé et affiché ; les **fonts de valeur** ont été agrandies. Les 4 cibles
> (`venusq2`, `epix2pro42mm/47mm/51mm`) compilent : `BUILD SUCCESSFUL`.
>
> Objectif de cette passation : permettre à une session neuve de continuer
> **sans dépendre de la mémoire de la session précédente**. Lire ce doc en
> entier, puis re-lire les fichiers cités avant toute édition.

---

## 1. Projet — infos de base

- **Racine** : `C:\Users\greg\Documents\Default Project\ebike-df\`
- **Type** : app Connect IQ (Monkey C) — **data field** (`EbikeField`) + fit
  contributor (`EbikeFitContributor`), qui lit le vélo Sigma via BLE.
- **Nom affiché** : `@Strings.AppName` = **« MGU Dashboard »**.
- **Langues** : `eng` (primaire), `fre`, `deu`, `ita` (déclarées dans
  `manifest.xml` ; dossiers `resources/`, `resources-fre/`, `resources-deu/`,
  `resources-ita/`).
- **Cibles** (`manifest.xml`) : `edgeexplore`, `epix2`, `epix2pro42mm`,
  `epix2pro47mm`, `epix2pro51mm`, `instinctcrossoveramoled`, `venusq2`.
- **Permissions** : `BluetoothLowEnergy`, `FitContributor`.
- **Clé de signature** : `developer_key.der` (racine).
- **Jungle** : `monkey.jungle` = `project.manifest = manifest.xml` (rien d'autre).

### Build (vérifié)

```powershell
& "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2\bin\monkeyc.bat" `
  -f monkey.jungle -o "C:\Users\greg\AppData\Local\Temp\opencode\ebike-test.prg" `
  -y developer_key.der -d venusq2 -l 0
```

- `-l 0` = typecheck **Off** (réglage IDE utilisateur) → `BUILD SUCCESSFUL`.
- `-l 2` = strict → **échoue sur UNE erreur pré-existante** (voir §6), sans lien
  avec les évolutions récentes. Les cibles `epix2pro*` produisent des `.iq` dans
  `bin/` ; le `.prg` de sideload est `bin\ebikedf.prg`.

---

## 2. État fonctionnel actuel

### Métriques affichées (ordre de `_collectMetrics`, `EbikeField.mc`)

| Ordre | Métrique | Source | Clé de config | Unités |
|---|---|---|---|---|
| 1 | **Power** (cycliste) | RX1 `u16(6)` | `CFG_KEY_METRIC_POWER` | W |
| 2 | **Motor** (moteur) | RX2 `u16(0)` | `CFG_KEY_METRIC_MOTOR_POWER` | W |
| 3 | **Cadence** | RX1 `d[9]` | `CFG_KEY_METRIC_CADENCE` | rpm |
| 4 | **Assist** (mode) | RX7 `d[0]` | `CFG_KEY_METRIC_ASSIST` | (aucune) |
| 5 | **Battery** | RX3 `d[0]` | `CFG_KEY_METRIC_BATTERY` | % |
| 6 | **Range** (autonomie) | RX3 `u16(6)` | `CFG_KEY_METRIC_RANGE` | km |

- **La vitesse n'est plus affichée** (métrique « Speed » retirée). `RX1 Speed`
  reste **décodé** dans `model.speedKmh` (démo / log), mais aucun affichage.
- État « **En attente…** » : `!demoMode && model.batterySoc == null &&
  timer - lastUpdate > 10000` (`EbikeField.mc:148`).
- **Fonts** : `_fitValueFont` (`EbikeField.mc:524`) = échelle **order-indépendante
  du plus grand font qui rentre** : candidats `FONT_NUMBER_HOT/MILD/MEDIUM` puis
  `FONT_LARGE/MEDIUM/SMALL/XTINY`. `_fontLetter` mappe le font retenu.
  ⚠️ Le SDK n'expose **pas** de `FONT_NUMBER_THIN_HUGE/LARGE` — ne pas en inventer.

### Menu réglages (`EbikeSettings.mc`)

Toggles : Demo, Libellés, CyclistPower, **MotorPower**, Cadence, Assistance,
Battery, Range, Debug. Le **niveau d'assistance est retiré du menu** (lignes
24-28 commentées, code conservé : `onAssistSelected`, `_assistLabel`,
`CFG_KEY_ASSIST_LEVEL`, `BleManager.setAssistLevel`).

### FIT (`fitcontributions.xml` + `EbikeFitContributor.mc`)

Champs enregistrés : id0 puissance cycliste (W, natif power=7), id1 cadence
(rpm, natif cadence=4), id2 **assistance = `model.assistMode`** (unité
`@Strings.Mode`), id3 batterie (%), id4 autonomie (km), id10 **puissance moteur
= `model.motorPowerW`** (W, natif motor_power=82) ; id5-7 résumé (moy. puissance,
moy. cadence, batterie mini) ; id8-9 par tour.

**Enregistrement en continu (champ non affiché)** : `Toybox.Timer` n'existe pas
dans un data field et `onUpdate` ne tourne que page affichée. Désormais
`BleManager.onCharacteristicChanged` appelle à chaque trame RX reçue
`onTick()` (heartbeat 1800 ms) puis `fit.update(_model)` (contributor branché
via `setFitContributor`) → l'enregistrement FIT continue même quand une autre
page est visible. Les moyennes restent **échantillonnées à 1 Hz** (gate
`_lastAvgTime` dans `EbikeFitContributor.update`, neutralise aussi le double
appel onUpdate+RX). Limite : le mode **demo** (sans BLE) reste lié à `onUpdate`.
À vérifier sur le terrain : les callbacks `onTimerStart/Pause/Lap` sont-ils
délivrés page cachée ? Sinon, `_timerRunning` serait faux pour une sortie menée
d'une autre page.

### Modèle (`EbikeData.mc`)

`motorPowerW`, `assistMode` ajoutés (+ reset). Conservés mais **non alimentés /
non affichés** : `speedKmh`, `assistPercent`.

---

## 3. Protocole Sigma/FD6D — état validé terrain (2026-09-21)

Service 16-bit `0xFD6D` (base Bluetooth) ; caractéristiques données
`0000000N-abab-4499-b9d7-d0efc0d06477`. Mapping `RXn ↔ SIGMA_MESSAGE_ID (n-1)`.
Détail complet : `docs/PROTOCOL.md` §S.1-S.4.

**Dispatch** (`BleManager.onCharacteristicChanged`, lignes 219-254) :

| RX / char | Message | Taille | Décodé ? |
|---|---|---|---|
| RX1 `00000001` | RIDE (vitesse, distance, puissance, couple, cadence) | 10 | ✅ (`parseRide`) |
| RX2 `00000002` | MOTOR | 10 | ✅ (`parseMotor` → `motorPowerW`) |
| RX3 `00000003` | BATTERY | 12 | ✅ (`parseBattery`) |
| RX5 `00000005` | DIAGNOSTIC | 11 | ⚠️ observé, **loggé brut** (non décodé) |
| RX7 `00000007` | ASSISTANCE | 2 | ✅ (`parseAssist` → `assistMode`) |
| RX4/RX6/RX8 | STATUS/SETUP/LIGHT | 3/117/4 | non observés, loggés bruts |

Souscription : RX1..RX8 (`FD6D_FIRST_CHAR=1`..`FD6D_LAST_CHAR=8`).
RX9..RX12 non souscrits (hors sondage).

### Trames réelles observées

- **RX1** `e7008b01000078001357` → 23,1 km/h · 0,4 km · 120 W · 19 Nm · 87 rpm.
- **RX2** `90014000ffffffff8029` → **400 W** · 64 Nm · courant/tension = `0xFFFF`
  (**n/a**) · temp `0x80`=128 (marqueur n/a) · **assist %** = 41. Le couple moteur
  suit la puissance. ⚠️ RX2 `d[9]` = **% d'assistance** (0..76), **≠** mode RX7.
- **RX3** `6440015ad28076000500701d` → SOC 100 % · 118 km · temp `0x80`.
  Tension `0xd25a`=53850 (≈53,85 V si mV), capacité `0x1d70`=7536 (échelles à
  confirmer). Autonomie vue 87/118/169 km.
- **RX5** `a8de0000f62e0000ffffff` → distance `0xdea8`=57000, 2ᵉ u32 = 12022
  (s'incrémente), puis `ff ff ff`.
- **RX7** `0100`/`0200`/`0300` → **modes 1 / 2 / 3**, start = 0.

**Heartbeat TX** : trame BCP single-frame écrite sur `5e8597ac` (BootUp à la
connexion, Operational toutes les 1800 ms, Stopped à la déconnexion) —
`BleManager._sendHeartbeat`. Seul vestige vivant de la pile BCP/CAP/PDO archivée.

---

## 4. Fichiers sources (`source/`)

- `EbikeField.mc` — data field / affichage / `_fitValueFont` (le plus gros fichier).
- `BleManager.mc` — BLE : scan, connexion, dispatch RX1/RX2/RX3/RX7, heartbeat TX,
  helpers `_decoded*`, `setAssistLevel` (assistance archivée).
- `Sigma.mc` — parseurs `parseRide` / `parseMotor` / `parseBattery` / `parseAssist`.
- `EbikeData.mc` — modèle partagé (`_model`).
- `EbikeConfig.mc` — clés de stockage + accès.
- `EbikeSettings.mc` — menu réglages (Menu2) + delegate.
- `EbikeFitContributor.mc` — champs FIT.
- `DemoManager.mc` — données simulées (`motorPowerW`, `assistMode` cyclique 1..4).

**Archive** (`archive/`, hors compilation) : `Bcp.mc`, `Cap.mc`, `Pdo.mc`,
`Assist.mc`.

**Docs** : `docs/PROTOCOL.md` (protocole), `docs/BUILD.md` (compilation),
`docs/QUICKSTART-FR.md` / `docs/QUICKSTART-EN.md` (guide utilisateur),
`docs/HANDOFF-NOUVELLE-SESSION.md` (ce fichier).

---

## 5. Ce qu'il reste à faire (pistes, non bloquant)

1. **RX5 non décodé** : observé mais loggé brut. Si utile, ajouter
   `parseDiagnostic` + un `_decodedDiagnostic` (unités à confirmer : distance
   57000 = m ?, 2ᵉ u32 = temps ?).
2. **RX2 `d[9]` (assist %)** : non mappé. Le champ `model.assistPercent` existe
   (inutilisé) — on peut l'alimenter si on veut afficher le **% d'assistance** en
   plus du **mode** (RX7).
3. ~~**Puissance moteur en FIT**~~ : **fait** — champ id10 `motor_power`
   (`nativeNum=82`), voir §FIT.
4. ~~**Enregistrement FIT quand le champ n'est pas affiché**~~ : **fait** —
   heartbeat + `fit.update` portés par le flux RX (`onCharacteristicChanged`),
   moyennes gated à 1 Hz, voir §FIT. Reste à valider sur le terrain + confirmer
   que `onTimer*` arrive page cachée.
5. **RX4/RX6/RX8** : jamais vus ; restent loggés bruts.
6. **Erreur typecheck stricte** (§6) : passer `_assistItem` en nullable pour un
   build `-l 2` propre.
7. **`Speed` string** et `CFG_KEY_ASSIST_LEVEL`/`assistLevel()` : reliquats
   inutilisés, sans effet — à nettoyer si on veut.

---

## 6. Pièges / points d'attention

1. **Erreur typecheck stricte pré-existante** (`-l 2`) :
   `source/EbikeSettings.mc:9: Member '$.EbikeSettingsMenu._assistItem' may not
   be initialized but does not accept Null.`
   Cause : `_assistItem` déclaré non-nullable, seule affectation dans le code
   commenté (ligne 27). Toléré car `monkeyC.typeCheckLevel: "Off"`. **Fix** :
   déclarer `private var _assistItem as WatchUi.MenuItem?;` et gérer le null.
2. **`Rez.Strings.X` est un ResourceId, pas une String** : tout affichage passe
   par `WatchUi.loadResource(Rez.Strings.X)`.
3. **Localisation** : chaque fichier `resources-<lang>/strings.xml` doit
   déclarer **tous** les ids (même valeur que l'anglais), sinon
   « String id undefined for language ». Codes : `fre` (pas `fra`), `deu`, `ita`.
4. **RX2 `d[9]` ≠ RX7 mode** : ne pas confondre le % d'assistance moteur (RX2)
   avec le mode d'assistance (RX7). Le log RX2 le note `assistNN%`.
5. **Trames de tailles fixes** : le dispatch teste `value.size()` (10/10/12/2) —
   une trame de taille inattendue est ignorée (mais loggée en hex).
6. **Lire un fichier en entier avant de l'éditer** ; éviter les lectures
   partielles parallèles (source d'incohérences dans une ancienne session).

---

## 7. Historique (déjà fait, pour contexte)

- **Pile BCP/CAP/PDO archivée** : `Bcp.mc`/`Cap.mc`/`Pdo.mc` déplacés dans
  `archive/`, références retirées de `BleManager.mc`. Seul le heartbeat TX BCP
  reste vivant.
- **Contrôle du niveau d'assistance** : archivé/désactivé (`archive/Assist.mc`).
- **Localisation** : eng + fre/deu/ita (labels, états, menu, titres).
- **2026-09-21** : vitesse → puissance moteur (RX2) ; mode d'assistance (RX7)
  décodé/affiché ; fonts de valeur agrandies ; RX2/RX5/RX7 validés terrain ;
  `docs/PROTOCOL.md` (§S.2-S.4) et les deux `QUICKSTART` mis à jour.
