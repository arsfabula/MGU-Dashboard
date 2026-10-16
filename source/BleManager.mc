import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class BleManager extends BluetoothLowEnergy.BleDelegate {
    //! Service advertised by the bike (16-bit 0xFD6D, seen by the watch scan).
    public const ADV_SERVICE_UUID = BluetoothLowEnergy.longToUuid(0x0000FD6D00001000L, 0x800000805F9B34FBL);
    //! Legacy BCP/CAP service (5e8597aa): its TX characteristic (5e8597ac) used
    //! to carry the BCP single-frame HEARTBEAT and the assist SDO writes. It is
    //! **no longer registered** (2026-10-16): a watch whose GATT profile table
    //! refused the second definition filed an ERA "System Error" on every start
    //! (Edge Explore 2 fw 27.14, 2026-10-14, BleManager.initialize:115), and the
    //! ride data never needed it — everything is decoded on the Sigma/FD6D
    //! service below. The UUID stays as a scan filter so the bike is still
    //! identified and paired. See archive/Cap.mc.bak, archive/Bcp.mc.bak and
    //! docs/PROTOCOL.md.
    public const SERVICE_UUID = BluetoothLowEnergy.longToUuid(0x5E8597AA69D911EAL, 0xBC550242AC130003L);

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
    //! FIT contributor the decoded data feeds. Set by the data field once the
    //! field is built; update() is invoked per received frame (below), so
    //! activity recording continues even while the field page isn't displayed.
    private var _fit as EbikeFitContributor? = null;
    //! False once stop() ran: the system keeps calling the delegate (there is
    //! no way to unregister it), so every callback must ignore late traffic
    //! instead of feeding a model nobody displays any more.
    private var _active as Boolean = true;

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
    //! dictionaries { :target, :data }.
    private var _writeQueue as Array<Dictionary> = [];
    private var _writeBusy as Boolean = false;

    //! NOTE: this may throw (registerProfile fails when the device's GATT
    //! profile table cannot take the definition). Never call it directly; go
    //! through getShared(), which contains the exception.
    public function initialize(model as EbikeData) {
        BleDelegate.initialize();
        _model = model;
        _sigma = new Sigma();
        var profiles = _buildProfiles();
        for (var i = 0; i < profiles.size(); i++) {
            //! The Sigma/AD profile is the only one left (the legacy BCP
            //! profile was dropped, see SERVICE_UUID): every decoded value
            //! (speed, power, battery, assist) arrives through it, so if the
            //! device refuses it there is nothing to show and the exception
            //! must reach getShared(), which turns it into a "BLE
            //! unavailable" field instead of a crash.
            BluetoothLowEnergy.registerProfile(profiles[i]);
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
        _queueReset();
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
        return [adProfile];
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
                //! The stream actually arrives on the Sigma/FD6D service.
                // Enable notifications on every 00000001..08 so we see vehicle
                // traffic on all of them (RIDE on 01, BATTERY on 03, ...).
                var fd6d = device.getService(ADV_SERVICE_UUID);
                if (fd6d != null) {
                    _enableFd6dNotifications(fd6d);
                }
                _model.connected = true;
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
            //! FIT recording rides along on incoming RX traffic: this is the only
            //! periodic event source that keeps firing while the data field
            //! page is hidden (Toybox.Timer is not available to data fields).
            //! The contributor gates its 1 Hz average sampling, so it never
            //! duplicates work already done by the visible field's onUpdate.
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
        _writeQueue = _writeQueue.add({:target => descriptor, :data => data});
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
            var desc = entry[:target] as BluetoothLowEnergy.Descriptor;
            desc.requestWrite(entry[:data] as ByteArray);
        } catch (ex) {
            _writeBusy = false;
            _queueDrain();
        }
    }
}
