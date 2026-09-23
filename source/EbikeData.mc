import Toybox.Lang;

class EbikeData {
    public var connected as Boolean = false;
    public var bikeName as String? = null;
    public var speedKmh as Float? = null;
    public var powerW as Number? = null;
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

    //! Diagnostics for BLE trouble-shooting.
    public var profileStatus as Number = -1;
    public var pairOk as Boolean = false;
    public var serviceFound as Boolean = false;
    public var fd6dServiceFound as Boolean = false;
    public var rxCharFound as Boolean = false;
    public var cccdOk as Boolean = false;
    public var fd6dCccdOk as Boolean = false;
    public var rxCount as Number = 0;
    public var rxOtherCount as Number = 0;
    public var lastRxHex as String? = null;
    public var lastRxOtherHex as String? = null;
    public var lastError as String? = null;

    public function initialize() {
    }

    public function reset() {
        connected = false;
        bikeName = null;
        speedKmh = null;
        powerW = null;
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
        profileStatus = -1;
        pairOk = false;
        serviceFound = false;
        fd6dServiceFound = false;
        rxCharFound = false;
        cccdOk = false;
        fd6dCccdOk = false;
        rxCount = 0;
        rxOtherCount = 0;
        lastRxHex = null;
        lastRxOtherHex = null;
        lastError = null;
    }
}
