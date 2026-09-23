import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;

//! Records eBike metrics into the activity FIT file. Power, cadence and
//! motor power are written into the device-native record fields (via
//! :nativeNum) so compatible services treat them as real Power/Cadence/
//! Motor Power; the remaining metrics are developer fields described by
//! resources/fitcontributions.xml (charts + activity summary + laps).
class EbikeFitContributor {
    private enum FieldId {
        FIELD_POWER,
        FIELD_CADENCE,
        FIELD_ASSIST,
        FIELD_BATTERY,
        FIELD_RANGE,
        FIELD_AVG_POWER,
        FIELD_AVG_CADENCE,
        FIELD_MIN_BATTERY,
        FIELD_LAP_AVG_POWER,
        FIELD_LAP_AVG_CADENCE,
        FIELD_MOTOR_POWER
    }

    //! Garmin native RECORD field numbers (as used by :nativeNum):
    //! heart_rate=3, cadence=4, distance=5, speed=6, power=7,
    //! motor_power=82. See docs/PROTOCOL.md for the source.
    private const NATIVE_RECORD_CADENCE = 4;
    private const NATIVE_RECORD_POWER = 7;
    private const NATIVE_RECORD_MOTOR_POWER = 82;

    private var _powerField as FitContributor.Field;
    private var _cadenceField as FitContributor.Field;
    private var _assistField as FitContributor.Field;
    private var _batteryField as FitContributor.Field;
    private var _rangeField as FitContributor.Field;
    private var _motorPowerField as FitContributor.Field;
    private var _avgPowerField as FitContributor.Field;
    private var _avgCadenceField as FitContributor.Field;
    private var _minBatteryField as FitContributor.Field;
    private var _lapAvgPowerField as FitContributor.Field;
    private var _lapAvgCadenceField as FitContributor.Field;

    private var _lastPower as Number? = null;
    private var _lastCadence as Number? = null;
    private var _lastAssist as Number? = null;
    private var _lastBattery as Number? = null;
    private var _lastRange as Number? = null;
    private var _lastMotorPower as Number? = null;

    private var _timerRunning as Boolean = false;
    //! Timestamp of the last accumulated average sample. Session/lap averages
    //! are sampled once per second (not once per update() call), because
    //! update() is driven both by the visible field's onUpdate (1 Hz) and by
    //! incoming BLE traffic (could be faster), and the same rate as the
    //! shipped build keeps Avg Power/Cadence numerically identical.
    private var _lastAvgTime as Number = 0;
    private var _powerSum as Number = 0;
    private var _cadenceSum as Number = 0;
    private var _powerSamples as Number = 0;
    private var _cadenceSamples as Number = 0;
    private var _lapPowerSum as Number = 0;
    private var _lapCadenceSum as Number = 0;
    private var _lapPowerSamples as Number = 0;
    private var _lapCadenceSamples as Number = 0;
    private var _sessionMinBattery as Number = 100;

