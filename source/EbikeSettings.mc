import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The app settings menu, shown directly when the user opens the
//! on-device settings flow (activity settings -> Connect IQ Fields -> eBike).
class EbikeSettingsMenu extends WatchUi.Menu2 {
    private var _ftpItem as WatchUi.MenuItem;

    public function initialize() {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.Title)});
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.DemoMode), null, $.CFG_KEY_DEMO, EbikeConfig.isDemo(), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Labels), null, $.CFG_KEY_LABELS, EbikeConfig.showLabels(), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.MotorPower), null, $.CFG_KEY_METRIC_MOTOR_POWER, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_MOTOR_POWER), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Cadence), null, $.CFG_KEY_METRIC_CADENCE, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_CADENCE), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Assistance), null, $.CFG_KEY_METRIC_ASSIST, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_ASSIST), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Battery), null, $.CFG_KEY_METRIC_BATTERY, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_BATTERY), null));
        addItem(new WatchUi.ToggleMenuItem(WatchUi.loadResource(Rez.Strings.Range), null, $.CFG_KEY_METRIC_RANGE, EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_RANGE), null));
        var ftpItem = new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Ftp), _ftpLabel(EbikeConfig.ftpOverride()), $.CFG_KEY_FTP, null);
        _ftpItem = ftpItem;
        addItem(ftpItem);
    }

    //! "Auto" plus the watts that auto actually resolves to (profile FTP, else
    //! 200 W), otherwise the watts value. The menu row and the picker wheel
    //! share this, so both show the same resolved number.
    public static function _ftpLabel(ftp as Number) as String {
        if (ftp <= 0) {
            return WatchUi.loadResource(Rez.Strings.FtpAuto) + " " +
                EbikeConfig.autoFtp().toString() + " " +
                WatchUi.loadResource(Rez.Strings.W);
        }
        return ftp.toString() + " " + WatchUi.loadResource(Rez.Strings.W);
    }

    //! Pushes the FTP picker wheel with the current value pre-selected.
    public function onFtpSelected() as Void {
        var factory = new $.EbikeFtpPickerFactory();
        var picker = new WatchUi.Picker({
            :title => new WatchUi.Text({
                :text => WatchUi.loadResource(Rez.Strings.Ftp),
                :locX => WatchUi.LAYOUT_HALIGN_CENTER,
                :locY => WatchUi.LAYOUT_VALIGN_CENTER,
                :font => Graphics.FONT_MEDIUM,
                :color => Graphics.COLOR_WHITE
            }),
            :pattern => [factory],
            :defaults => [(EbikeConfig.ftpOverride() / 5).toNumber()]
        });
        WatchUi.pushView(picker, new $.EbikeFtpPickerDelegate(self), WatchUi.SLIDE_IMMEDIATE);
    }

    //! Updates the FTP row sublabel once a picker value is accepted.
    public function onFtpChanged(current as Number) as Void {
        _ftpItem.setSubLabel(_ftpLabel(current));
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
            var id = menuItem.getId();
            if (id != null && id.equals($.CFG_KEY_FTP)) {
                _menu.onFtpSelected();
            }
        }
    }
}
