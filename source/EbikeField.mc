import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

class EbikeDataField extends WatchUi.DataField {
    private var _model as EbikeData;
    private var _ble as BleManager?;
    private var _demo as DemoManager?;
    private var _fit as EbikeFitContributor?;
    private var _lastValueFont as FontType;
    //! Last assist level sent to the bike, and whether we were connected, so a
    //! change in the setting (or a new connection) triggers a write.
    private var _lastAssistSent as Number? = null;

    public function initialize(model as EbikeData, ble as BleManager?, demo as DemoManager?) {
        DataField.initialize();
        _model = model;
        _ble = ble;
        _demo = demo;
        var fit = new EbikeFitContributor(self);
        _fit = fit;
        //! Wire the FIT contributor into the BLE manager so decoded frames are
        //! recorded even when this field page isn't displayed (onUpdate only
        //! runs while visible, but the BLE callbacks keep firing).
        if (ble != null) {
            ble.setFitContributor(fit);
        }
        _lastValueFont = Graphics.FONT_XTINY;
    }

    //! Make sure the correct data source (demo vs BLE) matches the current
    //! settings, switching if the user changed the mode while this field
    //! instance was kept alive. Returns the current demo mode.
    public function onTimerStart() as Void {
        var fit = _fit;
        if (fit != null) {
            fit.onTimerStart();
        }
    }

    public function onTimerResume() as Void {
        var fit = _fit;
        if (fit != null) {
            fit.onTimerResume();
        }
    }

    public function onTimerPause() as Void {
        var fit = _fit;
        if (fit != null) {
            fit.onTimerPause();
        }
    }

    public function onTimerStop() as Void {
        var fit = _fit;
        if (fit != null) {
            fit.onTimerStop();
        }
    }

    public function onTimerLap() as Void {
        var fit = _fit;
        if (fit != null) {
            fit.onTimerLap();
        }
    }

    public function onTimerReset() as Void {
        var fit = _fit;
        if (fit != null) {
            fit.onTimerReset();
        }
    }

    //! Pushes the configured assist level to the bike once per connection and
    //! again whenever the setting changes.
    //! NOTE: disabled / archived (see archive/Assist.mc) — the call site in
    //! onUpdate is commented out so no assist level is ever sent to the bike.
    private function _syncAssist(ble as BleManager) as Void {
        if (!_model.connected) {
            _lastAssistSent = null;
            return;
        }
        var level = EbikeConfig.assistLevel();
        var last = _lastAssistSent;
        if (last == null || level != last) {
            _lastAssistSent = level;
            ble.setAssistLevel(level);
        }
    }

    private function _ensureMode() as Boolean {
        var demoMode = EbikeConfig.isDemo();
        if (demoMode) {
            if (_demo == null) {
                _demo = new DemoManager(_model);
                var ble = _ble;
                if (ble != null) {
                    ble.stop();
                    _ble = null;
                }
            }
        } else {
            _demo = null;
            if (_ble == null) {
                _ble = new BleManager(_model);
                _ble.startScan();
            }
        }
        return demoMode;
    }

    public function onUpdate(dc as Dc) as Void {
        var demoMode = _ensureMode();
        var demo = _demo;
        var ble = _ble;
        if (demo != null) {
            demo.onTick();
        } else if (ble != null) {
            ble.onTick();
            //! Interaction d'assistance (envoi du niveau au vélo) désactivée /
            //! archivée — voir archive/Assist.mc. Décommenter pour réactiver.
            //_syncAssist(ble);
        }

        var fit = _fit;
        if (fit != null) {
            fit.update(_model);
        }

        var bg = getBackgroundColor();
        var fg = Graphics.COLOR_WHITE;
        if (bg == Graphics.COLOR_WHITE) {
            fg = Graphics.COLOR_BLACK;
        }
        dc.setColor(fg, bg);
        dc.clear();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);

        var safe = _computeSafeRect(dc);
        var x = safe[:x] as Number;
        var y = safe[:y] as Number;
        var w = safe[:w] as Number;
        var h = safe[:h] as Number;

