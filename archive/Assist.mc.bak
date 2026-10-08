import Toybox.Lang;
import Toybox.System;

//! ARCHIVE — interaction mode d'assistance avec le vélo (mise de côté).
//! Ce fichier n'est PAS compilé (le build n'englobe pas archive/). Il garde
//! la référence complète de ce qui a été désactivé :
//!   - source/BleManager.mc  : setAssistLevel / _sendPersist /
//!                             _buildSdoWriteFrame / _buildAssistFrame (conservés)
//!   - source/EbikeField.mc   : _syncAssist (conservé, appel commenté dans onUpdate)
//!   - source/EbikeSettings.mc: item de menu (commenté) + onAssistSelected (conservé)
//! Pour réactiver : décommenter _syncAssist(ble) dans onUpdate (EbikeField.mc:117)
//! et, au besoin, l'item _assistItem dans EbikeSettings.mc.

//! Envoie un SDO_WRITE de SYSTEM_ASSISTANCE (index 9602, subIndex 6), trame
//! BCP single 20 octets, 3x. Valeurs CoreMotorMode : 0=OFF, 1..4=GAIN_1..4.
//! Suivi du handshake "save" (SAVE_GENERAL_SETTINGS 4112/1 = magic 73 61 76 65
//! « save ») vers le nœud REMOTE (1) puis DRIVE_UNIT (2) — sans lui le
//! changement reste en RAM et revient.
class Assist {
    public const CAN_NODE_REMOTE = 1;
    public const CAN_NODE_DRIVE_UNIT = 2;
    public const SYSTEM_ASSISTANCE = 9602;
    public const SAVE_GENERAL_SETTINGS = 4112;
    public const CORE_MOTOR_MODE_OFF = 0;

    //! Layout du frame (little-endian, identique à l'app SDK) :
    //! [0xC0|11+N]  header BCP single-frame (CAP = 11 + N octets)
    //! [(s&31)<<3]  session id | SyncMsgType NO_ACK=0
    //! [0x09][0x02] BCP header (protocol CAP, APP -> REMOTE)
    //! [0x01]       CAP SDO_WRITE
    //! [0x01]       (IsTimeout<<7)|(Unused<<5)|NodeID
    //! [req lo][req hi] RequestID
    //! [0x82][0x25] SdoIndex
    //! [0x06]       SdoSubIndex
    //! [0x00]       SdoTimeout
    //! [0x01]       SdoDataLength
    //! [level]      mode
    //! [0x00 x6]    padding 18 octets BLE-comm
    public function buildAssistFrame(level as Number, sessionId as Number) as ByteArray {
        // NE PAS utiliser `new ByteArray[20]` : le padding non affecté reste
        // null et _hex (data[i] & 0xFF) lève une exception (crash au boot).
        var frame = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]b;
        var capLen = 11 + 1;
        frame[0] = 0xC0 | capLen;
        frame[1] = (sessionId & 0x1F) << 3;
        frame[2] = 0x09;
        frame[3] = 0x02;
        frame[4] = 0x01;
        frame[5] = CAN_NODE_REMOTE;
        frame[6] = 0x01; // RequestID bas
        frame[7] = 0x00; // RequestID haut
        frame[8] = SYSTEM_ASSISTANCE & 0xFF;
        frame[9] = (SYSTEM_ASSISTANCE >> 8) & 0xFF;
        frame[10] = 0x06; // SdoSubIndex
        frame[11] = 0x00; // SdoTimeout
        frame[12] = 0x01; // SdoDataLength
        frame[13] = level & 0xFF;
        return frame;
    }

    //! Frame "save" vers `node` (1 REMOTE / 2 DRIVE_UNIT / 3 DISPLAY).
    public function buildSaveFrame(node as Number, sessionId as Number) as ByteArray {
        var frame = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]b;
        var capLen = 11 + 4;
        frame[0] = 0xC0 | capLen;
        frame[1] = (sessionId & 0x1F) << 3;
        frame[2] = 0x09;
        frame[3] = 0x02;
        frame[4] = 0x01;
        frame[5] = node & 0xFF;
        frame[6] = 0x01;
        frame[7] = 0x00;
        frame[8] = SAVE_GENERAL_SETTINGS & 0xFF;
        frame[9] = (SAVE_GENERAL_SETTINGS >> 8) & 0xFF;
        frame[10] = 0x01;   // SdoSubIndex 1
        frame[11] = 0x00;   // SdoTimeout
        frame[12] = 0x04;   // SdoDataLength
        frame[13] = 0x73;
        frame[14] = 0x61;
        frame[15] = 0x76;
        frame[16] = 0x65;   // 0x65766173 LE = « save »
        return frame;
    }

    //! Sync auto du niveau à la connexion (EbikeField._syncAssist) :
    //! var level = EbikeConfig.assistLevel();
    //! ble.setAssistLevel(level);
    public static function hex(data as ByteArray) as String {
        var s = "";
        for (var i = 0; i < data.size(); i++) {
            s += (data[i] & 0xFF).format("%02x");
        }
        return s;
    }
}