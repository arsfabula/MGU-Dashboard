import Toybox.Lang;

//! Decoder for the Sigma frames broadcast by the bike's 0000fd6d service
//! (lib com.sitael.SERIAL_SIGMA_EBIKE_Lib). Each FD6D characteristic
//! 0000000N (RX1..RX8) carries one SIGMA message — see docs/PROTOCOL.md §S.2
//! for the full RX1..RX8 mapping and statuses. Decoded here: RX1 (RIDE),
//! RX2 (MOTOR), RX3 (BATTERY), RX7 (ASSISTANCE) — all four observed on the
//! bike. RX4..RX6/RX8 are logged raw until their traffic is characterised.
//! Layouts are little-endian, taken from the Sitael Deserialize() methods.
class Sigma {
    public function initialize() {
    }

    //! SIGMA_LIVE_RIDE_INFORMATION (10 bytes, RX1, observed): [0:2] Speed u16
    //! ×0.1 km/h, [2:6] Distance u32 m, [6:8] TreadlePower u16 W,
    //! [8] TreadleTorque u8 Nm, [9] Cadence u8 rpm.
    public function parseRide(d as ByteArray, model as EbikeData) as Void {
        if (d.size() < 10) {
            return;
        }
        model.speedKmh = _u16(d, 0) / 10.0;
        model.tripDistanceKm = _u32(d, 2) / 1000.0;
        model.powerW = _u16(d, 6);
        model.torqueNm = d[8];
        model.cadenceRpm = d[9];
    }

    //! SIGMA_LIVE_MOTOR_INFORMATION (10 bytes, RX2, observed): [0:2]
    //! MotorPower u16 W, [2:4] MotorTorque u16 Nm, [4:6] MotorCurrent u16,
    //! [6:8] MotorVoltage u16, [8] MotorTemperature u8, [9] MotorAssistance u8 %.
    //! Only MotorPower is injected into the model (motorPowerW); the rest is
    //! visible in the raw RX2 hex log. On the bike seen so far Current/Voltage
    //! read 0xFFFF (not available) and [9] is a 0..76 % (NOT the RX7 mode).
    public function parseMotor(d as ByteArray, model as EbikeData) as Void {
        if (d.size() < 10) {
            return;
        }
        model.motorPowerW = _u16(d, 0);
    }

    //! SIGMA_BIKE_ASSISTANCE (2 bytes, RX7, observed): [0] AssistMode u8,
    //! [1] StartUpAssistance byte. AssistMode is the active assist mode
    //! (0 = off, seen 1..3), injected into the model and shown as the
    //! Assistance metric / FIT field.
    public function parseAssist(d as ByteArray, model as EbikeData) as Void {
        if (d.size() < 2) {
            return;
        }
        model.assistMode = d[0];
    }

    //! SIGMA_LIVE_BATTERY_INFORMATION (12 bytes, RX3, observed): [0] SOC %,
    //! [1:3] BatteryCurrent i16, [3:5] BatteryVoltage u16, [5] Temperature °C,
    //! [6:8] EstimatedRange u16, [8] LogicBatteryLevel, [9]
    //! BatteryDisplayFlashing, [10:12] BatteryCapacity u16. SOC and range are
    //! validated on the bike; current / voltage / temperature / capacity
    //! scales are NOT (see docs/PROTOCOL.md §S.3 — temp seen as 0x80=128).
    public function parseBattery(d as ByteArray, model as EbikeData) as Void {
        if (d.size() < 12) {
            return;
        }
        model.batterySoc = d[0];
        model.rangeKm = _u16(d, 6);
        model.temperatureC = d[5].toFloat();
    }

    private function _u16(d as ByteArray, i as Number) as Number {
        return (d[i + 1] << 8) | d[i];
    }

    //! Signed 16-bit little-endian read.
    public function i16(d as ByteArray, i as Number) as Number {
        var v = (d[i + 1] << 8) | d[i];
        if (v > 32767) {
            v -= 65536;
        }
        return v;
    }

    //! Raw 16-bit little-endian read (for logging unvalidated fields).
    public function u16(d as ByteArray, i as Number) as Number {
        return _u16(d, i);
    }

    private function _u32(d as ByteArray, i as Number) as Number {
        return ((d[i + 3] << 24) | (d[i + 2] << 16) | (d[i + 1] << 8) | d[i]) & 0xFFFFFFFF;
    }
}