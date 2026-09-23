# Protocole BLE eBike Flyon (Pinion MGU) — Sigma / FD6D (flux réel) + archive BCP/CAP/PDO

> **FLUX RÉEL (2026) :** les données du vélo arrivent via le **service Sigma**
> `0000fd6d-…` (lib `com.sitael.SERIAL_SIGMA_EBIKE_Lib`), décodé par
> `source/Sigma.mc`. Les trames arrivent sur les caractéristiques
> `00000001..08` (« RX1..RX8 », voir §Sigma). La pile **BCP/CAP/PDO**
> (`5e8597aa-…`, `archive/Bcp.mc`, `Cap.mc`, `Pdo.mc`) n'est plus compilée pour
> la réception : c'est un chapitre d'archive (§ archive) — il ne reste **vivant**
> que le heartbeat TX en trame BCP single-frame sur `5e8597ac`.

Document de référence pour l'implémentation Garmin Connect IQ (data field) de la
réception des données d'un moteur Flyon (Pinion MGU) via Bluetooth Low Energy.
Rétro-conçu à partir de l'APK `ch.biketec.mobile.application.dev.apk`
(classes `ch.biketec.sdk.*`, `ch.flyer.mobile.*`, `com.sitael.SERIAL_SIGMA_EBIKE_Lib`).

> **MISE À JOUR TERRAIN (observé 2026, vélo réel « H5IVM02776 ») :** les
> données arrivent sur le service `0000fd6d-…`, caractéristique
> `00000001-abab-4499-b9d7-d0efc0d06477` (RX1) et `00000003-…` (RX3), en
> trames de **10 / 12 octets** (~1,3 s) — **PAS** sur le service `5e8597aa-…` :
>
> - `descwrite` CCCD du RX `5e8597ab` échoue : **status=18** ;
> - Aucune notification ne remonte sur `5e8597ab` ;
> - Le heartbeat sur TX (`5e8597ac`) est écrit correctement (status=0) mais ne
>   déclenche aucun flux BCP sur RX.
>
> Exemples RX1 (10 octets, `u.ch.24`), RX3 (12 octets) :
>
> ```
> RX1 2f 00 04 00 00 00 00 00 00 4e   <- 4,7 km/h, 4 m, 0 W, 0 Nm, 78 rpm
> RX1 39 00 05 00 00 00 14 00 15 38   <- 5,7 km/h, 5 m, 20 W, 21 Nm, 56 rpm
> RX3 62 40 01 32 d2 80 72 00 05 00 80 1c   <- 98 %, 114 km, 128 temp.
> RX3 62 4a 01 32 d2 80 72 00 05 00 80 1c
> ```
>
> Le data field n'affiche plus de diagnostic à l'écran : le flux est décodé
> directement en données et loggé en une ligne compacte par trame
> (`t=… RX1 10B <hex> <x>.xkm/h 0.0km 0W 0Nm 0rpm`).

---

## Sigma — service `0000fd6d` (flux réel)

### S.1 GATT du service Sigma

| Rôle | Valeur |
|---|---|
| Service (annoncé en AD, 16-bit `0xFD6D`, base « Bluetooth Base UUID ») | `0000fd6d-0000-1000-8000-00805f9b34fb` |
| Caractéristiques données RX1..RX8 | `00000001..08-abab-4499-b9d7-d0efc0d06477` |
| Caractéristiques écriture (0B / 0E, write-only) | `0000000b-…`, `0000000e-…` |

Chaque caractéristique `0000000N` porte **un** type de message Sigma. Le data
field enregistre un profil AD avec les 8 caractéristiques notify (CCCD) et
sonde la présence de chaque `0000000N` après connexion (`_enableFd6dNotifications`).

### S.2 Correspondance RX1..RX8 ↔ messages Sigma

Le mapping est corrélé sur le terrain : **RX1 = SIGMA_LIVE_RIDE_INFORMATION**,
**RX2 = SIGMA_LIVE_MOTOR_INFORMATION**, **RX3 = SIGMA_LIVE_BATTERY_INFORMATION**,
**RX5 = SIGMA_BIKE_DIAGNOSTIC_INFORMATION** et **RX7 = SIGMA_BIKE_ASSISTANCE**
(les cinq observés) ; le reste suit l'énumération `SIGMA_MESSAGE_ID_TE` de la
lib Sitael (`TYPE_BLE_EBIKE_SERVICE.java`) : `RXn ↔ SIGMA_MESSAGE_ID (n-1)`.

