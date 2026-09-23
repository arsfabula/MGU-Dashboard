import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class BleManager extends BluetoothLowEnergy.BleDelegate {
    //! Service advertised by the bike (16-bit 0xFD6D, seen by the watch scan).
    public const ADV_SERVICE_UUID = BluetoothLowEnergy.longToUuid(0x0000FD6D00001000L, 0x800000805F9B34FBL);
    //! Legacy BCP/CAP service: TX (5e8597ac) carries the BCP single-frame
    //! HEARTBEAT (BootUp/Operational/Stopped); RX (5e8597ab) carried ACK /
    //! CAP responses but its CCCD is refused on the real bike (st=18) and
    //! nothing arrives on it. The assist SDO write (setAssistLevel) and the
    //! old OT-style PDO handling are archived (archive/Assist.mc, archive/).
    public const SERVICE_UUID = BluetoothLowEnergy.longToUuid(0x5E8597AA69D911EAL, 0xBC550242AC130003L);
    public const RX_UUID = BluetoothLowEnergy.longToUuid(0x5E8597AB69D911EAL, 0xBC550242AC130003L);
    public const TX_UUID = BluetoothLowEnergy.longToUuid(0x5E8597AC69D911EAL, 0xBC550242AC130003L);

    private const HB_PERIOD_MS = 1800;
    private const HB_BOOTUP = 0;
    private const HB_OPERATIONAL = 5;
    private const HB_STOPPED = 4;

    //! Real stream: Sigma/FD6D service. 10 bytes on characteristic 00000001
    //! (RX1) = SIGMA_LIVE_RIDE_INFORMATION; 12 bytes on 00000003 (RX3) =
    //! SIGMA_LIVE_BATTERY_INFORMATION; RX2 (00000002, 10B) =
    //! SIGMA_LIVE_MOTOR_INFORMATION (MotorPower); RX7 (00000007, 2B) =
    //! SIGMA_BIKE_ASSISTANCE (AssistMode). RX1..RX8 map 1:1 to the Sitael
    //! SIGMA_MESSAGE_ID_TE (see docs/PROTOCOL.md §S.2); RX1/RX2/RX3/RX7 are
    //! decoded here (all four observed on the bike) — RX4..RX6/RX8 are probed
    //! and logged raw until their traffic is characterised (RX5 is observed
    //! but only logged raw).
    private const FD6D_NOTIFY_UUID = BluetoothLowEnergy.longToUuid(0x00000001ABAB4499L, 0xB9D7D0EFC0D06477L);
    private const FD6D_MOTOR_UUID = BluetoothLowEnergy.longToUuid(0x00000002ABAB4499L, 0xB9D7D0EFC0D06477L);
    private const FD6D_BATTERY_UUID = BluetoothLowEnergy.longToUuid(0x00000003ABAB4499L, 0xB9D7D0EFC0D06477L);
    private const FD6D_ASSISTANCE_UUID = BluetoothLowEnergy.longToUuid(0x00000007ABAB4499L, 0xB9D7D0EFC0D06477L);
    private const FD6D_FIRST_CHAR = 1;
    private const FD6D_LAST_CHAR = 8;

    private var _model as EbikeData;
    private var _sigma as Sigma;
    private var _txChar as BluetoothLowEnergy.Characteristic? = null;
    private var _lastHeartbeat as Number = 0;
    private var _bootPending as Boolean = false;
    //! Monotonic SDO request id (1..65535) for assist-level writes.
    private var _assistRequestId as Number = 1;
    //! BCP session id (0..31), incremented per transport frame so the bike
    //! sees every assist write as a fresh BCP session (the app increments it
    //! per message inside serializeMessageIntoBCPPackets).
    private var _bcpSessionId as Number = 0;
    //! FIT contributor the decoded data feeds. Set by the data field once the
    //! field is built; update() is invoked per received frame (below), so
    //! activity recording continues even while the field page isn't displayed.
    private var _fit as EbikeFitContributor? = null;

    //! Serialized write queue: CIQ only allows one BLE request in flight at a
    //! time ("Operation already in Progress" otherwise). Entries are
    //! dictionaries { :kind => :char | :desc, :target, :data, :log }.
    private var _writeQueue as Array<Dictionary> = [];
    private var _writeBusy as Boolean = false;
    private var _pendingLog as String = "";

    public function initialize(model as EbikeData) {
        BleDelegate.initialize();
        _model = model;
        _sigma = new Sigma();
        var profiles = _buildProfiles();
        for (var i = 0; i < profiles.size(); i++) {
            BluetoothLowEnergy.registerProfile(profiles[i]);
        }
        BluetoothLowEnergy.setDelegate(self);
    }

    public function startScan() as Void {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    //! Receives the FIT contributor so decoded frames can be recorded even
    //! when the data field is not the displayed page.
    public function setFitContributor(fit as EbikeFitContributor) as Void {
        _fit = fit;
    }

    public function stop() as Void {
        _sendHeartbeat(HB_STOPPED);
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
    }

    private function _buildProfiles() as Array<Dictionary> {
        //! AD profile: advertised service (16-bit 0xFD6D) used for scanning and
        //! pairing. Characteristics match those seen in the nRF Connect dump:
        //! 00000001..08 (notify candidates, with CCCD) + 0B/0E (write-only).
        var adProfile = {
            :uuid => ADV_SERVICE_UUID,
            :characteristics => _buildFd6dChars()
        };
        //! Legacy service kept only for the TX BCP heartbeat (the BCP/CAP/PDO
        //! data handling is archived in archive/; RX CCCD is refused st=18).
        var dataProfile = {
            :uuid => SERVICE_UUID,
            :characteristics => [
                {
                    :uuid => RX_UUID,
                    :descriptors => [BluetoothLowEnergy.cccdUuid()]
                },
                {
                    :uuid => TX_UUID
                }
            ]
        };
        return [adProfile, dataProfile];
    }

    private function _buildFd6dChars() as Array<Dictionary> {
        var chars = [];
        for (var i = FD6D_FIRST_CHAR; i <= FD6D_LAST_CHAR; i++) {
            chars.add({:uuid => _fd6dCharUuid(i), :descriptors => [BluetoothLowEnergy.cccdUuid()]});
        }
        //! 0000000B / 0000000E seen in the nRF dump without notification role.
        chars.add({:uuid => BluetoothLowEnergy.longToUuid(0x0000000BABAB4499L, 0xB9D7D0EFC0D06477L)});
        chars.add({:uuid => BluetoothLowEnergy.longToUuid(0x0000000EABAB4499L, 0xB9D7D0EFC0D06477L)});
        return chars;
    }

    //! Builds the 128-bit UUID 0000000X-ABAB-4499-B9D7-D0EFC0D06477 for X in
    //! 1..8 (the FD6D service characteristic index).
    private function _fd6dCharUuid(n as Number) as Uuid {
        return BluetoothLowEnergy.longToUuid(((n & 0xFF).toLong() << 32) | 0xABAB4499L, 0xB9D7D0EFC0D06477L);
    }

    public function onProfileRegister(uuid as Uuid, status as BluetoothLowEnergy.Status) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            System.println("BleManager: prof OK");
            if (uuid.equals(SERVICE_UUID)) {
                _model.profileStatus = 0;
            }
        } else {
            _model.profileStatus = status;
            System.println("BleManager: prof FAIL st=" + status);
        }
        WatchUi.requestUpdate();
    }

    public function onScanResults(scanResults as Iterator) as Void {
        System.println("BleManager: scan");
        while (true) {
            try {
                var result = scanResults.next();
                if (result == null) {
                    break;
                }
                if (result instanceof BluetoothLowEnergy.ScanResult) {
                    var scanResult = result as BluetoothLowEnergy.ScanResult;
                    System.println("BleManager:   rssi=" + scanResult.getRssi() + " name=" + scanResult.getDeviceName());
                    var uuids = scanResult.getServiceUuids();
                    while (true) {
                        var uuid = uuids.next();
                        if (uuid == null) {
                            break;
                        }
                        if (uuid.equals(ADV_SERVICE_UUID) || uuid.equals(SERVICE_UUID)) {
                            var name = scanResult.getDeviceName();
                            if (name != null && name.length() > 0) {
                                _model.bikeName = name;
                            }
                            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                            System.println("BleManager: pairing");
                            BluetoothLowEnergy.pairDevice(scanResult);
                            return;
                        }
                    }
                }
            } catch (ex) {
                _model.lastError = ex.getErrorMessage();
                System.println("BleManager: scan exc " + ex.getErrorMessage());
            }
        }
    }

    public function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        try {
            if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
                System.println("BleManager: CONNECTED");
                if (_model.bikeName == null || _model.bikeName.length() == 0) {
                    var name = device.getName();
                    if (name != null && name.length() > 0) {
                        _model.bikeName = name;
                    }
                }
                _queueReset();
                var service = device.getService(SERVICE_UUID);
                _model.serviceFound = (service != null);
                if (service != null) {
                    var tx = service.getCharacteristic(TX_UUID);
                    var rx = service.getCharacteristic(RX_UUID);
                    _txChar = tx;
                    _model.rxCharFound = (rx != null);
                    if (rx != null) {
                        var cccd = rx.getDescriptor(BluetoothLowEnergy.cccdUuid());
                        if (cccd != null) {
                            _queueDescriptorWrite(cccd, [0x01, 0x00]b, "rxC");
                        }
                    }
                } else {
                    System.println("BleManager: no 5e8597aa");
                }
                // The stream actually arrives on the Sigma/FD6D service.
                // Enable notifications on every 00000001..08 so we see vehicle
                // traffic on all of them (RIDE on 01, BATTERY on 03, ...).
                var fd6d = device.getService(ADV_SERVICE_UUID);
                _model.fd6dServiceFound = (fd6d != null);
                if (fd6d != null) {
                    _enableFd6dNotifications(fd6d);
                }
                _model.connected = true;
                _lastHeartbeat = 0;
                _bootPending = true;
            } else {
                System.println("BleManager: DISCONNECTED");
                _model.connected = false;
            }
            WatchUi.requestUpdate();
        } catch (ex) {
            _model.lastError = ex.getErrorMessage();
            System.println("BleManager: connect exception " + ex.getErrorMessage());
            WatchUi.requestUpdate();
        }
    }

    public function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as ByteArray) as Void {
        try {
            var t = System.getTimer();
            // Real stream: Sigma/FD6D service. Tag the characteristic so
            // probing 00000001..08 is readable (RX1..RX8).
            var uuid = characteristic.getUuid();
            var tag = _charTag(characteristic);
            _model.rxOtherCount += 1;
            var hexOther = _model.lastRxOtherHex;
            _model.lastRxOtherHex = _appendHex(hexOther, _hexC(value));
            var line = "BleManager: t=" + t + " " + tag + " " + value.size() + "B " + _hexC(value);
            if (uuid.equals(FD6D_NOTIFY_UUID) && value.size() == 10) {
                _sigma.parseRide(value, _model);
                _model.lastUpdate = t;
                line += _decoded(_model);
            } else if (uuid.equals(FD6D_MOTOR_UUID) && value.size() == 10) {
                _sigma.parseMotor(value, _model);
                _model.lastUpdate = t;
                line += _decodedMotor(value);
            } else if (uuid.equals(FD6D_BATTERY_UUID) && value.size() == 12) {
                _sigma.parseBattery(value, _model);
                _model.lastUpdate = t;
                line += _decodedBattery(value);
            } else if (uuid.equals(FD6D_ASSISTANCE_UUID) && value.size() == 2) {
                _sigma.parseAssist(value, _model);
                _model.lastUpdate = t;
                line += _decodedAssist(value);
            }
            System.println(line);
            WatchUi.requestUpdate();
            //! Heartbeat and FIT recording ride along on incoming RX traffic:
            //! this is the only periodic event source that keeps firing while
            //! the data field page is hidden (Toybox.Timer is not available
            //! to data fields). onTick() self-gates to HB_PERIOD_MS, and the
            //! contributor gates its 1 Hz average sampling, so neither
            //! duplicates work already done by the visible field's onUpdate.
            onTick();
            var fit = _fit;
            if (fit != null) {
                fit.update(_model);
            }
        } catch (ex) {
            _model.lastError = ex.getErrorMessage();
            System.println("BleManager: char exc " + ex.getErrorMessage());
            WatchUi.requestUpdate();
        }
    }

    //! Compact decoded summary of the last SIGMA RIDE values for one log line.
    private function _decoded(model as EbikeData) as String {
        var s = " ";
        var speed = model.speedKmh;
        s += speed == null ? "--" : speed.format("%.1f");
        s += "km/h ";
        var dist = model.tripDistanceKm;
        s += dist == null ? "--" : dist.format("%.1f");
        s += "km ";
        var power = model.powerW;
        s += power == null ? "--" : power.toString();
        s += "W ";
        var torque = model.torqueNm;
        s += torque == null ? "--" : torque.toString();
        s += "Nm ";
        var cad = model.cadenceRpm;
        s += cad == null ? "--" : cad.toString();
        s += "rpm";
        return s;
    }

    //! Compact decoded summary of a SIGMA motor report (RX2, 10 bytes): motor
    //! power W + raw torque/current/voltage/temperature + assistance % for
    //! field validation (the trailing % is RX2 [9], not the RX7 mode).
    private function _decodedMotor(value as ByteArray) as String {
        var s = " ";
        s += _sigma.u16(value, 0).toString();
        s += "W ";
        s += _sigma.u16(value, 2).toString();
        s += "Nm ";
        s += _sigma.u16(value, 4).toString();
        s += "A ";
        s += _sigma.u16(value, 6).toString();
        s += "V ";
        s += value[8].toString();
        s += "C assist";
        s += value[9].toString();
        s += "%";
        return s;
    }

    //! Compact decoded summary of a SIGMA assistance report (RX7, 2 bytes):
    //! active assist mode + start-up assistance flag.
    private function _decodedAssist(value as ByteArray) as String {
        var s = " mode=";
        s += value[0].toString();
        s += " start=";
        s += value[1].toString();
        return s;
    }

    //! Log tag RX1..RX8 computed from the FD6D characteristic UUID, so probes
    //! are readable regardless of which characteristic carries real data. BRX
    //! tags the legacy BCP RX characteristic (ACK / CAP responses).
    private function _charTag(characteristic as BluetoothLowEnergy.Characteristic) as String {
        var uuid = characteristic.getUuid();
        if (uuid.equals(RX_UUID)) {
            return "BRX";
        }
        for (var i = FD6D_FIRST_CHAR; i <= FD6D_LAST_CHAR; i++) {
            if (uuid.equals(_fd6dCharUuid(i))) {
                return "RX" + i.toString();
            }
        }
        return "RX?";
    }

    //! Compact decoded summary of a SIGMA battery report (12 bytes), for one
    //! log line: SOC %, range km, temperature.
    private function _decodedBattery(value as ByteArray) as String {
        var s = " ";
        s += value[0].toString();
        s += "% ";
        var range = _sigma.u16(value, 6);
        if (range == 0xFFFF) {
            s += "--";
        } else {
            s += range.toString();
        }
        s += "km ";
        s += value[5].toFloat().format("%.0f");
        s += "C";
        return s;
    }

    public function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        try {
            // Heartbeats fire constantly; only log failures to keep log size sane.
            if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
                System.println("BleManager: write " + _pendingLog + " st=" + status);
            }
            _queueDone();
        } catch (ex) {
            _model.lastError = ex.getErrorMessage();
            System.println("BleManager: write exc " + ex.getErrorMessage());
        }
    }

    public function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        try {
            System.println("BleManager: desc " + _pendingLog + " st=" + status);
            _queueDone();
        } catch (ex) {
            _model.lastError = ex.getErrorMessage();
            System.println("BleManager: descwrite exc " + ex.getErrorMessage());
        }
    }

    private function _queueReset() as Void {
        _writeQueue = [];
        _writeBusy = false;
        _pendingLog = "";
    }

    //! Enables notifications (CCCD = 0x0001) on every FD6D characteristic
    //! 00000001..08 present on the connected device, writing via the
    //! serialized queue so the watch only issues one BLE request at a time.
    private function _enableFd6dNotifications(fd6d as BluetoothLowEnergy.Service) as Void {
        for (var i = FD6D_FIRST_CHAR; i <= FD6D_LAST_CHAR; i++) {
            var char = fd6d.getCharacteristic(_fd6dCharUuid(i));
            if (char != null) {
                var cccd = char.getDescriptor(BluetoothLowEnergy.cccdUuid());
                if (cccd != null) {
                    _queueDescriptorWrite(cccd, [0x01, 0x00]b, "fdC" + i.toString());
                }
            }
        }
    }

    private function _queueDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, data as ByteArray, log as String) as Void {
        _writeQueue = _writeQueue.add({:kind => :desc, :target => descriptor, :data => data, :log => log});
        _queueDrain();
    }

    private function _queueCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, data as ByteArray, log as String) as Void {
        _writeQueue = _writeQueue.add({:kind => :char, :target => characteristic, :data => data, :log => log});
        _queueDrain();
    }

    private function _queueDone() as Void {
        _writeBusy = false;
        _queueDrain();
    }

    private function _queueDrain() as Void {
        if (_writeBusy || _writeQueue.size() == 0) {
            return;
        }
        var entry = _writeQueue[0];
        _writeQueue = _writeQueue.slice(1, _writeQueue.size());
        _writeBusy = true;
        _pendingLog = entry[:log] as String;
        try {
            if (entry[:kind] == :desc) {
                var desc = entry[:target] as BluetoothLowEnergy.Descriptor;
                desc.requestWrite(entry[:data] as ByteArray);
            } else {
                var char = entry[:target] as BluetoothLowEnergy.Characteristic;
                char.requestWrite(entry[:data] as ByteArray, {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
            }
        } catch (ex) {
            _model.lastError = ex.getErrorMessage();
            System.println("BleManager: queued write exc " + ex.getErrorMessage());
            _writeBusy = false;
            _queueDrain();
        }
    }

    public function onTick() as Void {
        if (!_model.connected) {
            return;
        }
        var now = System.getTimer();
        if (_bootPending) {
            _bootPending = false;
            _queueCharacteristicWriteCharSafe(HB_BOOTUP);
        } else if (now - _lastHeartbeat >= HB_PERIOD_MS) {
            _lastHeartbeat = now;
            _queueCharacteristicWriteCharSafe(HB_OPERATIONAL);
        }
    }

    private function _queueCharacteristicWriteCharSafe(status as Number) as Void {
        var tx = _txChar;
        if (tx == null) {
            return;
        }
        var frame = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]b;
        frame[0] = 0xC0 | 5;
        frame[1] = 0x00;
        frame[2] = 0x09;
        frame[3] = 0x02;
        frame[4] = 0x08;
        frame[5] = status;
        frame[6] = 0x00;
        _queueCharacteristicWrite(tx, frame, "hb" + status);
    }

    private function _sendHeartbeat(status as Number) as Void {
        _queueCharacteristicWriteCharSafe(status);
    }

    //! ARCHIVED / DISABLED (2026): assist-level writes were pulled from the
    //! build's call sites (see archive/Assist.mc and docs/PROTOCOL.md §A.7).
    //! This SDO_WRITE of SYSTEM_ASSISTANCE (index 9602, subIndex 6) on the
    //! BCP TX characteristic is kept for reference only and is no longer
    //! invoked by onUpdate (the menu entry + _syncAssist are off). Values are
    //! CoreMotorMode: 0 = OFF, 1..4 = GAIN_1..GAIN_4. The mode write must be
    //! followed by the "save" handshake (SAVE_GENERAL_SETTINGS/1 = "save"
    //! magic) to the REMOTE node that owns SYSTEM_ASSISTANCE and to the
    //! DRIVE_UNIT that executes it — the SDK's saveToPersist{Remote,Motor}
    //! path. Without it the change stays in RAM and reverts.
    public function setAssistLevel(level as Number) as Void {
        var tx = _txChar;
        if (tx == null) {
            return;
        }
        var frame = _buildAssistFrame(level);
        var log = "assist" + level.toString();
        System.println("BleManager: " + log + " tx=" + _hex(frame));
        _queueCharacteristicWrite(tx, frame, log);
        _queueCharacteristicWrite(tx, frame, log);
        _queueCharacteristicWrite(tx, frame, log);
        _sendPersist(1);
        _sendPersist(2);
    }

    //! SDO write of SAVE_GENERAL_SETTINGS (index 4112) subindex 1 carrying the
    //! "save" magic 0x65766173 (bytes LE 73 61 76 65) to `node` — the exact
    //! persist keyword the SDK's saveToPersistRemoteMemory (node 1) and
    //! saveToPersistMotorMemory (node 2) send after a settings write.
    private function _sendPersist(node as Number) as Void {
        var tx = _txChar;
        if (tx == null) {
            return;
        }
        var frame = _buildSdoWriteFrame(node, 4112, 1, [0x73, 0x61, 0x76, 0x65]b);
        System.println("BleManager: save" + node.toString() + " tx=" + _hex(frame));
        _queueCharacteristicWrite(tx, frame, "save" + node.toString());
        _queueCharacteristicWrite(tx, frame, "save" + node.toString());
    }

    //! Builds the 20-byte BCP single frame carrying a CAP SDO_WRITE for
    //! SYSTEM_ASSISTANCE. Layout (little-endian ids, matches the app's
    //! serializeMessageIntoBCPPackets + CAP_PACKET_SDO_WRITE.Serialize which
    //! PACKS the trailing bits):
    //! [0xC0|11+N]  BCP single-frame header (PacketID=3<<6 | DATA=0<<5 |
    //!              PayloadSize) — CAP message is 11 + N bytes
    //! [(s&31)<<3]  session id (incremented per frame) | SyncMsgType NO_ACK=0
    //! [0x09][0x02] BCP header (protocol CAP, sender APP, recipient REMOTE)
    //! [0x01]       CAP message type = SDO_WRITE
    //! [0x01]       (IsTimeout<<7)|(Unused<<5)|NodeID = 1 (NodeID REMOTE)
    //! [req lo][req hi] RequestID
    //! [0x82][0x25] SdoIndex = 9602 (SYSTEM_ASSISTANCE)
    //! [0x06]       SdoSubIndex
    //! [0x00]       SdoTimeout
    //! [0x01]       SdoDataLength
    //! [level]      mode
    //! [0x00 x6]    padding to the 18-byte BLE-comm payload
    private function _buildAssistFrame(level as Number) as ByteArray {
        return _buildSdoWriteFrame(1, 9602, 6, [level]b);
    }

    //! Generic 20-byte BCP single frame carrying a CAP SDO_WRITE of `data`
    //! to (node, index, subIndex). The CAP message is 3 + 8 + data.size()
    //! bytes: BCP header (0x09 0x02) + CAP type (0x01 SDO_WRITE) + SDO body
    //! (node, request LE2, index LE2, subIndex, timeout 0, length, data),
    //! zero-padded to the 18-byte payload field of the transport frame.
    //! NOTE: the frame must be allocated with a byte literal, NOT
    //! `new ByteArray[20]` — that leaves the unassigned padding cells as
    //! null, which makes `_hex` (data[i] & 0xFF) throw on the crash we hit.
    private function _buildSdoWriteFrame(node as Number, index as Number, subIndex as Number, data as ByteArray) as ByteArray {
        var capLen = 11 + data.size();
        var frame = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]b;
        frame[0] = 0xC0 | capLen;
        frame[1] = (_bcpSessionId & 0x1F) << 3;
        _bcpSessionId = (_bcpSessionId + 1) & 0x1F;
        frame[2] = 0x09;
        frame[3] = 0x02;
        frame[4] = 0x01;
        frame[5] = node & 0xFF;
        var req = _assistRequestId;
        _assistRequestId += 1;
        if (_assistRequestId > 0xFFFF) {
            _assistRequestId = 1;
        }
        frame[6] = req & 0xFF;
        frame[7] = (req >> 8) & 0xFF;
        frame[8] = index & 0xFF;
        frame[9] = (index >> 8) & 0xFF;
        frame[10] = subIndex & 0xFF;
        frame[11] = 0x00;
        frame[12] = data.size() & 0xFF;
        for (var i = 0; i < data.size(); i++) {
            frame[13 + i] = data[i];
        }
        return frame;
    }

    private function _hex(data as ByteArray) as String {
        var s = "";
        for (var i = 0; i < data.size(); i++) {
            var b = data[i] & 0xFF;
            s += b.format("%02x");
            if (i < data.size() - 1) {
                s += " ";
            }
        }
        return s;
    }

    //! Space-free hex used in the compact per-frame log lines.
    private function _hexC(data as ByteArray) as String {
        var s = "";
        for (var i = 0; i < data.size(); i++) {
            s += (data[i] & 0xFF).format("%02x");
        }
        return s;
    }

    //! Keep a small sliding window of the most recent frames (hex), newest last.
    private function _appendHex(old as String?, newHex as String) as String {
        var s = old == null ? "" : old;
        s += "|" + newHex;
        // Trim from the front to keep roughly the last 5 frames.
        while (s.length() > 260) {
            var cut = s.substring(1, s.length());
            var nxt = cut.find("|");
            if (nxt != null && nxt > 0) {
                s = cut.substring(nxt, cut.length());
            } else {
                s = cut;
            }
        }
        return s;
    }
}