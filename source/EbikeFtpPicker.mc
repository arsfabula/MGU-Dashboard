import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! FTP picker wheel: one column of watts, 0 (auto) to 400 W in 5 W steps.
//! 0 selects "auto": the field then reads the user profile FTP via
//! UserProfile.getFunctionalThresholdPower (feature-gated), then 200 W.
//! NumberPicker is not used because its modes are fixed (distance, weight,
//! time...), none fits watts; a custom Picker wheel is the standard route.
class EbikeFtpPickerFactory extends WatchUi.PickerFactory {
    public function initialize() {
        PickerFactory.initialize();
    }

    public function getSize() as Number {
        // 0..400 in 5 W steps -> 81 items.
        return 81;
    }

    public function getValue(item as Number) as Object or Null {
        return item * 5;
    }

    public function getDrawable(item as Number, isSelected as Boolean) as Drawable or Null {
        var value = item * 5;
        var label = value == 0
            ? WatchUi.loadResource(Rez.Strings.FtpAuto)
            : value.toString() + " " + WatchUi.loadResource(Rez.Strings.W);
        return new WatchUi.Text({
            :text => label,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER,
            :font => Graphics.FONT_MEDIUM,
            :color => Graphics.COLOR_WHITE
        });
    }
}

//! Persists the chosen FTP, refreshes the settings row, then pops back.
class EbikeFtpPickerDelegate extends WatchUi.PickerDelegate {
    private var _menu as EbikeSettingsMenu;

    public function initialize(menu as EbikeSettingsMenu) {
        PickerDelegate.initialize();
        _menu = menu;
    }

    public function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    public function onAccept(values as Array) as Boolean {
        var value = 0;
        if (values.size() > 0 && values[0] instanceof Number) {
            value = values[0] as Number;
        }
        Application.Storage.setValue($.CFG_KEY_FTP, value);
        _menu.onFtpChanged(value);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}