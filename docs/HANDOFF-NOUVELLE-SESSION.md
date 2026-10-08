# PASSATION — reprendre ce projet dans une NOUVELLE session opencode

> **STATUT 2026-10-08.** Le data field Sigma/FD6D est **fonctionnel et validé
> terrain**. Depuis la session précédente : la **puissance cycliste est passée en
> jauge radiale** (arc concentrique épousant le **contour supérieur** de l'écran,
> échelle 0→2×FTP, zones de couleur, aiguille, valeur centrée sous la calotte), avec
> bandes fixes **Moteur/Cadence/Assistance** et **Batterie/Autonomie**, titre en bas.
> Nouveau réglage **FTP** (sélecteur **Auto** / 60–400 W) ; l'échelle de la jauge suit
> le FTP réglé, sinon le FTP du profil utilisateur (`getFunctionalThresholdPower`,
> feature-gated, non exposé sur `venusq2`/`epix2pro42mm` → repli **200 W**). Le toggle
> « CyclistPower » a disparu (la puissance est toujours affichée). Les 2 cibles
> (`venusq2`, `epix2pro42mm`) compilent : `BUILD SUCCESSFUL` à `-l 0` **et** `-l 2`.
> **2026-10-08** : app **allégée pour la publication** — l'export du store
> échouait sur `enduro` (28 Ko max) ; coupes A–G (debug, logs, diagnostics,
> assistance morte, `archive/`) → **26668 B sur 32768** (voir entrée
> 2026-10-08 du §7 + pièges #18/#19). L'export de publication est **prêt à
> relancer** ; reste à valider l'ajout de `enduro4`/`approachs724x` au
> `manifest.xml` et un passage sur la montre.
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
- **Permissions** : `BluetoothLowEnergy`, `FitContributor`, `UserProfile`
  (`UserProfile` exigé par le typecheck dès qu'on touche à `Toybox.UserProfile`).
- **Clé de signature** : `developer_key.der` (racine).
- **Jungle** : `monkey.jungle` = `project.manifest = manifest.xml` (rien d'autre).

### Build (vérifié)

```powershell
& "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2\bin\monkeyc.bat" `
  -f monkey.jungle -o "C:\Users\greg\AppData\Local\Temp\opencode\ebike-test.prg" `
  -y developer_key.der -d venusq2 -l 0
```

- `-l 0` et `-l 2` : `BUILD SUCCESSFUL` sur `venusq2` et `epix2pro42mm`
  (vérifié le 2026-09-29 après ajout jauge + FTP).
- Les cibles `epix2pro*` produisent des `.iq` dans `bin/` ; le `.prg` de
  sideload est `bin\ebikedf.prg`.

---

## 2. État fonctionnel actuel

### Agencement écran (`_drawMetrics`, `EbikeField.mc`) — depuis 2026-09-29

Bandes fixes, de haut en bas :

1. **Jauge radiale de puissance** (toujours affichée) : **calotte d'arc
   concentrique au cercle de l'écran** (même centre, rayon
   `min(l,h)/2 - bw/2`, épaisseur `bw = 21`) : l'arc est **concentrique à
   l'écran**, donc son zénith EST le haut du cercle visible → il **touche le bord
   supérieur** (champ = écran pour un data field pleine page), **sans clamp
   `safe.top`**. Calotte **10 h → 14 h** : `θ = 60°` (`a1 = 150°` = 10 h à
   gauche, `a0 = 30°` = 14 h à droite), `f = 0` (0 W) à gauche,
   `f = 1` (2·FTP) à droite, **FTP au zénith** (SDK : 0°=est, 90°=zénith).
   Tracé : `angle(f) = a1 - 2θ·f`, `drawArc(..., ARC_CLOCKWISE, angle(fLo),
   angle(fHi))` (⚠️ le sens est **inversé** par rapport à la version précédente :
   `ARC_CLOCKWISE` depuis `a1`, sinon les zones et l'aiguille sortent à l'envers).
   θ plancher à **55°** (l'adaptatif ne se déclenche plus en pratique).
   **7 segments de largeur ÉGALE** (2/7 de FTP chacun), gauche→droite :
   `gris` (`COLOR_LT_GRAY`), `bleu clair`, `vert clair`, **`jaune` (FTP centré)**,
   `orange`, `rouge`, **`violet`** (`COLOR_PURPLE`). Plus d'encoche FTP.
   **Aiguille en moignon radial** (segment `r-29..r-8`, pen 6) en couleur `fg`
   pointant `model.powerW3s` (**moyenne glissante 3 s**, bornée à [0, 2·FTP]).
   **Valeur remontée À L'INTÉRIEUR de la calotte**, juste sous la portée de
   l'aiguille (plus sous la corde) : `topY = min(corde+1, scy - √((r-37)² -
   demiLargeur²))`, borné en haut par le bandeau d'arc (`scy - r + bw/2 + 4`) et
   en bas par le bas du bandeau jauge. Le bord haut du bloc (label compris) reste
   à ≥ 8 px sous `r-37`, donc **l'aiguille ne traverse jamais les chiffres** ;
   gain mesuré ≈ **40 px vers le haut** en 416×416 (`topY` 110 → ~70).
   Unité `W` + suffixe **`3s`** (FONT_XTINY, même fg, 1 px d'écart) dessinés à
   droite de la valeur quand `showUnit`. Rendu par `drawArc` + `setPenWidth`
   (le SDK 9.2 **n'a pas** `fillArc`).
2. **Bande Moteur / Cadence / Assistance** : cellules égales (toggles §menu).
3. **Bande Batterie / Autonomie** : idem.
4. **Titre** (nom du vélo, « MGU Demo » en démo) en **pied**, **descendu dans
   l'arc bas** (`titleY = max(yTitle, fh - titleH - 2)`) : c'est une bande
   étroite et centrée, donc elle tient là où les bandes larges ne tiennent pas
   (coins ronds) ; largeur bornée à la **corde du cercle** à cette hauteur
   (nom de vélo trop long → troncature `...`).

Sacrifices si hauteur insuffisante : titre, puis bande du bas ; la jauge garde
toujours sa place avec le plancher `_minGaugeH(w, h, showLabels)` = **max** de
— la profondeur de la calotte à θ = 55° + 16 px (≈ **100 px** en 416×416, ≈53 px
en 205×205) ;
— la **hauteur qu'exige la valeur** : `getFontHeight(FONT_NUMBER_MEDIUM) +
labelH + 6`, plafonnée à `h·6/10` pour que les lignes 2/3 ne disparaissent pas
sur un écran court.
Ce 2ᵉ terme garantit que la puissance rend au minimum en **FONT_NUMBER_MEDIUM**
(une taille au-dessus de `FONT_LARGE`), demandé le 2026-10-07. Diagnostic à
l'appui : avant, les lignes naturelles occupaient tout le quota
`avail = h - titleH - minG`, la jauge retombait au plancher (~100–127 px mesuré)
et le fit tombait en `FONT_LARGE` — **la hauteur bloquait, pas la largeur**
(`ww ≥ 80` de marge, `hh < 0`), `FONT_NUMBER_MEDIUM` échouait de 32 à 64 px.
Le terme géométrique garde son rôle d'origine ; l'ancienne constante
`MIN_GAUGE_H = 72` a été **supprimée** car elle ignorait la taille d'écran.
La jauge consomme alors `minG` en priorité (`avail` des lignes en découle) et
le fit se replie encore si même ce plancher ne suffit pas.
Hauteur des bandes 2/3 : chaque bande réclame d'abord sa hauteur **naturelle**
(`_rowBandH(..., budget = h)`) — la fonte n'est **plus bridée par un budget de
90 px**, elle grandit donc avec l'écran et **s'adapte seule au nombre de
métriques activées** (largeur de cellule `w/n`). Si
`row2H + row3H > h - titleH - minG`, le surplus est réparti proportionnellement
puis **chaque bande est re-fitée à la hauteur qu'elle obtient réellement**
(`_rowBandH(..., budget)`, retour **borné au budget**) : le dessin ne peut donc
plus choisir une fonte plus grande que celle réservée.
`_rowBandH` renvoie `maxH + labelH + **8**` (et non +2) — sinon `_drawCell`
re-fit avec `availH = h-6` rejette la plus grande fonte et chaque cellule
secondaire perd **un cran**.

**Puissance affichée = moyenne glissante 3 s** (`model.powerW3s`) : tampon
circulaire de 32 slots / `PW_WINDOW_MS = 3000` dans `EbikeData`, rempli par
`setPower(w)` depuis `Sigma.parseRide` (RX1) **et** `DemoManager.onTick`, moyenne
arrondie `(somme + n/2)/n`, wrap de `System.getTimer()` géré (`now >= t`).
Le champ FIT (`EbikeFitContributor`) continue d'enregistrer `powerW`
**brut** — seul l'écran est lissé. Le suffixe `3s` à côté de l'unité `W` en est
la trace visible.

| Bande | Métrique | Source | Clé de config | Unités |
|---|---|---|---|---|
| 2 | **Motor** (moteur) | RX2 `u16(0)` | `CFG_KEY_METRIC_MOTOR_POWER` | W |
| 2 | **Cadence** | RX1 `d[9]` | `CFG_KEY_METRIC_CADENCE` | rpm |
| 2 | **Assist** (mode) | RX7 `d[0]` | `CFG_KEY_METRIC_ASSIST` | (aucune) |
| 3 | **Battery** | RX3 `d[0]` | `CFG_KEY_METRIC_BATTERY` | % |
| 3 | **Range** (autonomie) | RX3 `u16(6)` | `CFG_KEY_METRIC_RANGE` | km |

- **La vitesse n'est plus affichée** (métrique « Speed » retirée). `RX1 Speed`
  reste **décodé** dans `model.speedKmh` (démo / log), mais aucun affichage.
- État « **En attente…** » : `!demoMode && model.batterySoc == null &&
  timer - lastUpdate > 10000` (début du chemin de rendu `onUpdate`).
- **FTP** : `_resolveFtp()` = réglage (`ftpOverride()` > 0) → sinon
  `EbikeConfig.autoFtp()` = FTP du profil (`getFunctionalThresholdPower`,
  feature-gated + try/catch + `instanceof Number`, cache statique
  `_profileFtp`) → sinon **200 W**. La résolution **« auto » est partagée** :
  le champ ET le menu/la roue appellent la même `autoFtp()`, donc l'échelle de
  la jauge et la valeur affichée près de « Auto » ne peuvent pas diverger.
- **Fonts** : `_fitValueFont` (`EbikeField.mc`) = échelle **order-indépendante
  du plus grand font qui rentre** : candidats `FONT_NUMBER_HOT/MILD/MEDIUM` puis
  `FONT_LARGE/MEDIUM/SMALL/XTINY`. `_fontLetter` mappe le font retenu.
  ⚠️ Le SDK n'expose **pas** de `FONT_NUMBER_THIN_HUGE/LARGE` — ne pas en inventer.
- ⚠️ **Invocation de classe depuis la jauge** : le fit de la valeur est calculé
  dans `_drawMetrics` puis **passé en paramètre** à `_drawPowerGauge(...,
  gfit)` (9ᵉ paramètre). Ne pas réintroduire un appel `_fitValueFont` DANS la
  jauge : sur le **simulateur**, le VM émet un **« Stack Overflow » / Failed
  invoking \<symbol\>** à l'**entrée** de `_fitValueFont` quand celle-ci est
  invoquée depuis le cadre `_drawPowerGauge` (8 paramètres dont `Dc`+
  `EbikeData`+`Dictionary`), alors que la même invocation depuis `_drawMetrics`
  / `_rowBandH` fonctionne. Diagnostic 2026-09-29 via `monkeydo` : print d'entrée
  jamais atteint, crash avant le corps de la fonction.

### Menu réglages (`EbikeSettings.mc`)

Toggles : Demo, Libellés, **MotorPower**, Cadence, Assistance, Battery, Range
(le toggle **CyclistPower a disparu** : la jauge l'affiche toujours ; le toggle
**Debug a supprimé le 2026-10-08** pour la publication, voir §8).
Item **FTP** : `MenuItem` id `CFG_KEY_FTP`, sous-libellé « NN W » ou — quand le
réglage est sur **auto** — **« Auto <valeur réellement résolue> W »**
(`_ftpLabel(ftp)` : `ftp <= 0` → `FtpAuto + " " + autoFtp() + " " + W`, ex.
*Auto 203 W*), demande du 2026-10-07. La roue du `WatchUi.Picker` (81 items =
0..400 W par pas de 5, `0` = **Auto**) affiche **le même `_ftpLabel`** : l'item
`Auto` y porte donc aussi la valeur résolue — voir `EbikeFtpPicker.mc`. Le
**niveau d'assistance a été retiré du menu** : `onAssistSelected`,
`_assistLabel`, `_assistItem` et le bloc commenté ont été **supprimés le
2026-10-08** (`archive/Assist.mc.bak` conserve la logique). `_ble` a disparu du
menu (le constructeur ne prend plus d'argument) ; seule la **restauration au
démarrage** vit encore (`EbikeField` → `BleManager.setAssistLevel`).

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
  `setAssistLevel`. **Jonct. 2026-10-08** : log BLE supprimé
  (helpers `_decoded*`, `_charTag`, `_hex(_C)`, `_appendHex`, `line`, `_pendingLog`
  et le paramètre `log` des 2 queue-functions ont disparu ; plus aucun
  `System.println` dans tout le projet).
- `Sigma.mc` — parseurs `parseRide` / `parseMotor` / `parseBattery` / `parseAssist`.
- `EbikeData.mc` — modèle partagé (`_model`). **Jonct. 2026-10-08** : les 12
  champs de diagnostic (`profileStatus`, `serviceFound`, `rxCharFound`,
  `cccdOk`, `fd6d*`, `rxCount`, `rxOtherCount`, `lastRxHex`/`lastRxOtherHex`,
  `lastError`…) supprimés.
- `EbikeConfig.mc` — clés de stockage + accès (`ftpOverride()`, **`autoFtp()`**
  = résolution « auto » partagée champ ↔ menu, cache `_profileFtp`).
- `EbikeSettings.mc` — menu réglages (Menu2) + delegate.
- `EbikeFtpPicker.mc` — roue de sélection FTP (`PickerFactory` + `PickerDelegate`).
  ⚠️ **fond du `Picker` = NOIR, texte = BLANC** (comme l'échantillon SDK
  `samples/Picker`, qui force `COLOR_WHITE` + `dc.clear()` noir). Un
  `COLOR_BLACK` sur le titre/les items rend la roue **vide à l'écran** (texte
  noir sur fond noir) → corrigé 2026-09-29.
- `EbikeFitContributor.mc` — champs FIT.
- `DemoManager.mc` — données simulées (`motorPowerW`, `assistMode` cyclique 1..4).

**Archive** (`archive/`, **renommé `.mc.bak` → hors compilation depuis
2026-10-08**) : `Bcp.mc.bak`, `Cap.mc.bak`, `Pdo.mc.bak`, `Assist.mc.bak`.
⚠️ ces 4 classes mortes coûtaient **5,1 Ko** au PRG (monkeyc ne « strip » pas) —
voir piège #18.

**Docs** : `docs/PROTOCOL.md` (protocole), `docs/BUILD.md` (compilation),
`docs/QUICKSTART-FR.md` / `docs/QUICKSTART-EN.md` (guide utilisateur),
`docs/HANDOFF-NOUVELLE-SESSION.md` (ce fichier).

---

## 5. Ce qu'il reste à faire (pistes, non bloquant)

1. **RX5 non décodé** : jamais exploité. Si utile un jour, il faut le
   **réintroduire** (le log BLE a été supprimé le 2026-10-08 — les 3 octets nuls
   des slots d'endurance/recovery sont interprétés comme 0) ; unités à confirmer
   (distance 57000 = m ?, 2ᵉ u32 = temps ?) — cf. `archive/Bcp.mc.bak`.
2. **RX2 `d[9]` (assist %)** : non mappé. Le champ `model.assistPercent` existe
   (inutilisé) — on peut l'alimenter si on veut afficher le **% d'assistance** en
   plus du **mode** (RX7).
3. ~~**Puissance moteur en FIT**~~ : **fait** — champ id10 `motor_power`
   (`nativeNum=82`), voir §FIT.
4. ~~**Enregistrement FIT quand le champ n'est pas affiché**~~ : **fait** —
   heartbeat + `fit.update` portés par le flux RX (`onCharacteristicChanged`),
   moyennes gated à 1 Hz, voir §FIT. Reste à valider sur le terrain + confirmer
   que `onTimer*` arrive page cachée.
5. **RX4/RX6/RX8** : jamais vus ; le log BLE qui les montrait brut a été
   supprimé (2026-10-08) — réintroduire uniquement si besoin.
6. ~~**Erreur typecheck stricte (`-l 2`)**~~ : **fait** — `_assistItem` nullable
   (2026-09-29), + cette session la jauge/FTP compilent en `-l 2` sur
   `venusq2` et `epix2pro42mm`.
7. **`Speed` string** et `CFG_KEY_ASSIST_LEVEL`/`assistLevel()` : reliquats
   inutilisés, sans effet — à nettoyer si on veut.
8. **FTP « Auto » sur appareils non supportés** : `getFunctionalThresholdPower`
   n'est documenté que sur fenix 8, Venu 4/X1, FR 570/970, Edge 8xx/5xx, Enduro 3,
   vivoactive 6, D2 Mach 2 Pro — pas `venusq2` ni `epix2pro*`. Le repli 200 W
   s'applique ; à valider terrain (la jauge reste lisible).
9. **Jauge au contour supérieur** : arc concentrique à l'écran, couronne calée
   sous `safe.top`. Corrigé le 2026-09-29 (fit de valeur sorti de la jauge, voir
   §6.3) ; rendu vérifié sur le simulateur (plusieurs frames sans crash).
   Vérifier le rendu épix2pro42mm (dégagement de la lunette,
   aiguille en moignon lisible) sur simulateur/terrain.

---

## 6. Pièges / points d'attention

1. **Un seul `BleManager` par exécution, et jamais depuis une vue** :
   `BluetoothLowEnergy.registerProfile()` écrit dans une table de profils GATT
   bornée de l'appareil, et une app ne peut avoir qu'un delegate BLE. Un
   `new BleManager(...)` supplémentaire **re-enregistre les mêmes UUID** et
   peut lever une exception — c'est ce qui a tué le data field sur un Edge 1030
   (fw 13.81, ERA 2026-09-29, `BleManager.initialize` ← `EbikeField._ensureMode`
   ← `onUpdate`), parce que `_ensureMode()` tournait dans le chemin de rendu.
   Règle : passer par `BleManager.getShared(model)`, qui enregistre une seule
   fois, contient l'exception, espace 3 tentatives de 30 s puis renvoie `null`.
   Un `null` doit afficher `Rez.Strings.BleError`, jamais remonter. Les 3
   anciens sites (`_ensureMode`, `onStart`, `getInitialView`) ont été corrigés.
   Rappel Monkey C : un `private` n'est pas accessible depuis une méthode
   `static` (crash du compilateur) — passer par un accesseur public.
2. **Les 2 profils GATT ne s'enregistrent pas au même risque** :
   `initialize()` traite le profil Sigma/AD (`PROFILE_INDEX_REQUIRED`) en
   obligatoire — son exception remonte vers `getShared()` — et le profil legacy
   BCP (`5e8597aa`, heartbeat TX) en « best effort » : un refus met
   `_legacyProfileOk = false` et les données Sigma fonctionnent quand même.
   Les deux étaient dans la même boucle, si bien qu'un appareil refusant la
   2ᵉ définition perdait aussi le profil qui porte toutes les données — observé
   sur un **Edge Explore 2 fw 31.33** (ERA « System Error », 2 occurrences le
   2026-09-25, `initialize:68` ← `onStart:692`). Le profil Sigma/AD garde ses
   **8 caractéristiques RX1..RX8** : rien n'a été réduit.
3. **Une inscription peut aussi échouer sans lever** : `onProfileRegister` reçoit
   un statut non nul et le log (`BleManager: prof FAIL st=…`), distinct de
   l'exception. Les deux cas existent.
4. **`stop()` ne détruit pas le manager** : il coupe le trafic (`_active = false`,
   callbacks ignorés) mais garde l'objet et ses profils enregistrés ; revenir du
   mode démo fait un `startScan()`, pas un nouvel enregistrement.
5. **Erreur typecheck stricte (`-l 2`) corrigée le 2026-09-29** :
   `source/EbikeSettings.mc:9: Member '$.EbikeSettingsMenu._assistItem' may not
   be initialized but does not accept Null.`
   Cause : `_assistItem` déclaré non-nullable, seule affectation dans le code
   commenté. Corrigé en `private var _assistItem as WatchUi.MenuItem?;` + garde
   null dans `onAssistSelected`. Le build `-l 2` passe maintenant sur edge1030
   et edgeexplore2 : à utiliser pour vérifier la nullabilité du nouveau code.
6. **`Rez.Strings.X` est un ResourceId, pas une String** : tout affichage passe
   par `WatchUi.loadResource(Rez.Strings.X)`.
7. **Localisation** : chaque fichier `resources-<lang>/strings.xml` doit
   déclarer **tous** les ids (même valeur que l'anglais), sinon
   « String id undefined for language ». Codes : `fre` (pas `fra`), `deu`, `ita`.
8. **RX2 `d[9]` ≠ RX7 mode** : ne pas confondre le % d'assistance moteur (RX2)
   avec le mode d'assistance (RX7). Le log RX2 le note `assistNN%`.
9. **Trames de tailles fixes** : le dispatch teste `value.size()` (10/10/12/2) —
   une trame de taille inattendue est ignorée (mais loggée en hex).
10. **Chaque `EbikeDataField` crée son `EbikeFitContributor`** (11 `createField`
    liés à l'instance du champ, non mutualisables). Même famille de risque « table
    qui se remplit » que BLE, mais aucun backtrace ERA ne pointe là : à
    surveiller, pas à corriger dans l'immédiat.
11. **Lire un fichier en entier avant de l'éditer** ; éviter les lectures
    partielles parallèles (source d'incohérences dans une ancienne session).
12. **`UserProfile` exige la permission (manifest)** : dès qu'on utilise
    `Toybox.UserProfile`, ajouter `<iq:uses-permission id="UserProfile"/>`
    (le typecheck `-l 2` le refuse sinon). `getFunctionalThresholdPower` est
    feature-gated (`UserProfile has :getFunctionalThresholdPower`) + try/catch +
    `instanceof Number` : nécessaire car l'API n'est pas exposée sur toutes les
    cibles au runtime, même si elle compile partout (`api.mir`).
13. **`WatchUi.PickerFactory` : signatures à respecter exactement** —
    `getValue(item) as Object or Null` et `getDrawable(item, isSelected) as
    Drawable or Null` (pas `Number`/`Drawable`) : `-l 2` refuse l'override sinon
    (« Cannot override ... with a different return type »). `WatchUi.NumberPicker`
    ne convient pas aux watts (modes figés : poids/distance/temps…) — utiliser
    `Picker` + `PickerFactory`, `:defaults => [valeur/5]`.
14. **Simulateur : le BLE n'existe pas** — avec le mode démo OFF, un data field
    BLE **crash à `onStart`** (`BleManager.getShared:152`, `new BleManager`)
    en **« Symbol Not Found »** (natif `registerProfile` absent du sim, **non
    interceptable** par try/catch) : champ blanc + « app crashed ». Sur le sim :
    **activer le Mode démo**. Sur la montre réelle : aucun problème.
15. **Simulateur : « Stack Overflow » au rendu corrigé le 2026-09-29** — l'écran
    blanc en démo était un crash VM du sim (voir §2) : `_fitValueFont` invoquée
    depuis `_drawPowerGauge` → à l'entrée de la fonction, « Stack Overflow /
    Failed invoking <symbol> » (cadre `onUpdate:226←_drawMetrics←
    _drawPowerGauge`). Fix structurel : le fit est calculé dans `_drawMetrics`
    (mêmes appels, ça passe) et passé en paramètre à la jauge. Ne pas remettre
    d'appel de classe dans `_drawPowerGauge`.
16. **Budget de cadres VM partagé (2026-10-07)** : la limite n'est pas
    « `_drawPowerGauge` appelle une classe », c'est la **profondeur cumulée**
    `onUpdate + _drawMetrics + cadre + appelé`. Ajouter 3 `var` locaux dans
    `_drawMetrics` a **déplacé** le crash de la jauge vers la chaîne la plus
    profonde `_drawValueRow → _drawCell → _fitValueFont` (« Stack Overflow /
    Failed invoking \<symbol\> » à l'entrée de `_fitValueFont`). Règles
    appliquées et à conserver :
    - `_drawPowerGauge` **n'invoque aucun appel de classe**, pas même `_fmt0` :
      la chaîne formatée est portée par `gfit[:value] = _fmt0(...)` posé dans
      `_drawMetrics` ;
    - `_drawCell` est maintenu **volontairement maigre** (11 locaux au lieu de
      19 : `lf/uf/total/ux/uy/blockH/vh` inlinés) car il est au fond de la
      chaîne ; `_fitValueFont` aussi (`unitFont` inliné) ;
    - toute évolution de `_drawMetrics` doit **compenser** ses locaux ailleurs,
      sinon le prochain crash apparaîtra au premier appel profond venu.
    Diagnostic : patch démo (`isDemo() → return true`), `monkeyc -l 2` puis
    `monkeydo`, log `CIQ_LOG.YML` vidé avant le lancement (un run sans crash y
    laisse **0 octet**).
17. **Sortie de debug invisible : la seule voie lisible est le numéro de
    ligne d'une exception (2026-10-07)** — `System.println` **ne donne rien**
    dans le simulateur : `CIQ_LOG.YML` ne contient que des blocs d'**erreur**
    (le message d'une `Exception` déclenchée par `throw` n'y figure **pas**,
    seulement `Error:` + la **pile avec numéro de ligne**), et rediriger la
    stdout du `simulator.exe` (`Start-Process -RedirectStandardOutput`) reste
    à 0 octet. Recette utilisée : `throw new InvalidValueException("…")` posé
    **sur une ligne dédiée par cas** dans `_drawMetrics` (exemple : un `if`
    par fonte, un `if` par tranche de valeur) → le numéro de ligne remonté
    par le log code la donnée. `throw ("…")` et `throw diag` sont **refusés à
    la compilation** (« Cannot throw object of type String ») ; il faut un
    objet `Lang.*Exception`. Attention : ce throw tue le premier frame, donc
    il ne doit pas rester dans une version livrée.
18. **`archive/` EST compilé par monkeyc (2026-10-08)** : le source path par
    défaut couvre **tout le dossier projet**, pas seulement `source/`. Les 4
    classes mortes (`Assist`, `Bcp`, `Cap`, `Pdo`) rentraient donc dans le PRG
    et pesaient **5,1 Ko** alors que le moteur ne les « strip » pas. Exclusion :
    **renommer `*.mc` → `*.mc.bak`** (gardées pour référence, plus compilées).
    Tout `.mc` qui traîne dans le projet est compilé — attention aux copier-coller.
    Symptôme qui l'a fait découvrir : erreur de compile sur `archive/Cap.mc:27`
    `:isDebug` alors qu'aucun code ne référençait `Cap`.
19. **`strings.xml` : les 4 fichiers de langue doivent rester cohérents + le
    FIT référence des chaînes (2026-10-08)** : supprimer un id dans une langue
    et pas dans l'autre → « String id undefined for language DEFAULT/FRENCH/… ».
    Et `resources/fitcontributions.xml` référence `CyclistPower`, `AvgPower`,
    `AvgCadence`, `MinBattery`, `Rpm`, `Percent`, `Km`, `Mode` → les
    supprimer fait échouer le build. (Id retirés pour la publication :
    `Debug`, `Speed`, `NothingSelected`, `AssistLevel`, `AssistOff`. ⚠️ manipuler
    les fichiers localisés en UTF-8 : un aller-retour via la console PowerShell
    (codepage) double-encode les accents — recette sûre : extraire via
    `cmd /c "git show HEAD:<path> > out"` puis éditer les lignes.)

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
- **2026-09-29** : 2 crashs ERA tierces corrigés —
  (a) data field, **Edge 1030** fw 13.81, « Unhandled Exception » (1 occurrence),
  `initialize:68` ← `_ensureMode:110` ← `onUpdate:118` ;
  (b) **Edge Explore 2** fw 31.33, « System Error » (2 occurrences),
  `initialize:68` ← `onStart:692` — même appel, premier enregistrement de
  l'exécution, donc table GATT de l'appareil ou pile BLE en cause.
  Correctifs : `BleManager` singleton via `getShared()`, exception contenue +
  3 tentatives espacées, callbacks inertes après `stop()`, **profils Sigma/AD
  obligatoire vs legacy BCP best effort**, état « BLE indisponible »
  (`Rez.Strings.BleError`, 4 langues), `_assistItem` nullable. Le profil Sigma
  garde ses **8 caractéristiques RX1..RX8** : rien n'a été réduit.
  Non publié : la 0.0.4 du store reste vulnérable.
- **2026-09-29** : jauge radiale de puissance + réglage FTP. Nouvelles bandes
  (jauge, Moteur/Cadence/Assistance, Batterie/Autonomie, titre en bas) ;
  `EbikeFtpPicker.mc` (roue Auto/60–400 W par pas de 5) ; `CFG_KEY_FTP`/
  `ftpOverride()` ; repli FTP : réglage > profil (`getFunctionalThresholdPower`
  feature-gated, cache `_profileFtp`) > 200 W ; suppression du toggle
  CyclistPower (`CFG_KEY_METRIC_POWER`) ; permission `UserProfile` ; docs FR/EN
  mises à jour. Build `-l 0` et `-l 2` OK sur `venusq2` + `epix2pro42mm`.
- **2026-09-29 (suite)** : **écran blanc simulateur corrigé**. Cause identifiée
  via `monkeydo`/log sim : **« Stack Overflow » du VM à l'entrée de
  `_fitValueFont`** quand invoquée depuis `_drawPowerGauge` (crash
  `onUpdate:226←_drawMetrics:351←_drawPowerGauge:453←_fitValueFont:585`,
  part 006-B4314-00 FW 23.16, API 5.2.0 — le slot epix2pro42mm de l'utilisateur).
  Fix : `_drawMetrics` calcule le fit et le passe à la jauge (9ᵉ paramètre,
  `gfit`) ; vérifié sur le sim : plusieurs frames successives sans crash (démo
  forceé). `Math.acos` non en cause (jamais atteint). Piège sim #14 (BLE OFF)
  documenté : slot venusq2 avec démo OFF → crash `getShared` fatal (hors champ
  du bug).
- **2026-09-29 (fin de soirée)** : jauge retouchée selon le rendu simulateur —
  (1) **colle au bord** : bord externe du trait à `y=0` (`r = screenR - bw/2`,
  `bw` 9→14, plus d'anneau underlay), couronne à `safe.top` sur écrans ronds
  sans double-décote (`scy - top - bw/2`, et non `scy - safe.y - top` ;
  `safe.y` vaut déjà `top`) ; (2) **couleurs** : rampe 7 zones
  `BLEU/BLEU_FONCÉ/VERT_FONCÉ/VERT/YELLOW/ORANGE/RED` (0–0.40/0.40–0.70/
  0.70–0.85/0.85–1.15/1.15–1.40/1.40–1.70/1.70–2.00), le bleu n'occupe plus
  55 % de l'arc, FTP centré dans l'apex vert ; (3) **encoche FTP supprimée**
  (l'apex vert suffit, un trait central faisait « bug ») ; aiguille `r-22..r-8`
  pen 4 (→ `r-29..r-8` pen 6 le 2026-10-01, +50 % / +50 %). ⚠️ `COLOR_LT_BLUE`/`COLOR_LT_GREEN` **n'existent pas** en CIQ —
  palette réelle vérifiée dans `api.mir` : `COLOR_BLUE`/`COLOR_DK_BLUE`/
  `COLOR_DK_GREEN`/`COLOR_GREEN`/`COLOR_YELLOW`/`COLOR_ORANGE`/`COLOR_RED`.
  Build `-l 2` OK sur `venusq2` + `epix2pro42mm`, rendu vérifié sur le sim
  (démo ON, 45 s sans crash).
- **2026-09-29 (nuit)** : 5 corrections de retour utilisateur — (1) **couleurs**
  → ramp `gris / bleu clair / vert clair / jaune / orange / rouge / violet`
  (`LT_GRAY`, `BLUE`, `GREEN`, `YELLOW`, `ORANGE`, `RED`, `PURPLE` — tous
  vérifiés dans `api.mir`), bornes 0–0.40/0.40–0.70/0.70–0.85/0.85–1.15/
  1.15–1.40/1.40–1.70/1.70–2.00 (jaune au zénith) ; (2) **arc collé au bord
  haut** : clamp couronne `safe.top` **supprimé** (l'arc est concentrique au
  cercle d'écran, son zénith EST le bord visible) ; (3) **titre descendu** dans
  l'arc bas avec largeur bornée à la corde du cercle ; (4) **fonte secondaire
  +1 cran** : `_rowBandH` renvoie `+8` au lieu de `+2` (sinon `_drawCell`
  re-fit à `h-6` et rejette la plus grande fonte) ; (5) **picker FTP vide** :
  cause = `COLOR_BLACK` sur fond de `Picker` **noir** → texte invisible,
  `COLOR_WHITE` (titre + items). Build `-l 2` OK, run sim sans crash.
- **2026-09-29 (nuit, v2 jauge)** : retour simulateur — (1) **sens inversé** :
  zones et aiguille sortaient à l'envers (gris à droite, aiguille basse à
  droite). Corrigé en **miroir** : `angle(f) = a1 - 2θ·f` (f=0 → gauche) +
  `drawArc(..., ARC_CLOCKWISE, ...)` (au lieu de `ARC_COUNTER_CLOCKWISE`
  depuis `a0`) ; aiguille sur la même formule. (2) **épaisseur** : `bw` 14 → **21**
  (≈ +50 %). (3) **angle** : `θ` 61° → **60°** = exactement **10 h → 14 h**
  (`a1`=150°=10 h, `a0`=30°=14 h), plancher 35° → **55°** pour que la calotte
  10 h–14 h reste garantie. (4) **segments égaux** : les 7 zones font désormais
  2/7 de FTP chacune (avant : vert 0.15 trop petit, gris 0.40 trop large) ;
  tableau `zoneColors[]` indexé 0..6 au lieu d'un tableau de dictionnaires.
  `a0` supprimé (gisant). Build `-l 2` OK `venusq2` + `epix2pro42mm`, run sim
  sans crash.

- **2026-10-07** : trois retours utilisateur, tous en place —
  (1) **chiffre remonté dans la calotte** (sous la portée de l'aiguille, plus
  sous la corde) : `topY = min(corde+1, scy - √((r-37)² - demiLargeur²))`,
  né à ≈70 px au lieu de 110 en 416×416, garde-fous haut (`scy - r + bw/2 + 4`)
  et bas (bas du bandeau jauge) ; aiguille **inchangée** (`r-29..r-8`, pen 6) ;
  (2) **polices lignes 2/3 dynamiques** : `_rowBandH(..., budget = h)` remplace
  le budget magique 90, plancher de jauge `_minGaugeH(w,h)` (calotte-aware)
  remplace `MIN_GAUGE_H = 72`, répartition proportionnelle + re-fit à la
  hauteur obtenue ; (3) **moyenne glissante 3 s** : `EbikeData.setPower()` +
  tampon 32 slots / 3000 ms (wrap `getTimer()` géré), appelé par
  `Sigma.parseRide` **et** `DemoManager.onTick`, affiché par la jauge et
  l'aiguille avec suffixe **`3s`** ; le FIT reste au **brut** (`powerW`).
  ⚠️ **Piège #16 découvert en cours de route** : les 2 premières versions
  crashaient en « Stack Overflow / Failed invoking \<symbol\> » — le 1ᵉʳ dans
  `_fmt0` appelé depuis la jauge, le 2ᵉ (après +3 locaux dans `_drawMetrics`)
  à l'entrée de `_fitValueFont` via `_drawValueRow → _drawCell`. Fix :
  `gfit[:value] = _fmt0(...)` posé dans `_drawMetrics` (la jauge n'appelle
  **aucun** appel de classe), `_drawCell` allégé de 8 locaux, `_fitValueFont`
  de 1. Patch démo (`isDemo() → return true`) pendant les tests, reverti par
  `git checkout -- source/EbikeConfig.mc`. Build `-l 2` OK `venusq2` +
  `epix2pro42mm`, run sim **démo 30 s sans crash sur les 2 cibles** (log
  `CIQ_LOG.YML` vidé avant = 0 octet) ; run **sans** démo = crash connu
  piège #14 (BLE absent du sim). Rendu **non** vérifié visuellement par
  l'agent (pas de capture lisible) : reste un œil utilisateur.

- **2026-10-07 (suite)** : retour simulateur epix Pro 51 mm « pas de crash, pas
  de bug » + demande : **fonte de la puissance cycliste un cran au dessus**.
  Mesure (voir piège #17, `throw` + numéro de ligne) : le fit retenait
  **`FONT_LARGE`** — ni largeur ni largeur du bloc, **la hauteur** : les lignes
  2/3 prenaient tout le quota `avail`, la jauge retombait au plancher
  (`gh ∈ [100,128)` mesuré) et `FONT_NUMBER_MEDIUM` échouait de **32 à 64 px**
  (marge largeur, elle, ≥ 80 px). Correctif : `_minGaugeH(w, h, showLabels)`
  rend désormais **max(calotte, `getFontHeight(FONT_NUMBER_MEDIUM) + labelH +
  6`)** plafonné à `60 %` de la hauteur — les lignes sont re-fittées sur ce qui
  reste (`avail` suit `minG`), donc la puissance rend **au minimum en
  FONT_NUMBER_MEDIUM** (une taille au-dessus de `FONT_LARGE`), et le fit se
  replie encore si le plancher ne suffit pas. Revérifié au `throw` : fonte
  observée = **FONT_NUMBER_MEDIUM** ; runs démo sans crash sur
  **epix2pro51mm** et **venusq2** (log 0 octet) ; `monkeyc -l 2` OK
  `venusq2` + `epix2pro42mm` + **`epix2pro51mm`** (cible ajoutée, c'est la
  montre de l'utilisateur). Capture d'écran obsolète supprimée par
  l'utilisateur (reste ` D` dans `git status`, à inclure au commit).

- **2026-10-07 (suite 2)** : menu réglages — quand FTP est sur **auto**, afficher
  **à côté la valeur réellement résolue** (demande : « quand FTP <auto> est
  sélectionné, afficher à côté la valeur du FTP »). La résolution a été
  **extraite du champ** : `EbikeConfig.autoFtp()` (profil `getFunctionalThresholdPower`
  feature-gated + try/catch, cache statique `_profileFtp`, repli **200 W**) est
  désormais l'unique source, consommée par `_resolveFtp()` (champ) et par
  `EbikeSettingsMenu._ftpLabel()` (sous-ligne du menu **et** item `Auto` de la
  roue, via `$.EbikeSettingsMenu._ftpLabel(...)` dans
  `EbikeFtpPickerFactory.getDrawable`) → « **Auto 203 W** » aux deux endroits,
  jamais deux valeurs différentes. `_readProfileFtp`/`_profileFtp` et les
  imports `Activity`/`UserProfile` ont quitté `EbikeField.mc`. Contrôles :
`monkeyc -l 2` OK `venusq2` + `epix2pro42mm` + `epix2pro51mm`, run démo sans
  crash (log 0 octet) avec `isDemo()` patché en `true`, patch reverti.

- **2026-10-08 — réduction mémoire pour l'export de publication** : l'export du
  store échouait sur `enduro` (« memory below requirement », rapport de
  l'outil : 32811 B pour 32768) ; SDK local 9.2.0 métre différemment (38170 B
  pour la même source) → ce qui compte = les **deltas** (mesure :
  `monkeyc.bat -d enduro -f monkey.jungle -o … -y developer_key.der
  --build-stats 1`, marge lisible à « Total PRG Size »).
  Coupes successives (validées via builds enduro + `-l 2` + run démo log
  0 octet) :
  - **A. Écran debug supprimé** : toggle `CFG_KEY_DEBUG`, `isDebug()`,
    `_printDebugInfo`, `_lastDebugLine`, `_fontLetter`, `_obscureString`,
    `_lastValueFont` (champ + assignations), `Rez.Strings.Debug`. ≈1,6 Ko.
  - **B. 26 `System.println` supprimés** (24 `BleManager`, 1 `EbikeConfig`,
    1 `EbikeSettings`). ≈0,5 Ko.
  - **C. Log BLE supprimé** : `_decoded*`, `_charTag`, `_hex`, `_hexC`,
    `_appendHex`, `line`, `_pendingLog`, paramètre `log` des 2 queue-functions.
    ≈0,6 Ko.
  - **D. Diagnostiques supprimés** : 12 champs de `EbikeData` (dont `lastError`,
    `rxCount`, `rxOtherCount`, `lastRxHex`) + leurs écritures/`reset()` dans
    `BleManager` (dont les 10 `lastError`, le `profileStatus`, `serviceFound`,
    `rxCharFound`, `cccdOk`, `fd6d*`). ≈0,5 Ko.
  - **E. Code assistance mort supprimé** : `_assistItem`, `_assistLabel`,
    `onAssistSelected`, branche `else` du delegate, `_ble` du menu
    (`onAssistSelected` persistait le niveau au tap, alors que la
    **restauration au démarrage** suffit — `EbikeField` → `setAssistLevel`) ;
    `Rez.Strings.AssistLevel/AssistOff` retirés.
  - **F. Chaînes mortes** : `Debug`, `Speed`, `NothingSelected` retirés des
    4 `strings.xml` (**pas** `CyclistPower/AvgPower/AvgCadence/MinBattery/
    Rpm/Percent/Km/Mode` : `fitcontributions.xml` les référence → build KO —
    piège #19).
  - **G. `archive/` exclu** (piège #18) : `*.mc` → `*.mc.bak` — 4 classes
    mortes compilées quand même, **5,1 Ko**.
  Taille `enduro` finale : **26668 B** (Data 6346 + Code 20322) sur 32768
  (avant : 38170). Contrôles : `monkeyc -l 2` OK `venusq2` +
  `epix2pro42mm` + `epix2pro51mm`, run démo (patch `isDemo` + revert) log
  0 octet ; **plus aucun `System.println` dans le projet**, le seul canal de
  diagnostic reste le `throw` (piège #17).
  NB : l'outil d'export publié a ajouté **3 produits au `manifest.xml`**
  (`approachs7243mm`, `approachs7247mm`, `enduro4`) lors de la tentative — à
  valider avec l'utilisateur avant commit (le `enduro4` ajoute une cible à
  contrôler).
