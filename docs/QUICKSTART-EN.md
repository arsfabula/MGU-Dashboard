# MGU Dashboard — Quick Start Guide

A Connect IQ data field for Garmin watches that shows your e-bike assistance data (Pinion MGU motor) in real time, straight on your wrist.

## 1. Overview
Added to an activity data screen, it automatically connects to your bike over Bluetooth Low Energy. The screen uses fixed bands: a **radial cyclist-power gauge** (a thick arc hugging the top of the screen, spanning 10 o'clock to 2 o'clock, scale 0→2×FTP with 7 colour segments and a needle), a **Motor / Cadence / Assist** band, a **Battery / Range** band, and the bike's name at the bottom. Each band metric is set in the settings menu (§4); power is always shown by the gauge.

The gauge scale spans 0 to **2×FTP**: the needle points straight up when you ride at your FTP, and the central (yellow) zone is FTP ±15 %. All 7 segments have the same width and read, left to right, from grey (very easy) to purple (well above FTP), through blue, green and yellow — so low power sits on the left and high power on the right. The FTP is chosen in the menu (§4); at “**Auto**”, the field uses your user profile FTP when available, else 200 W.

Beyond the screen:
- **FIT recording**: power, motor power, cadence, assistance, battery and range are saved into the activity; power, motor power and cadence use Garmin's native fields (recognised by Garmin Connect: averages, laps, minimums).
- **Demo mode**: simulates a bike with no BLE, to test the display.

## 2. Installing the data field
**From the phone (recommended)**: in Garmin Connect, open **Connect IQ Store**, search for **MGU Dashboard**, tap **Install** and pick your watch.
**From a computer**: connect.garmin.com ▸ Connect IQ Store ▸ Install.

Requirements: a Connect IQ-compatible watch, Garmin Connect Mobile installed and the watch synced.

### Adding MGU Dashboard to an activity
- **On the watch**: start an activity (e.g. Bike), hold the middle button ▸ **Data Screens** ▸ **Add** ▸ **Connect IQ** ▸ MGU Dashboard. (Repeat for several screens with different metrics.)
- **From the phone**: Garmin Connect ▸ **More** ▸ **Activity Profiles** ▸ activity ▸ **Data Screens** ▸ **Add** ▸ Connect IQ ▸ MGU Dashboard.

## 3. Automatic connection
No configuration needed: it's all automatic. When the activity starts, the field scans for BLE devices advertising the motor's service (UUID `0xFD6D`) and shows “Scanning…”. On the first pairing, confirm it on the watch. Once connected, data streams in continuously (~1.3 s) and the bike's name appears as the screen title. A heartbeat keeps the link stable.

Screen states: “Scanning…” (scan in progress), “Waiting…” (connected, no data for ~10 s), `--` (data unavailable). If the connection drops, the field restarts the scan automatically.

## 4. Features & menu
Menu: Activity ▸ **Activity Settings** ▸ **Connect IQ Fields** ▸ **MGU Dashboard**.

Options:
- **Demo mode**: generates simulated data with no bike or BLE (“Demo” screen).
- **Labels**: shows each metric's name above its value (default: on).
- **Motor / Cadence / Assist / Battery / Range**: turn each band metric on/off (default: all on). The power gauge is always shown.
- **FTP**: picker wheel with **Auto** (default) or 60–400 W in 5 W steps. Drives the gauge scale (see §1).
- **Debug (measurements)**: band-layout logs, for diagnostics only.

Activity recording: continuously (power, cadence, assistance, battery, range), as a summary (average power, average cadence, minimum battery) and per lap (averages) — all visible in Garmin Connect. The BLE callbacks drive the recording, so it keeps running even while the field is not the displayed data page (only demo mode needs the field visible).

## 5. Notes & limitations
Data arrives roughly every 1.3 s (the motor's native stream, not the GPS pace). Only the BLE link draws the watch's battery. Demo mode disconnects from the bike until disabled.

## 6. Quick troubleshooting
- “Scanning…” all the time: bike off or too far → move closer, motor on, keep the screen awake.
- “Waiting…”: restart the activity or power-cycle the motor.
- No pairing offered: the bike is already paired; otherwise forget it in the watch's Bluetooth settings.
- Gauge pinned at the top: “Auto” FTP is too low (profile) → pick a value in the menu (§4).
- White screen **in the simulator**: enable **Demo mode** (the simulator does not implement Bluetooth; the app cannot start with demo disabled).
- Test without a bike: enable **Demo mode**, then turn it off.

*Technical docs: docs/PROTOCOL.md (BLE protocol), docs/BUILD.md (building).*