        var model = _model;
        if (!demoMode && !model.connected) {
            dc.drawText(x + w / 2, y + h / 2, _stateFont(h), WatchUi.loadResource(Rez.Strings.Scanning), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (!demoMode && model.batterySoc == null && System.getTimer() - model.lastUpdate > 10000) {
            dc.drawText(x + w / 2, y + h / 2, _stateFont(h), WatchUi.loadResource(Rez.Strings.Waiting), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        _drawMetrics(dc, model, safe);
    }

    //! Inset each edge that is cut by the (non-rectangular) screen shape so
    //! that content stays inside the visible area. On rectangular screens no
    //! edge is obscured, so the whole field remains usable.
    private function _computeSafeRect(dc as Dc) as Dictionary {
        var flags = getObscurityFlags();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var top = 0;
        var bottom = 0;
        var left = 0;
        var right = 0;
        if ((flags & OBSCURE_TOP) != 0) {
            top = _obscureInsetTop(w);
        }
        if ((flags & OBSCURE_BOTTOM) != 0) {
            bottom = _obscureInsetTop(w);
        }
        if ((flags & OBSCURE_LEFT) != 0) {
            left = _obscureInsetSide(w);
        }
        if ((flags & OBSCURE_RIGHT) != 0) {
            right = _obscureInsetSide(w);
        }
        return {
            :x => left,
            :y => top,
            :w => w - left - right,
            :h => h - top - bottom,
            :flags => flags,
            :top => top,
            :bottom => bottom,
            :left => left,
            :right => right
        };
    }

    //! Top/bottom edges are cut deep on a round screen (the band narrows at the
    //! poles), so they get a larger inset than the left/right edges which are
    //! only shallowly cut near the horizontal center.
    private function _obscureInsetTop(w as Number) as Number {
        var v = w / 10;
        if (v < 8) {
            v = 8;
        }
        return v;
    }

    private function _obscureInsetSide(w as Number) as Number {
        var v = w / 20;
        if (v < 8) {
            v = 8;
        }
        return v;
    }

    //! Title band is only drawn when the field is big enough to spare the space.
    private function _titleHeight(w as Number, h as Number) as Number {
        if (w < 120 || h < 70) {
            return 0;
        }
        return Graphics.getFontHeight(Graphics.FONT_XTINY) + 2;
    }

    //! Shorten a (BLE device) name so it fits in maxW pixels at FONT_XTINY.
    private function _fitTitle(dc as Dc, name as String, maxW as Number) as String {
        var font = Graphics.FONT_XTINY;
        if (dc.getTextWidthInPixels(name, font) <= maxW) {
            return name;
        }
        var dots = "...";
        for (var i = name.length() - 1; i > 0; i--) {
            var cand = name.substring(0, i) + dots;
            if (dc.getTextWidthInPixels(cand, font) <= maxW) {
                return cand;
            }
        }
        return name.substring(0, 1) + dots;
    }

    private function _stateFont(h as Number) as FontType {
        if (h >= 100) {
            return Graphics.FONT_MEDIUM;
        }
        if (h >= 60) {
            return Graphics.FONT_SMALL;
        }
        return Graphics.FONT_XTINY;
    }

    private function _drawMetrics(dc as Dc, model as EbikeData, safe as Dictionary) as Void {
        var showLabels = EbikeConfig.showLabels();
        var metrics = _collectMetrics(model);
        var x = safe[:x] as Number;
        var y = safe[:y] as Number;
        var w = safe[:w] as Number;
        var h = safe[:h] as Number;
        var flags = safe[:flags] as Number;

        var n = metrics.size();
        if (n == 0) {
            dc.drawText(x + w / 2, y + h / 2, _stateFont(h), WatchUi.loadResource(Rez.Strings.NothingSelected), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var minCellH = _minCellHeight(showLabels);
        var circle = _inferCircle(dc, flags);

        // The title is sacrificed before the data: evaluate both the titled and
        // the untitled layout and keep whichever shows the most metrics (ties
        // go to the layout with the roomier cells).
        var best = _bestLayout(dc, metrics, x, y, w, h, showLabels, minCellH, circle);

        var titleH = best[:titleH] as Number;
        var effW = best[:effW] as Number;
        var grid = best[:grid] as Dictionary;
        var k = best[:k] as Number;
        var gridX = x + (w - effW) / 2;
        var cols = grid[:cols] as Number;
        var cellW = grid[:cellW] as Number;
        var cellH = grid[:cellH] as Number;

        if (titleH > 0) {
            var title = WatchUi.loadResource(Rez.Strings.Title);
            if (EbikeConfig.isDemo()) {
                title = WatchUi.loadResource(Rez.Strings.TitleDemo);
            } else {
                var bikeName = model.bikeName;
                if (bikeName != null && bikeName.length() > 0) {
                    title = _fitTitle(dc, bikeName, w - 4);
                }
            }
            dc.drawText(x + w / 2, y + 2, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER);
        }

        for (var i = 0; i < k; i++) {
            var metric = metrics[i] as Dictionary;
            var col = i % cols;
            var row = i / cols;
            _drawCell(dc, gridX + col * cellW, y + titleH + row * cellH, cellW, cellH,
                metric[:label] as String, metric[:value] as String, metric[:unit] as String, showLabels);
        }

        if (EbikeConfig.isDebug()) {
            for (var i = 0; i < k; i++) {
                var col = i % cols;
                var row = i / cols;
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.drawRectangle(gridX + col * cellW, y + titleH + row * cellH, cellW, cellH);
            }
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(x, y, w, h);
            _printDebugInfo(dc.getWidth(), dc.getHeight(), safe, grid, k, n, showLabels, effW, titleH);
        }
    }

    private function _collectMetrics(model as EbikeData) as Array<Dictionary> {
        var metrics = new [0];
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_POWER)) {
            metrics.add({:label => WatchUi.loadResource(Rez.Strings.Power), :value => _fmt0(model.powerW), :unit => "W"});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_MOTOR_POWER)) {
            metrics.add({:label => WatchUi.loadResource(Rez.Strings.Motor), :value => _fmt0(model.motorPowerW), :unit => "W"});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_CADENCE)) {
            metrics.add({:label => WatchUi.loadResource(Rez.Strings.Cadence), :value => _fmt0(model.cadenceRpm), :unit => "rpm"});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_ASSIST)) {
            metrics.add({:label => WatchUi.loadResource(Rez.Strings.Assist), :value => _fmt0(model.assistMode), :unit => ""});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_BATTERY)) {
            metrics.add({:label => WatchUi.loadResource(Rez.Strings.Battery), :value => _fmt0(model.batterySoc), :unit => "%"});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_RANGE)) {
            metrics.add({:label => WatchUi.loadResource(Rez.Strings.Range), :value => _fmt0(model.rangeKm), :unit => "km"});
        }
        return metrics;
    }

    private function _minCellHeight(showLabels as Boolean) as Number {
        var x = Graphics.getFontHeight(Graphics.FONT_XTINY);
        return showLabels ? 2 * x + 2 : x;
    }

    //! True if a grid of k cells (labels + units at minimum size) fits the
    //! given box. w is the effective (circle-limited) grid width.
    private function _gridFits(dc as Dc, metrics as Array<Dictionary>, k as Number, w as Number, h as Number, showLabels as Boolean, titleH as Number, minCellH as Number) as Boolean {
        for (var c = 1; c <= 3; c++) {
            if (c > k) {
                break;
            }
            var r = (k + c - 1) / c;
            var cellW = w / c;
            var cellH = (h - titleH) / r;
            if (_cellsFit(dc, metrics, k, cellW, cellH, minCellH)) {
                return true;
            }
        }
        return false;
    }

    private function _cellsFit(dc as Dc, metrics as Array<Dictionary>, k as Number, cellW as Number, cellH as Number, minCellH as Number) as Boolean {
        if (cellH < minCellH + 6) {
            return false;
        }
        var availW = cellW - 6;
        for (var i = 0; i < k; i++) {
            var metric = metrics[i] as Dictionary;
            var needW = dc.getTextWidthInPixels(metric[:value] as String, Graphics.FONT_XTINY) + 1
                + dc.getTextWidthInPixels(metric[:unit] as String, Graphics.FONT_XTINY);
            if (needW > availW) {
                return false;
            }
        }
        return true;
    }

    //! Pick columns/rows so cells are as square as possible (1..3 columns).
    private function _pickGrid(w as Number, h as Number, titleH as Number, k as Number) as Dictionary {
        var best = null;
        var bestScore = 1000000;
        for (var c = 1; c <= 3; c++) {
            if (c > k) {
                break;
            }
            var r = (k + c - 1) / c;
            var cellW = w / c;
            var cellH = (h - titleH) / r;
            if (cellH < 26) {
                continue;
            }
            var diff = cellW - cellH;
            if (diff < 0) {
                diff = -diff;
            }
            if (diff > bestScore) {
                continue;
            }
            var better = best == null || diff < bestScore;
            if (diff == bestScore && best != null) {
                // Tie-break: more columns when wide, more rows when tall.
                var wide = cellW > cellH;
                var bestCols = (best as Dictionary)[:cols] as Number;
                better = (wide && c > bestCols) || (!wide && c < bestCols);
            }
            if (better) {
                best = {:cols => c, :rows => r, :cellW => cellW, :cellH => cellH};
                bestScore = diff;
            }
        }
        if (best == null) {
            var r = k;
            best = {:cols => 1, :rows => r, :cellW => w, :cellH => (h - titleH) / r};
        }
        return best;
    }

    //! When the field spans the full width of a round screen and touches its
    //! top or bottom edge, infer the screen circle in field coordinates so the
    //! grid can be clipped to the actually visible area. Returns null when the
    //! position cannot be determined (middle bands, side cells, rectangular
    //! screens), in which case the uniform insets are used alone.
    private function _inferCircle(dc as Dc, flags as Number) as Dictionary? {
        if ((flags & (OBSCURE_LEFT | OBSCURE_RIGHT)) != (OBSCURE_LEFT | OBSCURE_RIGHT)) {
            return null;
        }
        var fw = dc.getWidth();
        var fh = dc.getHeight();
        var r = fw / 2;
        var cx = fw / 2;
        var cy = 0;
        if ((flags & OBSCURE_TOP) != 0) {
            cy = r;
        } else if ((flags & OBSCURE_BOTTOM) != 0) {
            cy = fh - r;
        } else {
            return null;
        }
        return {:cx => cx, :cy => cy, :r => r};
    }

    //! Largest width the grid may use so that its corners stay inside the round
    //! screen: limited by the narrowest horizontal chord across the rows and by
    //! the vertical chord available at the outer columns.
    private function _effectiveWidth(w as Number, h as Number, titleH as Number, y as Number, circle as Dictionary?) as Number {
        if (circle == null) {
            return w;
        }
        var cy = circle[:cy] as Number;
        var r = circle[:r] as Number;
        var gTop = y + titleH;
        var gBottom = y + h;
        var hw = _halfChord(r, gTop, cy);
        var hc = _halfChord(r, gBottom, cy);
        if (hc < hw) {
            hw = hc;
        }
        var m = cy - gTop;
        var m2 = gBottom - cy;
        if (m2 > m) {
            m = m2;
        }
        if (m < 0) {
            m = 0;
        }
        if (m < r) {
            hc = _halfChord(r, cy + m, cy);
            if (hc < hw) {
                hw = hc;
            }
        }
        var maxHalf = w / 2;
        if (hw > maxHalf) {
            hw = maxHalf;
        }
        return (hw * 2).toNumber();
    }

    private function _halfChord(r as Number, yLine as Number, cy as Number) as Float {
        var d = yLine - cy;
        var r2 = r * r;
        var d2 = d * d;
        if (d2 >= r2) {
            return 0.0;
        }
        return Math.sqrt(r2 - d2);
    }

    //! Pick the title option (keep or drop) that shows the most metrics, and
    //! return the chosen title height, grid and effective width. The title is
    //! sacrificed before the number of metrics; on equal counts the roomier
    //! cells (bigger minimum dimension) win.
    private function _bestLayout(dc as Dc, metrics as Array<Dictionary>, x as Number, y as Number, w as Number, h as Number, showLabels as Boolean, minCellH as Number, circle as Dictionary?) as Dictionary {
        var n = metrics.size();
        var bestK = 0;
        var bestTitleH = 0;
        var bestEffW = w;
        var bestGrid = null;
        var bestMinDim = -1;
        var titleOpts = [_titleHeight(w, h), 0];
        for (var i = 0; i < titleOpts.size(); i++) {
            var titleH = titleOpts[i] as Number;
            var effW = _effectiveWidth(w, h, titleH, y, circle);
            var k = n;
            while (k > 1 && !_gridFits(dc, metrics, k, effW, h, showLabels, titleH, minCellH)) {
                k--;
            }
            var grid = _pickGrid(effW, h, titleH, k);
            var cellW = grid[:cellW] as Number;
            var cellH = grid[:cellH] as Number;
            var minDim = cellW < cellH ? cellW : cellH;
            if (k > bestK || (k == bestK && minDim > bestMinDim)) {
                bestK = k;
                bestTitleH = titleH;
                bestEffW = effW;
                bestGrid = grid;
                bestMinDim = minDim;
            }
            if (k >= n) {
                break;
            }
        }
        return {:titleH => bestTitleH, :effW => bestEffW, :grid => bestGrid, :k => bestK};
    }

    //! Largest value font whose value+unit fit horizontally and vertically.
    //! Candidates lead with the big digit-only number fonts (FONT_NUMBER_*)
    //! so values render as large as the cell allows; FONT_XTINY is the floor.
    //! The tallest font that fits wins, so the list order does not matter.
    private function _fitValueFont(dc as Dc, value as String, unit as String, w as Number, h as Number, showLabels as Boolean) as Dictionary {
        var ladder = [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MILD, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_XTINY];
        var unitFont = Graphics.FONT_XTINY;
        var uw = dc.getTextWidthInPixels(unit, unitFont);
        var availW = w - 6;
        var availH = h - 6;
        var labelH = showLabels ? Graphics.getFontHeight(Graphics.FONT_XTINY) + 2 : 0;
        var chosen = Graphics.FONT_XTINY;
        var bestH = 0;
        for (var i = 0; i < ladder.size(); i++) {
            var f = ladder[i];
            var fh = Graphics.getFontHeight(f);
            if (fh <= bestH || fh + labelH > availH) {
                continue;
            }
            var vw = dc.getTextWidthInPixels(value, f);
            if (vw + 1 + uw <= availW) {
                chosen = f;
                bestH = fh;
            }
        }
        var showUnit = unit.length() > 0 && dc.getTextWidthInPixels(value, chosen) + 1 + uw <= availW;
        return {:valueFont => chosen, :showUnit => showUnit};
    }

    private function _drawCell(dc as Dc, x as Number, y as Number, w as Number, h as Number, label as String, value as String, unit as String, showLabels as Boolean) as Void {
        var withLabel = showLabels;
        var fit = _fitValueFont(dc, value, unit, w, h, withLabel);
        var vf = fit[:valueFont] as FontType;
        var lf = Graphics.FONT_XTINY;
        var labelH = withLabel ? Graphics.getFontHeight(lf) : 0;
        if (withLabel && Graphics.getFontHeight(vf) + labelH + 2 > h - 6) {
            withLabel = false;
            fit = _fitValueFont(dc, value, unit, w, h, false);
            vf = fit[:valueFont] as FontType;
            labelH = 0;
        }
        _lastValueFont = vf;
        var showUnit = fit[:showUnit] as Boolean;

        var vh = Graphics.getFontHeight(vf);
        var gap = withLabel ? 2 : 0;
        var blockH = vh + labelH + gap;
        var top = y + (h - blockH) / 2;
        var valueY = top + labelH + gap;
        var cx = x + w / 2;
        var vw = dc.getTextWidthInPixels(value, vf);

        if (showUnit) {
            var uf = Graphics.FONT_XTINY;
            var uw = dc.getTextWidthInPixels(unit, uf);
            var total = vw + 1 + uw;
            var vx = cx - total / 2;
            var ux = vx + vw + 1;
            var uy = valueY + vh - Graphics.getFontHeight(uf);
            dc.drawText(vx + vw / 2, valueY, vf, value, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(ux, uy, uf, unit, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(cx, valueY, vf, value, Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (withLabel) {
            dc.drawText(cx, top, lf, label, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function _fontLetter(f as FontType) as String {
        if (f == Graphics.FONT_NUMBER_HOT) {
            return "O";
        }
        if (f == Graphics.FONT_NUMBER_MILD) {
            return "D";
        }
        if (f == Graphics.FONT_NUMBER_MEDIUM) {
            return "nM";
        }
        if (f == Graphics.FONT_LARGE) {
            return "L";
        }
        if (f == Graphics.FONT_MEDIUM) {
            return "M";
        }
        if (f == Graphics.FONT_SMALL) {
            return "S";
        }
        return "X";
    }

    private function _obscureString(flags as Number) as String {
        var parts = "";
        if ((flags & OBSCURE_TOP) != 0) {
            parts += "T";
        }
        if ((flags & OBSCURE_BOTTOM) != 0) {
            parts += "B";
        }
        if ((flags & OBSCURE_LEFT) != 0) {
            parts += "L";
        }
        if ((flags & OBSCURE_RIGHT) != 0) {
            parts += "R";
        }
        if (parts.length() == 0) {
            parts = "-";
        }
        return parts;
    }

    private var _lastDebugLine as String = "";

    //! Prints the one-line layout/debug summary to the console instead of
    //! drawing it on screen, so the watch face stays clean. Only prints when
    //! the line changed, to avoid spamming the console every second.
    private function _printDebugInfo(fw as Number, fh as Number, safe as Dictionary, grid as Dictionary, shown as Number, selected as Number, showLabels as Boolean, effW as Number, titleH as Number) as Void {
        var w = safe[:w] as Number;
        var h = safe[:h] as Number;
        var flags = safe[:flags] as Number;
        var top = safe[:top] as Number;
        var bottom = safe[:bottom] as Number;
        var left = safe[:left] as Number;
        var right = safe[:right] as Number;
        var cols = grid[:cols] as Number;
        var rows = grid[:rows] as Number;
        var line = "F" + fw.toString() + "x" + fh.toString()
            + " S" + w.toString() + "x" + h.toString()
            + " gw" + effW.toString() + " t" + titleH.toString()
            + " n=" + shown.toString() + "/" + selected.toString()
            + " " + cols.toString() + "x" + rows.toString()
            + " f" + _fontLetter(_lastValueFont)
            + " lbl" + (showLabels ? "1" : "0")
            + " O:" + _obscureString(flags)
            + " i" + top.toString() + "/" + bottom.toString() + "/" + left.toString() + "/" + right.toString();
        if (!line.equals(_lastDebugLine)) {
            _lastDebugLine = line;
            System.println(line);
        }
    }

    private function _fmt0(v as Number?) as String {
        if (v == null) {
            return "--";
        }
        return v.toString();
    }
}

class EbikeField extends Application.AppBase {
    private var _ble as BleManager? = null;
    private var _demo as DemoManager? = null;
    private var _model as EbikeData? = null;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        var model = new EbikeData();
        _model = model;
        if (EbikeConfig.isDemo()) {
            _demo = new DemoManager(model);
            _ble = null;
        } else {
            var ble = new BleManager(model);
            _ble = ble;
            _demo = null;
            ble.startScan();
        }
    }

    public function onStop(state as Dictionary?) as Void {
        var ble = _ble;
        if (ble != null) {
            ble.stop();
        }
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var model = _model;
        if (model == null) {
            model = new EbikeData();
            _model = model;
        }
        if (EbikeConfig.isDemo()) {
            var demo = _demo;
            if (demo == null) {
                demo = new DemoManager(model);
                _demo = demo;
            }
            var ble = _ble;
            if (ble != null) {
                ble.stop();
                _ble = null;
            }
        } else {
            var ble = _ble;
            if (ble == null) {
                ble = new BleManager(model);
                _ble = ble;
                ble.startScan();
            }
            _demo = null;
        }
        return [new $.EbikeDataField(model, _ble, _demo)];
    }

    public function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        var menu = new $.EbikeSettingsMenu(_ble);
        return [menu, new $.EbikeSettingsMenuDelegate(menu)];
    }
}
