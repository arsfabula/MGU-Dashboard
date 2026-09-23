import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The app settings menu, shown directly when the user opens the
//! on-device settings flow (activity settings -> Connect IQ Fields -> eBike).
class EbikeSettingsMenu extends WatchUi.Menu2 {
    private var _assistItem as WatchUi.MenuItem;
    private var _ble as BleManager? = null;

    public function initialize(ble as BleManager?) {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.Title)});
        _ble = ble;
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.DemoMode), null, $.CFG_KEY_DEMO, EbikeConfig.isDemo(), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Labels), null, $.CFG_KEY_LABELS, EbikeConfig.showLabels(), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.CyclistPower), null, $.CFG_KEY_METRIC_POWER, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_POWER), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.MotorPower), null, $.CFG_KEY_METRIC_MOTOR_POWER, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_MOTOR_POWER), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Cadence), null, $.CFG_KEY_METRIC_CADENCE, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_CADENCE), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Assistance), null, $.CFG_KEY_METRIC_ASSIST, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_ASSIST), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Battery), null, $.CFG_KEY_METRIC_BATTERY, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_BATTERY), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Range), null, $.CFG_KEY_METRIC_RANGE, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_RANGE), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Debug), null, $.CFG_KEY_DEBUG, EbikeConfig.isDebug(), null));
        //! Niveau d'assistance retiré du menu (fonctionnalité mise de côté).
        //! Le code (création de l'item, onAssistSelected, _assistLabel) est
        //! conservé : décommenter ces deux lignes pour le réactiver.
        //_assistItem = new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.AssistLevel), _assistLabel(EbikeConfig.assistLevel()), "assist", null);
        //addItem(_assistItem);
    }

    //! "OFF" for level 0, otherwise the level number (1..4).
    public static function _assistLabel(level as Number) as String {
        if (level <= 0) {
            return WatchUi.loadResource(Rez.Strings.AssistOff);
        }
        return level.toString();
    }

    //! Cycles the assist level (OFF -> 1 -> 2 -> 3 -> 4 -> OFF), persists it,
    //! immediately pushes it to the bike, updates the row and forces the menu
    //! to redraw. Kept on the menu itself (which owns the item) so nothing
    //! depends on Menu2 id lookups.
    public function onAssistSelected() as Void {
        var next = (EbikeConfig.assistLevel() + 1) % 5;
        Application.Storage.setValue($.CFG_KEY_ASSIST_LEVEL, next);
        var ble = _ble;
        if (ble != null) {
            ble.setAssistLevel(next);
        }
        _assistItem.setSubLabel(_assistLabel(next));
        System.println("EbikeSettings: assist -> " + next.toString());
        WatchUi.requestUpdate();
    }
}

//! Input handler for the app settings menu.
class EbikeSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _menu as EbikeSettingsMenu;

    public function initialize(menu as EbikeSettingsMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    public function onSelect(menuItem as MenuItem) as Void {
        if (menuItem instanceof ToggleMenuItem) {
            Application.Storage.setValue(menuItem.getId() as String, menuItem.isEnabled());
        } else {
            _menu.onAssistSelected();
        }
    }
}