| RX / char | ID | Message (Sitael) | Taille | Statut |
|---|---|---|---|---|
| RX1 `01` | 0 | SIGMA_LIVE_RIDE_INFORMATION | 10 | ✅ observé |
| RX2 `02` | 1 | SIGMA_LIVE_MOTOR_INFORMATION | 10 | ✅ observé |
| RX3 `03` | 2 | SIGMA_LIVE_BATTERY_INFORMATION | 12 | ✅ observé |
| RX4 `04` | 3 | SIGMA_BIKE_STATUS | 3 | à valider |
| RX5 `05` | 4 | SIGMA_BIKE_DIAGNOSTIC_INFORMATION | 11 | ✅ observé |
| RX6 `06` | 5 | SIGMA_BIKE_SETUP_INFORMATION | 117 | à valider |
| RX7 `07` | 6 | SIGMA_BIKE_ASSISTANCE | 2 | ✅ observé |
| RX8 `08` | 7 | SIGMA_BIKE_LIGHT | 4 | à valider |
| RX9 `09` | 8 | SIGMA_BIKE_MESSAGES | 2 | hors sondage |
| RX10 `0a` | 9 | SIGMA_BIKE_MAINTENANCE | 8 | hors sondage |
| RX11 `0b` | 10 | SIGMA_ERROR_STATE | 102 | hors sondage |
| RX12 `0c` | 11 | SIGMA_SERVICE_VERSION | 2 | hors sondage |

L'application ne s'abonne qu'à RX1..RX8 (`FD6D_FIRST_CHAR=1`, `FD6D_LAST_CHAR=8`,
voir `BleManager.mc`). Le `hors sondage` concerne RX9..RX12, non souscrits.

### S.3 Détail des trames RX1..RX8

Toutes les trames sont **little-endian**, sans header/checksum : la
caractéristique est le message. Layouts issus des méthodes `Deserialize()` de
la lib Sitael (`com.sitael.SERIAL_SIGMA_EBIKE_Lib.*`).

**RX1 — SIGMA_LIVE_RIDE_INFORMATION (10 octets)** — ✅ validé terrain
Trame vue : `e7008b01000078001357` → 23,1 km/h, 0,4 km, 120 W, 19 Nm, 87 rpm.
| Off. | Champ | Type | Échelle |
|---|---|---|---|
| 0-1 | UINT16_Speed | u16 | ×0,1 → km/h |
| 2-5 | UINT32_Distance | u32 | mètres |
| 6-7 | UINT16_TreadlePower | u16 | W (puissance cycliste) |
| 8 | UINT8_TreadleTorque | u8 | Nm |
| 9 | UINT8_Cadence | u8 | rpm |

**RX2 — SIGMA_LIVE_MOTOR_INFORMATION (10 octets)** — ✅ observé
Trames vues : `90014000ffffffff8029` (400 W, 64 Nm, assistance 41 %) et
`00000000ffffffff8000` (0 W, 0 Nm, 0 %). Le couple moteur suit la puissance
(400/470/280/200/160/10/0 W ↔ 64/57/25/24/10/1/0 Nm).
| Off. | Champ | Type | Échelle / note |
|---|---|---|---|
| 0-1 | UINT16_MotorPower | u16 | W (✅) |
| 2-3 | UINT16_MotorTorque | u16 | Nm (observé, cohérent avec la puissance) |
| 4-5 | UINT16_MotorCurrent | u16 | `0xFFFF` = **non disponible** sur ce vélo |
| 6-7 | UINT16_MotorVoltage | u16 | `0xFFFF` = **non disponible** sur ce vélo |
| 8 | UINT8_MotorTemperature | u8 | vu `0x80`=128 = marqueur « n/a » (idem RX3) |
| 9 | UINT8_MotorAssistance | u8 | **%** (0..76 observé, suit la puissance cycliste) — à ne PAS confondre avec `AssistMode` (RX7) |

`BleManager`/`Sigma.parseMotor` n'injectent que `MotorPower` (`model.motorPowerW`,
métrique « Motor ») ; le reste est visible dans le log `_decodedMotor`.

