import Toybox.Lang;
import Toybox.System;

class EbikeData {
    public var connected as Boolean = false;
    public var bikeName as String? = null;
    public var speedKmh as Float? = null;
    public var powerW as Number? = null;
    //! 3 s moving average of the rider power: what the gauge draws. powerW
    //! stays raw because the FIT record must keep the instantaneous samples.
    public var powerW3s as Number? = null;
    public var motorPowerW as Number? = null;
    public var cadenceRpm as Number? = null;
    public var torqueNm as Number? = null;
    public var assistPercent as Number? = null;
    public var assistMode as Number? = null;
    public var batterySoc as Number? = null;
    public var rangeKm as Number? = null;
    public var temperatureC as Float? = null;
    public var altitudeM as Number? = null;
    public var odometerKm as Float? = null;
    public var tripTimeS as Number? = null;
    public var tripDistanceKm as Float? = null;
    public var avgSpeedKmh as Float? = null;
    public var maxSpeedKmh as Float? = null;
    public var lastUpdate as Number = 0;

    //! Rider-power samples kept for the 3 s moving average drawn by the gauge.
    //! 32 slots cover the window up to ~10 samples/s (RX1 is faster than 1 Hz
    //! but well below that); entries older than the window are skipped.
    private const PW_WINDOW_MS = 3000;
    private const PW_SLOTS = 32;
    private var _pwT as Array<Number>;
    private var _pwV as Array<Number>;
    private var _pwHead as Number = 0;
    private var _pwCount as Number = 0;

    public function initialize() {
        _pwT = new [PW_SLOTS] as Array<Number>;
        _pwV = new [PW_SLOTS] as Array<Number>;
        for (var i = 0; i < PW_SLOTS; i++) {
            _pwT[i] = 0;
            _pwV[i] = 0;
        }
    }

    //! Records one rider-power sample (raw value kept in powerW) and refreshes
    //! the 3 s moving average that the gauge draws. Called from the RX1 decoder
    //! and from the demo tick, so the window keeps filling even when another
    //! data page is displayed.
    public function setPower(w as Number) as Void {
        powerW = w;
        var now = System.getTimer();
        var i = _pwHead;
        _pwT[i] = now;
        _pwV[i] = w;
        _pwHead = (i + 1) % PW_SLOTS;
        if (_pwCount < PW_SLOTS) {
            _pwCount++;
        }
        _recomputePower3s(now);
    }

    //! Averages the samples of the last PW_WINDOW_MS ms. System.getTimer()
    //! wraps after ~24.8 days of uptime: an entry stamped ahead of now predates
    //! the wrap, so it counts as stale (same treatment as BleManager).
    private function _recomputePower3s(now as Number) as Void {
        var sum = 0;
        var n = 0;
        for (var k = 0; k < _pwCount; k++) {
            var idx = (_pwHead - _pwCount + k + PW_SLOTS * 2) % PW_SLOTS;
            var t = _pwT[idx];
            if (now >= t && now - t <= PW_WINDOW_MS) {
                sum += _pwV[idx];
                n++;
            }
        }
        if (n == 0) {
            powerW3s = powerW;
            return;
        }
        powerW3s = (sum + n / 2) / n;
    }

    public function reset() {
        connected = false;
        bikeName = null;
        speedKmh = null;
        powerW = null;
        powerW3s = null;
        _pwHead = 0;
        _pwCount = 0;
        motorPowerW = null;
        cadenceRpm = null;
        torqueNm = null;
        assistPercent = null;
        assistMode = null;
        batterySoc = null;
        rangeKm = null;
        temperatureC = null;
        altitudeM = null;
        odometerKm = null;
        tripTimeS = null;
        tripDistanceKm = null;
        avgSpeedKmh = null;
        maxSpeedKmh = null;
        lastUpdate = 0;
    }
}
