import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Generates realistic eBike data so the field can be exercised
//! without a real bike (or BLE at all).
class DemoManager {
    private var _model as EbikeData;
    private var _tick as Number = 0;
    private var _speed as Float = 16.0;
    private var _altitudeM as Number = 125;
    private var _soc as Float = 85.0;
    private var _maxSpeedKmh as Float = 0.0;
    private var _tripDistanceKm as Float = 0.0;
    private var _odometerKm as Float = 1246.5;

    public function initialize(model as EbikeData) {
        _model = model;
    }

    public function stop() as Void {
    }

    public function onTick() as Void {
        _tick++;

        _speed = 16.0 + 6.0 * Math.sin(_tick.toFloat() / 7.0) + _noise(2.0);
        if (_speed < 3.0) {
            _speed = 3.0;
        } else if (_speed > 45.0) {
            _speed = 45.0;
        }

        var power = (80.0 + _speed * 6.5 + _noise(25.0)).toNumber();
        if (power < 0) {
            power = 0;
        }

        var cadence = (82.0 + 5.0 * Math.sin(_tick.toFloat() / 4.5) + _noise(4.0)).toNumber();
        if (cadence < 50) {
            cadence = 50;
        } else if (cadence > 115) {
            cadence = 115;
        }

        var assist = (100.0 + 6.0 * Math.sin(_tick.toFloat() / 30.0)).toNumber();
        // Motor (assist) power roughly follows the rider's power.
        var motorPower = (power * 1.8 + _noise(20.0)).toNumber();
        if (motorPower < 0) {
            motorPower = 0;
        }
        // Active assist mode cycles 1..4 over time (0 = off is not demoed).
        var assistMode = 1 + ((_tick / 20) % 4);

        _soc -= 0.004;
        if (_soc < 5.0) {
            _soc = 5.0;
        }

        var range = (_soc * 0.9 + _noise(3.0)).toNumber();
        if (range < 0) {
            range = 0;
        }

        _altitudeM += _randInt(3) - 1;
        if (_altitudeM < 40) {
            _altitudeM = 40;
        } else if (_altitudeM > 900) {
            _altitudeM = 900;
        }

        var temp = 22.0 + 0.5 * Math.sin(_tick.toFloat() / 50.0);
        if (temp < 5.0) {
            temp = 5.0;
        } else if (temp > 45.0) {
            temp = 45.0;
        }

        _tripDistanceKm += _speed / 3600.0;
        _odometerKm += _speed / 3600.0;
        if (_speed > _maxSpeedKmh) {
            _maxSpeedKmh = _speed;
        }

        var model = _model;
        model.connected = true;
        model.speedKmh = _speed;
        model.powerW = power;
        model.motorPowerW = motorPower;
        model.cadenceRpm = cadence;
        model.assistPercent = assist;
        model.assistMode = assistMode;
        model.batterySoc = _soc.toNumber();
        model.rangeKm = range;
        model.altitudeM = _altitudeM;
        model.temperatureC = temp;
        model.odometerKm = _odometerKm;
        model.tripTimeS = _tick;
        model.tripDistanceKm = _tripDistanceKm;
        model.avgSpeedKmh = _tripDistanceKm / (_tick.toFloat() / 3600.0);
        model.maxSpeedKmh = _maxSpeedKmh;
        model.lastUpdate = System.getTimer();
    }

    private function _noise(magnitude as Float) as Float {
        return (Math.rand() % 1000).toFloat() / 1000.0 * magnitude * 2.0 - magnitude;
    }

    private function _randInt(max as Number) as Number {
        return Math.rand() % (max + 1);
    }
}