**RX3 — SIGMA_LIVE_BATTERY_INFORMATION (12 octets)** — ✅ SOC/range/temp validés
Trame vue : `6440015ad28076000500701d` → SOC 100, courant `0x0140`=320, tension
`0xd25a`=53850 (≈53,85 V si mV), temp `0x80`, autonomie 118, logic 5, flashing 0,
capacité `0x1d70`=7536. L'autonomie varie (87/118/169 km).
| Off. | Champ | Type | Échelle / note |
|---|---|---|---|
| 0 | UINT8_BatterySOC | u8 | % (✅) |
| 1-2 | INT16_BatteryCurrent | i16 | vu 320 ; échelle à valider |
| 3-4 | UINT16_BatteryVoltage | u16 | vu 53850 → ≈53,85 V si mV (à confirmer) |
| 5 | UINT8_BatteryTemperature | u8 | vu `0x80`=128 = marqueur « n/a » (idem RX2 temp) |
| 6-7 | UINT16_EstimatedRange | u16 | km (✅), vu 87/118/169 |
| 8 | UINT8_LogicBatteryLevel | u8 | vu 5 |
| 9 | UINT8_BatteryDisplayFlashing | u8 | vu 0 |
| 10-11 | UINT16_BatteryCapacity | u16 | vu `0x1d70`=7536 ; échelle à valider |

**RX4 — SIGMA_BIKE_STATUS (3 octets)** — à valider
| Off. | Champ | Type |
|---|---|---|
| 0 | UINT8_FrontGear | u8 |
| 1 | UINT8_RearGear | u8 |
| 2 | UINT8_SystemState | u8 |

**RX5 — SIGMA_BIKE_DIAGNOSTIC_INFORMATION (11 octets)** — ✅ observé
Trame vue : `a8de0000f62e0000ffffff` → `0x0000dea8` = 57000, `0x00002ef6` =
12022, `ff ff ff`. Le 2ᵉ u32 s'incrémente lentement (≈ +1 toutes les ~15 min) ;
unités/échelles à confirmer (loguée brute, non injectée dans le modèle).
| Off. | Champ | Type | Note |
|---|---|---|---|
| 0-3 | UINT32_TotalRideDistance | u32 | vu 57000 (m ? 57 km) |
| 4-7 | UINT32_TotalRideTime | u32 | vu 12022, s'incrémente |
| 8 | UINT8_BatterySOH | u8 | vu `0xff` = n/a |
| 9-10 | UINT16_ChargingCycleCounter | u16 | vu `0xffff` = n/a |

**RX6 — SIGMA_BIKE_SETUP_INFORMATION (117 octets = `BLE_EBIKE_SERVICE_MAX_PCKT_SIZE`)** — à valider
| Off. | Champ | Type |
|---|---|---|
| 0 | UINT8_NumberOfAssistModes | u8 |
| 1-2 | UINT16_BatteryDesignCapacity | u16 |
| 3-4 | UINT16_BatteryDesignVoltage | u16 |
| 5 | UINT8_NumBattLogicLevels | u8 |
| 6 | BYTE_LightAvailability | byte |
| 7 | UINT8_ESystemManufacturerID | u8 |
| 8 | UINT8_Reserved1 | u8 |
| 9 | UINT8_NumberOfRearGear | u8 |
| 10 | UINT8_NumberOfFrontGear | u8 |
| 11-12 | UINT16_MotorMaximumPower | u16 |
| 13-14 | UINT16_MotorMaximumTorque | u16 |
| 15 | UINT8_BikeType | u8 |
| 16 | UINT8_AssistModeNamesLen | u8 |
| 17..16+Len | vBYTE_AssistModeNames[Len] | bytes |

**RX7 — SIGMA_BIKE_ASSISTANCE (2 octets)** — ✅ observé
Trames vues : `0100`, `0200`, `0300` → modes 1, 2, 3 (StartUpAssistance = 0).
| Off. | Champ | Type | Note |
|---|---|---|---|
| 0 | UINT8_AssistMode | u8 | mode actif, vu 1..3 (0 = OFF) |
| 1 | BYTE_StartUpAssistance | byte | vu `0x00` |

`BleManager`/`Sigma.parseAssist` injectent `AssistMode` (`model.assistMode`,
métrique « Assist » + champ FIT « Assistance »).

