import Toybox.Lang;
import Toybox.System;

const CAP_TYPE_PDO = 7;
const CAP_TYPE_HEARTBEAT = 8;

class Cap {
    public function initialize() {
    }

    public function parse(packet as ByteArray) as CapFrame? {
        if (packet.size() < 3) {
            return null;
        }
        var b0 = packet[0];
        var b1 = packet[1];
        var protocol = (b0 >> 3) & 0x07;
        if (protocol != 1) {
            return null;
        }
        var recipient = (b1 >> 3) & 0x07;
        if (recipient != 2) {
            return null;
        }
        var type = packet[2];
        if (type != CAP_TYPE_PDO && type != CAP_TYPE_HEARTBEAT) {
            if (EbikeConfig.isDebug()) {
                System.println("CAP type=" + type.toString() + " hex=" + _hex(packet));
            }
            return null;
        }
        return new CapFrame(type, packet.slice(3, packet.size()));
    }

    private function _hex(data as ByteArray) as String {
        var out = "";
        for (var i = 0; i < data.size(); i++) {
            var v = data[i];
            var hi = (v >> 4) & 0x0F;
            var lo = v & 0x0F;
            out += "0123456789ABCDEF".substring(hi, hi + 1);
            out += "0123456789ABCDEF".substring(lo, lo + 1);
        }
        return out;
    }
}

class CapFrame {
    public var type as Number;
    public var data as ByteArray;

    public function initialize(t as Number, d as ByteArray) {
        type = t;
        data = d;
    }
}