    public function initialize(dataField as EbikeDataField) {
        _powerField = dataField.createField("Cyclist Power", FIELD_POWER, FitContributor.DATA_TYPE_UINT16, { :nativeNum => NATIVE_RECORD_POWER, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" });
        _cadenceField = dataField.createField("Cadence", FIELD_CADENCE, FitContributor.DATA_TYPE_UINT8, { :nativeNum => NATIVE_RECORD_CADENCE, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rpm" });
        _assistField = dataField.createField("Assistance", FIELD_ASSIST, FitContributor.DATA_TYPE_SINT16, { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mode" });
        _batteryField = dataField.createField("Battery", FIELD_BATTERY, FitContributor.DATA_TYPE_UINT8, { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%" });
        _rangeField = dataField.createField("Range", FIELD_RANGE, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "km" });
        _motorPowerField = dataField.createField("Motor Power", FIELD_MOTOR_POWER, FitContributor.DATA_TYPE_UINT16, { :nativeNum => NATIVE_RECORD_MOTOR_POWER, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" });

        _avgPowerField = dataField.createField("Avg Power", FIELD_AVG_POWER, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "W" });
        _avgCadenceField = dataField.createField("Avg Cadence", FIELD_AVG_CADENCE, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "rpm" });
        _minBatteryField = dataField.createField("Min Battery", FIELD_MIN_BATTERY, FitContributor.DATA_TYPE_UINT8, { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%" });

        _lapAvgPowerField = dataField.createField("Avg Power", FIELD_LAP_AVG_POWER, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "W" });
        _lapAvgCadenceField = dataField.createField("Avg Cadence", FIELD_LAP_AVG_CADENCE, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "rpm" });

        _powerField.setData(0);
        _cadenceField.setData(0);
        _assistField.setData(0);
        _batteryField.setData(0);
        _rangeField.setData(0);
        _motorPowerField.setData(0);
        _avgPowerField.setData(0);
        _avgCadenceField.setData(0);
        _minBatteryField.setData(0);
        _lapAvgPowerField.setData(0);
        _lapAvgCadenceField.setData(0);
    }

    public function update(model as EbikeData) as Void {
        var power = model.powerW;
        if (power != null && power != _lastPower) {
            _powerField.setData(power);
            _lastPower = power;
        }
        var cadence = model.cadenceRpm;
        if (cadence != null && cadence != _lastCadence) {
            _cadenceField.setData(cadence);
            _lastCadence = cadence;
        }
        var assist = model.assistMode;
        if (assist != null && assist != _lastAssist) {
            _assistField.setData(assist);
            _lastAssist = assist;
        }
        var battery = model.batterySoc;
        if (battery != null && battery != _lastBattery) {
            _batteryField.setData(battery);
            _lastBattery = battery;
        }
        var range = model.rangeKm;
        if (range != null && range != _lastRange) {
            _rangeField.setData(range);
            _lastRange = range;
        }
        var motorPower = model.motorPowerW;
        if (motorPower != null && motorPower != _lastMotorPower) {
            _motorPowerField.setData(motorPower);
            _lastMotorPower = motorPower;
        }

        if (_timerRunning) {
            var now = System.getTimer();
            if (now - _lastAvgTime >= 1000) {
                _lastAvgTime = now;
                if (power != null) {
                    _powerSum += power;
                    _powerSamples++;
                    _lapPowerSum += power;
                    _lapPowerSamples++;
                }
                if (cadence != null) {
                    _cadenceSum += cadence;
                    _cadenceSamples++;
                    _lapCadenceSum += cadence;
                    _lapCadenceSamples++;
                }
                if (battery != null && battery < _sessionMinBattery) {
                    _sessionMinBattery = battery;
                }
                _avgPowerField.setData(_avg(_powerSum, _powerSamples));
                _avgCadenceField.setData(_avg(_cadenceSum, _cadenceSamples));
                _minBatteryField.setData(_sessionMinBattery);
                _lapAvgPowerField.setData(_avg(_lapPowerSum, _lapPowerSamples));
                _lapAvgCadenceField.setData(_avg(_lapCadenceSum, _lapCadenceSamples));
            }
        }
    }

    private function _avg(sum as Number, samples as Number) as Number {
        if (samples == 0) {
            return 0;
        }
        return sum / samples;
    }

    public function onTimerStart() as Void {
        _timerRunning = true;
    }

    public function onTimerResume() as Void {
        _timerRunning = true;
        _lastAvgTime = 0;
    }

    public function onTimerPause() as Void {
        _timerRunning = false;
    }

    public function onTimerStop() as Void {
        _timerRunning = false;
    }

    public function onTimerLap() as Void {
        _lapPowerSum = 0;
        _lapCadenceSum = 0;
        _lapPowerSamples = 0;
        _lapCadenceSamples = 0;
    }

    public function onTimerReset() as Void {
        _timerRunning = false;
        _lastAvgTime = 0;
        _powerSum = 0;
        _cadenceSum = 0;
        _powerSamples = 0;
        _cadenceSamples = 0;
        _lapPowerSum = 0;
        _lapCadenceSum = 0;
        _lapPowerSamples = 0;
        _lapCadenceSamples = 0;
        _sessionMinBattery = 100;
        _lastPower = null;
        _lastCadence = null;
        _lastAssist = null;
        _lastBattery = null;
        _lastRange = null;
        _lastMotorPower = null;
    }
}