**RX8 — SIGMA_BIKE_LIGHT (4 octets)** — à valider
| Off. | Champ | Type |
|---|---|---|
| 0 | BYTE_LightModes | byte (bitfield) |
| 1 | UINT8_FrontLightBrightness | u8 |
| 2 | UINT8_FrontLightBeamBrightness | u8 |
| 3 | UINT8_RearLightBrightness | u8 |

**RX9 — SIGMA_BIKE_MESSAGES (2 octets, hors sondage)** : byte 0 bitfield
(advices dérailleur/assistance), byte 1 (GPSSignalState bit7 + FutureUse).
**RX10 — MAINTENANCE (8 o)** : Day u8, Month u8, Year u16, DateReminder u8,
TotDistNextMaintenance u16, DistanceReminder u8.
**RX11 — ERROR_STATE (102 o)** : ErrorCode[100] + ErrorLevel u8 +
ErrorCodeLength u8 (ordre exact à confirmer).
**RX12 — SERVICE_VERSION (2 o)** : Major u8, Minor u8.

### S.4 Données utilisées par l'application (data field)

`BleManager.onCharacteristicChanged` dispatche sur **RX1, RX2, RX3 et RX7** ;
les autres caractéristiques sont **loggées en hex brut** sans décodage
(`_charTag` → `RX4..RX6`, `RX8`).

| Message | Champs → modèle | Usage |
|---|---|---|
| RX1 RIDE | `speedKmh = u16(0)/10` (non affiché) ; `tripDistanceKm = u32(2)/1000` ; `powerW = u16(6)` (puissance cycliste) ; `torqueNm = d[8]` ; `cadenceRpm = d[9]` | affichage (Power, Cadence) + FIT (id 0-1) |
| RX2 MOTOR | `motorPowerW = u16(0)` | affichage (Motor) ✅ |
| RX3 BATTERY | `batterySoc = d[0]` ; `rangeKm = u16(6)` ; `temperatureC = d[5]` | affichage + FIT (id 3-4) |
| RX7 ASSISTANCE | `assistMode = d[0]` | affichage (Assist) + FIT (id 2) ✅ |

**La vitesse (RX1 Speed) n'est plus affichée** : la métrique « Speed » a été
retirée du data field et remplacée par la **puissance moteur (RX2)**. RX1 reste
décodé pour la puissance cycliste, la cadence, le couple et la distance.
**RX5 est observé mais non décodé** (loggé brut) ; échelles non validées
(courant/tension/capacité/temp) : non injectées, seulement loggées via
`_decodedBattery` / `_decodedMotor`.

---

## ARCHIVE — pile BCP / CAP / PDO (service `5e8597aa`)

> **Statut d'archivage (2026) :** la réception BCP/CAP/PDO via `5e8597aa-…`
> n'est **plus** observée sur le vélo réel (CCCD RX refusé `st=18`) ; les
> décodeurs `Bcp.mc`, `Cap.mc`, `Pdo.mc` sont conservés dans `archive/` (hors
> compilation). **Ce qui reste vivant :** le **heartbeat TX**, trame BCP
> single-frame écrite sur `5e8597ac` (BootUp à la connexion, Operational toutes
> les 1800 ms, Stopped à la déconnexion) — `BleManager._sendHeartbeat`. Le
> **changement de niveau d'assistance** (SDO_WRITE) est archivé/désactivé
> (voir `archive/Assist.mc`). Le §6 PDO ci-dessous est le protocole
> **FIT e-Bike CAN** de Biketec — **sans rapport avec Sigma** (§ Sigma).

### A.1 GATT legacy

| Rôle | UUID |
|---|---|
| Service de données BCP (non annoncé en AD, présent au GATT) | `5e8597aa-69d9-11ea-bc55-0242ac130003` |
| TX (écriture, vers le moteur) | `5e8597ac-69d9-11ea-bc55-0242ac130003` |
| RX (notification, depuis le moteur) | `5e8597ab-69d9-11ea-bc55-0242ac130003` |

Le vélo annonce `0xFD6D` et `5e8597aa-…` (128-bit incomplet) ; la pile BLE du
firmware Garmin ne remonte que le 16-bit au scan. Connect IQ n'a pas de
découverte GATT : on enregistre **deux profils** — AD (FD6D, voir §S.1) et
données (5e8597aa + RX/TX). En pratique les données ne remontent **que** sur
FD6D (CCCD `5e8597ab` refusé, `st=18`).

