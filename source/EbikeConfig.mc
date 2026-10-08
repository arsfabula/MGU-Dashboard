import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.UserProfile;

const CFG_KEY_DEMO = "cfg.demo";
const CFG_KEY_LABELS = "cfg.labels";
const CFG_KEY_METRIC_MOTOR_POWER = "cfg.metric.motorpower";
const CFG_KEY_METRIC_CADENCE = "cfg.metric.cadence";
const CFG_KEY_METRIC_ASSIST = "cfg.metric.assist";
const CFG_KEY_METRIC_BATTERY = "cfg.metric.battery";
const CFG_KEY_METRIC_RANGE = "cfg.metric.range";
const CFG_KEY_ASSIST_LEVEL = "cfg.assist.level";
const CFG_KEY_FTP = "cfg.ftp";

//! On-device settings access.
class EbikeConfig {
    public static function isDemo() as Boolean {
        return _getBool($.CFG_KEY_DEMO, false);
    }

    public static function showLabels() as Boolean {
        return _getBool($.CFG_KEY_LABELS, true);
    }

    public static function isMetricEnabled(key as String) as Boolean {
        return _getBool(key, true);
    }

    //! Requested motor assist level (CoreMotorMode value): 0 = OFF, 1..4.
    public static function assistLevel() as Number {
        var v = _getInt($.CFG_KEY_ASSIST_LEVEL, 0);
        if (v < 0 || v > 4) {
            return 0;
        }
        return v;
    }

    //! Explicit rider FTP in watts set on the device: 0 means "auto", i.e. the
    //! field falls back to the user profile's cycling FTP, then to 200 W.
    public static function ftpOverride() as Number {
        var v = _getInt($.CFG_KEY_FTP, 0);
        if (v < 0 || v > 400) {
            return 0;
        }
        return v;
    }

    //! Rider FTP the "auto" setting actually resolves to: the user profile's
    //! cycling FTP when the API is exposed, otherwise 200 W. This is what the
    //! gauge scales against AND what the settings menu / picker show next to
    //! "Auto", so both always agree. The profile read is feature-gated
    //! (getFunctionalThresholdPower exists only from API 5.2.2 on a subset of
    //! bodies) and cached per session; a failed/absent read is retried on the
    //! next call and still yields 200 W.
    public static function autoFtp() as Number {
        var profile = _profileFtp;
        if (profile == null) {
            if (UserProfile has :getFunctionalThresholdPower) {
                try {
                    var v = UserProfile.getFunctionalThresholdPower(Activity.SPORT_CYCLING);
                    if (v instanceof Number && (v as Number) > 0) {
                        profile = v as Number;
                    }
                } catch (ex) {
                }
            }
            _profileFtp = profile;
        }
        if (profile != null && profile > 0) {
            return profile as Number;
        }
        return 200;
    }

    //! Profile FTP read once per session (null until it can be read).
    private static var _profileFtp as Number? = null;

    private static function _getInt(key as String, def as Number) as Number {
        var value = Application.Storage.getValue(key);
        if (value instanceof Number) {
            return value as Number;
        }
        return def;
    }

    private static function _getBool(key as String, def as Boolean) as Boolean {
        var value = Application.Storage.getValue(key);
        if (value == null) {
            return def;
        }
        if (value instanceof Boolean) {
            return value as Boolean;
        }
        return def;
    }
}
