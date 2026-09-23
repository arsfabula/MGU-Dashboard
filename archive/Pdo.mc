import Toybox.Lang;
import Toybox.System;

class Pdo {
    public function initialize() {
    }

    public function parse(cap as CapFrame, model as EbikeData) as Void {
        if (cap.type != CAP_TYPE_PDO) {
            return;
        }
        var data = cap.data;
        if (data.size() < 2) {
            return;
        }
        var numFrames = data[1];
        var offset = 2;
        for (var i = 0; i < numFrames; i++) {
            if (offset + 10 > data.size()) {
                break;
            }
            var canId = ((data[offset] & 0x07) << 8) | data[offset + 1];
            _dispatch(canId, data.slice(offset + 2, offset + 10), model);
            offset += 10;
        }
    }

    private function _dispatch(canId as Number, d as ByteArray, model as EbikeData) as Void {
        switch (canId) {
            case 0x281:
                _parsePdo1(d, model);
                break;
            case 0x2A1:
                _parsePdo2(d, model);
                break;
            case 0x2C1:
                _parsePdo3(d, model);
                break;
            case 0x2E1:
                _parsePdo4(d, model);
                break;
            case 0x301:
                _parsePdo5(d, model);
                break;
            case 0x321:
            case 0x341:
            case 0x361:
            case 0x261:
            case 0x3A1:
            default:
                if (EbikeConfig.isDebug()) {
                    System.println("CAN 0x" + _hex2(canId) + " " + _hex(d));
                }
                break;
        }
    }

    private function _parsePdo1(d as ByteArray, model as EbikeData) as Void {
        var speed = _u16(d, 0);
        if (speed != 0xFFFF) {
            model.speedKmh = speed / 10.0;
        }
        var power = _u16(d, 2);
        if (power != 0xFFFF) {
            model.powerW = power;
        }
        var cadence = _s16(d, 4);
        if (cadence != -1) {
            model.cadenceRpm = cadence;
        }
        var assist = d[7];
        if (assist > 127) {
            assist -= 256;
        }
        if (assist != -1) {
            model.assistPercent = assist;
        }
    }

    private function _parsePdo2(d as ByteArray, model as EbikeData) as Void {
        var alt = _s16(d, 0);
        if (alt != -1) {
            model.altitudeM = alt;
        }
    }

    private function _parsePdo3(d as ByteArray, model as EbikeData) as Void {
        var range = _u16(d, 0);
        if (range != 0xFFFF) {
            model.rangeKm = range;
        }
        var soc = d[2];
        if (soc != 0xFF) {
            model.batterySoc = soc;
        }
        var temp = d[7];
        if (temp > 127) {
            temp -= 256;
        }
        if (temp != 127 && temp != -127 && temp != -128) {
            model.temperatureC = temp / 2.0;
        }
    }

    private function _parsePdo4(d as ByteArray, model as EbikeData) as Void {
        var odo = _u32(d, 0);
        if (odo != 0xFFFFFFFF) {
            model.odometerKm = odo / 10.0;
        }
    }

    private function _parsePdo5(d as ByteArray, model as EbikeData) as Void {
        var time = _u16(d, 0);
        if (time != 0xFFFF) {
            model.tripTimeS = time;
        }
        var dist = _u16(d, 2);
        if (dist != 0xFFFF) {
            model.tripDistanceKm = dist / 10.0;
        }
        var avg = _u16(d, 4);
        if (avg != 0xFFFF) {
            model.avgSpeedKmh = avg / 10.0;
        }
        var max = _u16(d, 6);
        if (max != 0xFFFF) {
            model.maxSpeedKmh = max / 10.0;
        }
    }

    private function _u16(d as ByteArray, i as Number) as Number {
        return (d[i + 1] << 8) | d[i];
    }

    private function _hex2(v as Number) as String {
        var hi = (v >> 8) & 0xFF;
        var lo = v & 0xFF;
        return _byteHex(hi) + _byteHex(lo);
    }

    private function _hex(d as ByteArray) as String {
        var out = "";
        for (var i = 0; i < d.size(); i++) {
            out += _byteHex(d[i]);
        }
        return out;
    }

    private function _byteHex(v as Number) as String {
        var table = "0123456789ABCDEF";
        return table.substring((v >> 4) & 0x0F, ((v >> 4) & 0x0F) + 1)
            + table.substring(v & 0x0F, (v & 0x0F) + 1);
    }

    private function _s16(d as ByteArray, i as Number) as Number {
        var v = _u16(d, i);
        if (v > 0x7FFF) {
            v -= 0x10000;
        }
        return v;
    }

    private function _u32(d as ByteArray, i as Number) as Number {
        return ((d[i + 3] << 24) | (d[i + 2] << 16) | (d[i + 1] << 8) | d[i]) & 0xFFFFFFFF;
    }
}
