# MGU Dashboard

A Connect IQ data field for Garmin watches that shows your e-bike assistance data (Pinion MGU motor) in real time, straight on your wrist.

## Features

- Automatic connection to your bike over Bluetooth Low Energy (motor service UUID `0xFD6D`)
- Configurable display: cyclist power (W), motor power (W), cadence (rpm), assist mode, battery (%) and range (km)
- Adaptive display grid (1 to 3 columns), each metric can be turned on/off
- **FIT recording**: cyclist power, motor power and cadence use Garmin's native fields (averages, laps, minimums recognized by Garmin Connect), plus assistance, battery and range
- **Demo mode**: simulates a bike with no BLE, to test the display
- Multilingual labels (EN, FR, DE, IT)

## Installing on your watch

- **Phone**: Garmin Connect ▸ Connect IQ Store ▸ search **MGU Dashboard** ▸ Install
- **Computer**: connect.garmin.com ▸ Connect IQ Store ▸ Install

Then add it to an activity: **Data Screens ▸ Add ▸ Connect IQ ▸ MGU Dashboard**.

## Development

A Connect IQ data field written in Monkey C (Garmin Connect IQ SDK).

```
monkeyc -d <device> -f monkey.jungle -o ebikedf.prg -y developer_key.der -w
```

Build outputs (`bin/`, `*.iq`, `*.prg`, `*.debug.xml`) and developer keys (`*.pem`, `*.der`) are excluded via `.gitignore`.

## Documentation

- [Quick Start Guide — EN](docs/QUICKSTART-EN.md)
- [Guide de démarrage rapide — FR](docs/QUICKSTART-FR.md)
- [BLE protocol (technical)](docs/PROTOCOL.md)
- [Building](docs/BUILD.md)

## License

See the [LICENSE](LICENSE) file.

---

**[Français](README.fr.md)** — Version française du README.