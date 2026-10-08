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

    //! Position of the mandatory profile (Sigma/AD) in the _buildProfiles()
    //! array — see initialize() for why it is treated differently.
    private const PROFILE_INDEX_REQUIRED = 0;

    //! Number of registration attempts before giving BLE up for this run of
    //! the app, and the delay between two attempts. `static var` and not
    //! `const`: a const is an instance field in Monkey C and is unreachable
    //! from getShared(), which is a static method.
    private static var _maxInitFailures as Number = 3;
    private static var _initRetryMs as Number = 30000;

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
    //! False once stop() ran: the system keeps calling the delegate (there is
    //! no way to unregister it), so every callback must ignore late traffic
    //! instead of feeding a model nobody displays any more.
    private var _active as Boolean = true;
    //! False when the legacy BCP profile was refused by the device. The
    //! heartbeats are then silently impossible (no TX characteristic), but the
    //! Sigma stream is unaffected.
    private var _legacyProfileOk as Boolean = true;

    //! The one BLE manager per run of the app. GATT profiles live in a
    //! bounded table on the device and an application can only have one
    //! delegate, so building a second BleManager (a second registerProfile of
    //! the same UUIDs) is what killed onUpdate on an Edge 1030 — see
    //! getShared().
    private static var _shared as BleManager? = null;
    private static var _initFailures as Number = 0;
    private static var _nextRetryAt as Number = 0;
    private static var _lastNow as Number = 0;

    //! Serialized write queue: CIQ only allows one BLE request in flight at a
    //! time ("Operation already in Progress" otherwise). Entries are
    //! dictionaries { :kind => :char | :desc, :target, :data }.
    private var _writeQueue as Array<Dictionary> = [];
    private var _writeBusy as Boolean = false;

    //! NOTE: this may throw (registerProfile fails when the device's GATT
    //! profile table cannot take the definition) — hence the two-tier handling
    //! below. Never call it directly; go through getShared(), which contains
    //! the exception.
    public function initialize(model as EbikeData) {
        BleDelegate.initialize();
        _model = model;
        _sigma = new Sigma();
        var profiles = _buildProfiles();
        for (var i = 0; i < profiles.size(); i++) {
            if (i == PROFILE_INDEX_REQUIRED) {
                //! Mandatory: every decoded value (speed, power, battery,
                //! assist) arrives through the Sigma/AD profile. If the device
                //! refuses it there is nothing left to show, so let the
                //! exception reach getShared(), which turns it into a
                //! "BLE unavailable" field instead of a crash.
                BluetoothLowEnergy.registerProfile(profiles[i]);
            } else {
                //! Best effort: the legacy service carries only the TX BCP
                //! heartbeat. Losing it costs us the heartbeats, never the ride
                //! data — reported on an Edge Explore 2 (fw 31.33, ERA
                //! 2026-09-25) whose profile table refused the second
                //! definition. Registering both in one loop made that device
                //! lose the Sigma profile too.
                try {
                    BluetoothLowEnergy.registerProfile(profiles[i]);
                } catch (ex) {
                    _legacyProfileOk = false;
                }
            }
        }
        BluetoothLowEnergy.setDelegate(self);
    }

    //! The one BLE manager for this run of the app, or null when the GATT
    //! profiles cannot be registered (device profile table full, BLE stack
    //! busy, ...). Registration happens at most once, retries are bounded and
    //! spaced, and the caller gets a null instead of an exception — a failure
    //! here must degrade the data field to a "BLE unavailable" message, never
    //! kill it.
    public static function getShared(model as EbikeData) as BleManager? {
        var shared = _shared;
        if (shared != null) {
            //! The app rebuilds the model in onStart; re-point the manager
            //! instead of registering the profiles a second time.
            shared.setModel(model);
            return shared;
        }
        var now = System.getTimer();
        if (now < _lastNow) {
            //! System.getTimer() wraps around (~24.8 days of uptime). A stale
            //! _nextRetryAt would then block every retry for weeks.
            _nextRetryAt = 0;
        }
        _lastNow = now;
        if (_initFailures >= _maxInitFailures || now < _nextRetryAt) {
            return null;
        }
        try {
            shared = new BleManager(model);
            _shared = shared;
            return shared;
        } catch (ex) {
            _initFailures += 1;
            _nextRetryAt = now + _initRetryMs;
            //! ERA reports the backtrace but never the message, so this line
            //! is the only place the reason is ever written down.
            return null;
        }
    }

    public function isActive() as Boolean {
        return _active;
    }

    //! The model lives in EbikeData, which the app rebuilds on every start.
    public function setModel(model as EbikeData) as Void {
        _model = model;
    }

    public function startScan() as Void {
        _active = true;
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        } catch (ex) {
            _active = false;
        }
    }

    //! Receives the FIT contributor so decoded frames can be recorded even
    //! when the data field is not the displayed page.
    public function setFitContributor(fit as EbikeFitContributor) as Void {
        _fit = fit;
    }

    //! Stops the traffic. The manager object itself is kept (its profiles stay
    //! registered and the delegate cannot be unregistered), so leaving demo
    //! mode only restarts it through startScan() — it never registers twice.
    public function stop() as Void {
        _active = false;
        _model.connected = false;
        _bootPending = false;
        //! The bike expects the Stopped heartbeat, so it goes out before the
        //! TX characteristic reference is dropped.
        _sendHeartbeat(HB_STOPPED);
        _queueReset();
        _txChar = null;
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (ex) {
        }
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
        WatchUi.requestUpdate();
    }

    public function onScanResults(scanResults as Iterator) as Void {
        if (!_active) {
            return;
        }
        while (true) {
            try {
                if (!_active) {
                    break;
                }
                var result = scanResults.next();
                if (result == null) {
                    break;
                }
                if (result instanceof BluetoothLowEnergy.ScanResult) {
                    var scanResult = result as BluetoothLowEnergy.ScanResult;
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
                            BluetoothLowEnergy.pairDevice(scanResult);
                            return;
                        }
                    }
                }
            } catch (ex) {
            }
        }
    }

    public function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (!_active) {
            return;
        }
        try {
            if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
                if (_model.bikeName == null || _model.bikeName.length() == 0) {
                    var name = device.getName();
                    if (name != null && name.length() > 0) {
                        _model.bikeName = name;
                    }
                }
                _queueReset();
                if (_legacyProfileOk) {
                    var service = device.getService(SERVICE_UUID);
                    if (service != null) {
                        var tx = service.getCharacteristic(TX_UUID);
                        var rx = service.getCharacteristic(RX_UUID);
                        _txChar = tx;
                        if (rx != null) {
                            var cccd = rx.getDescriptor(BluetoothLowEnergy.cccdUuid());
                            if (cccd != null) {
                                _queueDescriptorWrite(cccd, [0x01, 0x00]b);
                            }
                        }
                    }
                }
                // The stream actually arrives on the Sigma/FD6D service.
                // Enable notifications on every 00000001..08 so we see vehicle
                // traffic on all of them (RIDE on 01, BATTERY on 03, ...).
                var fd6d = device.getService(ADV_SERVICE_UUID);
                if (fd6d != null) {
                    _enableFd6dNotifications(fd6d);
                }
                _model.connected = true;
                _lastHeartbeat = 0;
                _bootPending = true;
            } else {
                _model.connected = false;
            }
            WatchUi.requestUpdate();
        } catch (ex) {
            WatchUi.requestUpdate();
        }
    }

    public function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as ByteArray) as Void {
        if (!_active) {
            return;
        }
        try {
            var t = System.getTimer();
            // Real stream: Sigma/FD6D service. Tag the characteristic so
            // probing 00000001..08 is readable (RX1..RX8).
            var uuid = characteristic.getUuid();
            if (uuid.equals(FD6D_NOTIFY_UUID) && value.size() == 10) {
                _sigma.parseRide(value, _model);
                _model.lastUpdate = t;
            } else if (uuid.equals(FD6D_MOTOR_UUID) && value.size() == 10) {
                _sigma.parseMotor(value, _model);
                _model.lastUpdate = t;
            } else if (uuid.equals(FD6D_BATTERY_UUID) && value.size() == 12) {
                _sigma.parseBattery(value, _model);
                _model.lastUpdate = t;
            } else if (uuid.equals(FD6D_ASSISTANCE_UUID) && value.size() == 2) {
                _sigma.parseAssist(value, _model);
                _model.lastUpdate = t;
            }
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
            WatchUi.requestUpdate();
        }
    }

    public function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        if (!_active) {
            return;
        }
        try {
            // Heartbeats fire constantly; only log failures to keep log size sane.
            if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            }
            _queueDone();
        } catch (ex) {
        }
    }

    public function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        if (!_active) {
            return;
        }
        try {
            _queueDone();
        } catch (ex) {
        }
    }

    private function _queueReset() as Void {
        _writeQueue = [];
        _writeBusy = false;
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
                    _queueDescriptorWrite(cccd, [0x01, 0x00]b);
                }
            }
        }
    }

    private function _queueDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, data as ByteArray) as Void {
        _writeQueue = _writeQueue.add({:kind => :desc, :target => descriptor, :data => data});
        _queueDrain();
    }

    private function _queueCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, data as ByteArray) as Void {
        _writeQueue = _writeQueue.add({:kind => :char, :target => characteristic, :data => data});
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
        try {
            if (entry[:kind] == :desc) {
                var desc = entry[:target] as BluetoothLowEnergy.Descriptor;
                desc.requestWrite(entry[:data] as ByteArray);
            } else {
                var char = entry[:target] as BluetoothLowEnergy.Characteristic;
                char.requestWrite(entry[:data] as ByteArray, {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
            }
        } catch (ex) {
            _writeBusy = false;
            _queueDrain();
        }
    }

    public function onTick() as Void {
        if (!_active || !_model.connected) {
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
        _queueCharacteristicWrite(tx, frame);
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
        _queueCharacteristicWrite(tx, frame);
        _queueCharacteristicWrite(tx, frame);
        _queueCharacteristicWrite(tx, frame);
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
        _queueCharacteristicWrite(tx, frame);
        _queueCharacteristicWrite(tx, frame);
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
}