### A.2 Framing BCP (20 octets / trame)

Toute trame fait **20 octets**, complétée par des zéros.

**Trame SINGLE (0xC0 – 0xDF)**
```
[0xC0 | len(5)]  [session/type(8)]  [payload len octets]  [zéros → 20]
```
- `len` = longueur du payload (2..18) = paquet BCP (voir §A.3).
- Pas de CRC en single-frame.

**Trame MULTI (START/BODY/STOP)** — START `0x80|frameId`, BODY `0x00|frameId`,
STOP `0x40|frameId` — avec FrameSize u16 LE, FrameCrc u16 LE (CRC16 CCITT-FALSE,
poly `0x1021`, init `0xFFFF`, MSB d'abord), FramesNumber u16 LE. Les trames
moteur multi sont ignorées par le data field.

**Trame ACK (0xE0 – 0xFF)** : émise par le moteur en réponse aux multi, ignorée.

### A.3 En-tête BCP (2 octets) — `BCPPacket`

```
byte0 = (signature << 6) | (protocol << 3) | version
byte1 = (recipient << 3) | sender
```
signature=0, protocol=1 (FITCANAccessProtocol CAP), version=1,
recipient sortant 0 (FIT_REMOTE), sender 2 (CellPhoneApp). Payload moteur →
app : `[0x09, 0x02, type, ...]`. Le contenu utile est un paquet **CAP** :
`[type, data...]`.

### A.4 Paquets CAP — `CAPType`

| Valeur | Type |
|---|---|
| 0 | SDO_READ |
| 1 | SDO_WRITE |
| 2 | SDO_READ_STREAM |
| 3 | SDO_WRITE_STREAM |
| 4 | RESPONSE |
| 5 | STREAM_RESPONSE |
| 6 | NMT_COMMAND |
| 7 | PDO (données périodiques moteur) |
| 8 | HEARTBEAT |
| 10 | INVALID |

### A.5 Heartbeat (toujours utilisé, TX)

`CAPPacket(HEARTBEAT, [status, info])` → payload `[8, status, info]`.

| Statut | `status` |
|---|---|
| BootUp | 0 |
| Stopped | 4 |
| Operational | 5 |
| PreOperational | 127 |

Séquence (toujours active dans `BleManager`) : `BootUp` `[09 02 08 00 00]` dès
la connexion GATT, puis `Operational` `[09 02 08 05 00]` toutes les **1800 ms**,
et `Stopped` `[09 02 08 04 00]` à l'arrêt. Trame wire single-frame complète :
`[0xC5, session, 0x09, 0x02, 8, status, info, zéros…]`.

### A.6 PDO (`CAPType.PDO = 7`) — archive

Payload : `[version(1)][numFrames(1)]` puis `numFrames ×` frames de 10 octets.
Frame PDO (10 o) : `[ (len<<3)|(canId>>8) ][ canId & 0xFF ][8 octets de données]`
avec `canId = ((b0 & 0x07) << 8) | b1`.

**Identifiants PDO (protocole FIT e-Bike CAN — PAS Sigma)**

| PDO | CAN ID | déc. |
|---|---|---|
| PDO1 | 0x281 | 641 |
| PDO2 | 0x2A1 | 673 |
| PDO3 | 0x2C1 | 705 |
| PDO4 | 0x2E1 | 737 |
| PDO5 | 0x301 | 769 |
| PDO6 | 0x321 | 801 |
| PDO7 | 0x341 | 833 |
| PDO8 | 0x361 | 865 |
| PDO9 (TPMS) | 0x261 | 609 |
| PDO11 | 0x3A1 | 929 |

**Mappings (octets 0..7 des données, LE) — §6.3 historique (FIT e-Bike)**

PDO1 — 0x281 : bikeSpeed u16 /10, driverPower W u16, driverCadence i16,
réservé, relMotorAssistance i8.
PDO2 — 0x2A1 : altitude i16, tripAltitude i16, appStatus u8, lockStatus u8,
inclination i8, pulse u8.
PDO3 — 0x2C1 : range u16, soc u8, batterie 1-4 soc u8×4, température i8 /2.
PDO4 — 0x2E1 : driverOdometer u32, driverEnergyKcal i16, batteryConsumption u8.
PDO5 — 0x301 : tripTime s u16, tripDistance /10 u16, avgSpeed /10 u16,
maxSpeed /10 u16.
PDO6 — 0x321 : navigationDistance u16, navigationDirection u8, gearStatus u8,
gearValue u8, weatherForecast 1-3 u8×3.
PDO7 — 0x341 : stateIndication u8, buttons u8, smartphoneSoc u8, assistLevel
i8, iconIndication u16, error u16 (errorType = b6&0x1F, errorCode = b7).
PDO8 — 0x361 : batteryStates u8×4, chargeRemainingTime u8, countdown u8,
ioTStatus u8 (&3).
PDO9 (TPMS) — 0x261 : pressions FL/RR/FR/RL u16 ×10 (ordre wire FL, RR, FR, RL).
PDO11 — 0x3A1 : totalActiveEmergencies u8.

Les sentinelles (`0xFFFF`, `255`, `127`, `-1`…) dénotent l'absence de valeur —
voir le détail complet dans l'historique git de `docs/PROTOCOL.md` et
`archive/Pdo.mc`.

### A.7 Écriture CAN par SDO_WRITE — arch. (ancien changement de niveau)

L'app changeait le niveau par un **SDO_WRITE** BCP/CAP ciblé
(`MotorSettingsActuator.setAssistantLevel` → `sendSDOWriteDirection`) :
node 1 (REMOTE), **index 9602** (`SYSTEM_ASSISTANCE`, `0x2582`), **subIndex 6**,
1 octet. Valeurs `CoreMotorMode` : 0=OFF, 1..4=GAIN_1..4, 5=WALK_ASSIST (inutilisé),
6=GAIN_BOOST (inutilisé).

Trame BCP single-frame, 20 octets (byte-exact avec
`serializeMessageIntoBCPPackets` + `CAP_PACKET_SDO_WRITE.Serialize`) :
```
oct   description
0     0xCC = PayloadSize 12
1     (session & 31)<<3
2-3   0x09 0x02  BCP header (CAP)
4     0x01  CAP SDO_WRITE
5     0x01  (IsTimeout 0)<<7 | (UnusedBits 0)<<5 | NodeID 1
6-7   RequestID  u16 LE
8-9   SdoIndex = 9602  u16 LE (0x82, 0x25)
10    0x06  SdoSubIndex = 6
11    0x00  SdoTimeout
12    0x01  SdoDataLength = 1
13    mode  CoreMotorMode (0..4)
14-19 0x00  padding
```

Un écueil mesuré : un `PayloadSize` qui ment sur la longueur réelle du message
CAP (ex. 13 au lieu de 12) fait dropper la trame par le parseur du vélo. Octet 5
vérifié sur `CAP_PACKET_SDO_WRITE.Deserialize` (IsTimeout/UnusedBits/NodeID
packés sur un octet, RequestID et SdoIndex en LE).

**Handshake « save » (persistance)** : tout SDO_WRITE seul ne persiste pas — le
SDK Biketec terminait l'écriture par un write **index 4112**
(`SAVE_GENERAL_SETTINGS`, `0x1010`), subIndex 1, magic `0x65766173` LE =
octets `73 61 76 65` (« save »), vers le node propriétaire (1 REMOTE /
`saveToPersistRemoteMemory`, 2 DRIVE_UNIT / `saveToPersistMotorMemory`, 3
DISPLAY). Trame de 20 octets, message CAP de 15 octets, `0xCF = PayloadSize 15`.
Sans lui, le changement restait en RAM et se perdait. Implémentation + layout :
`archive/Assist.mc`.

---

## Séquence de connexion (data field, état réel)

1. Scan BLE sur le service annoncé `0000fd6d-…` (le watch ne voit que lui en
   AD) ; match aussi `5e8597aa-…` au cas où.
2. `pairDevice(scanResult)` → appairage confirmé par l'utilisateur.
3. Connexion : récupérer les services FD6D (profil AD) et `5e8597aa` (profil
   données, TX `5e8597ac` heartbeats).
4. Souscrire les CCCD des caractéristiques FD6D `00000001..08` (`[0x01, 0x00]`).
   Le CCCD BCP `5e8597ab` est aussi tenté mais refusé (`st=18`) sur le vélo.
5. Envoyer le heartbeat BCP `BootUp` `[0x09, 0x02, 8, 0, 0]` sur TX `5e8597ac`.
6. Heartbeat `Operational` `[0x09, 0x02, 8, 5, 0]` auto-gated à 1800 ms, envoyé
   **à chaque trame RX reçue** (`onCharacteristicChanged` → `onTick()`) — pas
   d'horloge propre : `Toybox.Timer` n'est **pas disponible** dans un data field
   (`Permission Required: not available to 'Data Field'`), et `onUpdate` ne
   tourne que quand la page du champ est affichée. Tout le travail périodique
   (heartbeat + enregistrement FIT) est donc porté par le flux RX entrant, qui
   continue même champ caché.
7. Les notifications Sigma arrivent sur FD6D : RX1 (RIDE) + RX3 (BATTERY)
   décodées, RX2/RX4..RX8 loguées en hex. À la déconnexion : heartbeat
   `Stopped` `[0x09, 0x02, 8, 4, 0]`.

---

## Enregistrement FIT (activité Garmin)

Le data field déclare ses métriques dans le fichier FIT de l'activité via
`FitContributor` (≠ §A.6 « FIT e-Bike » : ici **format de fichier Garmin FIT**).

- **`resources/fitcontributions.xml`** — bloc `<fitContributions>` avec un
  `<fitField>` par champ (`id` = `fieldId` passé à `createField`) : libellés,
  graphiques, résumé d'activité, tours.
- **`:nativeNum` dans `createField`** — annote le champ développeur comme
  **équivalent** à un champ du profil FIT (override natif). Garmin Connect **ne
  traite pas** un champ CIQ comme natif (le rendu GC vient de
  `fitcontributions.xml`) ; l'annotation sert surtout à certains tiers
  (runalyze, SportTracks, Golden Cheetah, ConnectStats). Numéros RECORD :
  `heart_rate=3, cadence=4, distance=5, speed=6, power=7, motor_power=82` ;
  injectés en natif : **cadence (4)**, **power (7)**, **motor_power (82)**.

| id | Nom | Message | Type | natif |
|---|---|---|---|---|
| 0 | Cyclist Power | record | u16 | power=7 |
| 1 | Cadence | record | u8 | cadence=4 |
| 2 | Assistance | record | i16 | — |
| 3 | Battery | record | u8 | — |
| 4 | Range | record | u16 | — |
| 5 | Avg Power | session | u16 | — |
| 6 | Avg Cadence | session | u16 | — |
| 7 | Min Battery | session | u8 | — |
| 8 | Avg Power | lap | u16 | — |
| 9 | Avg Cadence | lap | u16 | — |
| 10 | Motor Power | record | u16 | motor_power=82 |

Moyennes session/tour calculées en interne (`_powerSum`/`_cadenceSum` sur
`onTick` / `onTimerStart/Resume/Lap/Reset`).

### Enregistrement « en continu » (champ non affiché)

`onUpdate` n'est appelé que quand la page du data field est affichée. Pour que
l'enregistrement continue quand une autre page de données est visible,
`BleManager.onCharacteristicChanged` appelle à chaque trame RX reçue :
`onTick()` (heartbeat, auto-gated 1800 ms) puis `fit.update(_model)` (via
`setFitContributor`). Conséquences :

- **Enregistrement FIT ininterrompu** tant que le vélo envoie des trames, champ
  caché ou non (les callbacks BLE, eux, continuent de tourner).
- Les **moyennes session/tour restent échantillonnées à 1 Hz** : `update()`
  n'accumule que si `System.getTimer() - _lastAvgTime >= 1000`. Sans ce gate,
  les trames RX (plus rapides que 1 Hz) sur-échantillonneraient et les moyennes
  dériveraient vs l'ancien build ; il neutralise aussi le double appel quand le
  champ est affiché (onUpdate 1 Hz + flux RX).
- Limite : en mode **demo** (pas de BLE), l'enregistrement reste lié à
  `onUpdate` (outil de simulation uniquement).
- À vérifier sur le terrain : les callbacks `onTimerStart/Pause/Lap` du data
  field sont-ils délivrés quand la page est cachée ? S'ils ne l'étaient pas,
  l'état tournée `_timerRunning` serait faux pour une sortie entièrement menée
  sur une autre page (moyennes session/tour à re-vérifier).