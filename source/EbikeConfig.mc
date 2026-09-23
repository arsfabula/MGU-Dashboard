import Toybox.Application;
import Toybox.Lang;

const CFG_KEY_DEMO = "cfg.demo";
const CFG_KEY_LABELS = "cfg.labels";
const CFG_KEY_DEBUG = "cfg.debug";
const CFG_KEY_METRIC_POWER = "cfg.metric.power";
const CFG_KEY_METRIC_MOTOR_POWER = "cfg.metric.motorpower";
const CFG_KEY_METRIC_CADENCE = "cfg.metric.cadence";
const CFG_KEY_METRIC_ASSIST = "cfg.metric.assist";
const CFG_KEY_METRIC_BATTERY = "cfg.metric.battery";
const CFG_KEY_METRIC_RANGE = "cfg.metric.range";
const CFG_KEY_ASSIST_LEVEL = "cfg.assist.level";

//! On-device settings access.
class EbikeConfig {
    public static function isDemo() as Boolean {
        return _getBool($.CFG_KEY_DEMO, false);
    }

    public static function showLabels() as Boolean {
        return _getBool($.CFG_KEY_LABELS, true);
    }

    public static function isDebug() as Boolean {
        return _getBool($.CFG_KEY_DEBUG, false);
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
