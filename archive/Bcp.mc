import Toybox.Lang;

class Bcp {
    private const FRAME_SIZE = 20;
    private const MAX_ASSEMBLY = 500;

    private var _buffer as ByteArray? = null;
    private var _expectedSize as Number = 0;
    private var _expectedCrc as Number = 0;
    private var _frameId as Number = -1;

    public function initialize() {
    }

    public function push(frame as ByteArray) as Array<ByteArray> {
        var result = new Array<ByteArray>[0];
        if (frame.size() < FRAME_SIZE) {
            return result;
        }
        var b0 = frame[0];
        if ((b0 & 0xE0) == 0xE0) {
            return result;
        }
        if ((b0 & 0xC0) == 0xC0) {
            var len = b0 & 0x1F;
            if (len > 0 && len <= 18) {
                result = result.add(frame.slice(2, 2 + len));
            }
            return result;
        }
        var frameId = b0 & 0x3F;
        if ((b0 & 0x80) != 0) {
            var size = (frame[2] << 8) | frame[1];
            if (size <= 0 || size > MAX_ASSEMBLY) {
                _reset();
                return result;
            }
            _expectedSize = size;
            _expectedCrc = (frame[4] << 8) | frame[3];
            _frameId = frameId;
            _buffer = frame.slice(8, FRAME_SIZE);
            return result;
        }
        var buf = _buffer;
        if (buf == null || _frameId != frameId) {
            return result;
        }
        var needed = _expectedSize - buf.size();
        if (needed <= 0) {
            _reset();
            return result;
        }
        var take = needed;
        if (take > 19) {
            take = 19;
        }
        var isStop = (b0 & 0x40) != 0;
        for (var i = 0; i < take; i++) {
            buf = buf.add(frame[1 + i]);
        }
        if (isStop || take == needed) {
            var expected = _expectedCrc;
            _reset();
            if (crc16(buf, 0, buf.size()) == expected) {
                result = result.add(buf);
            }
        } else {
            _buffer = buf;
        }
        return result;
    }

    private function _reset() as Void {
        _buffer = null;
        _expectedSize = 0;
        _expectedCrc = 0;
        _frameId = -1;
    }

    public function crc16(data as ByteArray, offset as Number, length as Number) as Number {
        var crc = 0xFFFF;
        for (var i = offset; i < offset + length; i++) {
            crc = crc ^ (data[i] << 8);
            for (var j = 0; j < 8; j++) {
                if ((crc & 0x8000) != 0) {
                    crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
                } else {
                    crc = (crc << 1) & 0xFFFF;
                }
            }
        }
        return crc;
    }
}
