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
    }

    //! Best available rider FTP in watts for the gauge scale: the explicit
    //! on-device setting if set (> 0), otherwise the "auto" resolution shared
    //! with the settings menu (profile FTP, else 200 W). The setting is
    //! re-read every draw (it changes only through the settings menu, but the
    //! field may stay alive across pages).
    private function _resolveFtp() as Number {
        var override = EbikeConfig.ftpOverride();
        if (override > 0) {
            return override;
        }
        return EbikeConfig.autoFtp();
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

    //! Make sure the correct data source (demo vs BLE) matches the current
    //! settings, switching if the user changed the mode while this field
    //! instance was kept alive. Returns the current demo mode.
    //!
    //! The BLE manager is NOT created here, it is only borrowed from
    //! BleManager.getShared(): this runs once per second from the draw path,
    //! and building a manager there re-registered the GATT profiles. The
    //! uncaught registerProfile() in its constructor is what killed this field
    //! on an Edge 1030 — see docs/HANDOFF-NOUVELLE-SESSION.md.
    private function _ensureMode() as Boolean {
        var demoMode = EbikeConfig.isDemo();
        var ble = _ble;
        if (demoMode) {
            if (_demo == null) {
                _demo = new DemoManager(_model);
            }
            if (ble != null && ble.isActive()) {
                ble.stop();
            }
        } else {
            _demo = null;
            if (ble == null) {
                ble = BleManager.getShared(_model);
                _ble = ble;
            }
            if (ble != null && !ble.isActive()) {
                ble.startScan();
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
        if (!demoMode && ble == null) {
            //! The GATT profiles could not be registered and every retry is
            //! spent (see BleManager.getShared). Say so instead of claiming
            //! the app is still scanning.
            dc.drawText(x + w / 2, y + h / 2, _stateFont(h), WatchUi.loadResource(Rez.Strings.BleError), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (!demoMode && !model.connected) {
            dc.drawText(x + w / 2, y + h / 2, _stateFont(h), WatchUi.loadResource(Rez.Strings.Scanning), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (!demoMode && model.batterySoc == null && System.getTimer() - model.lastUpdate > 10000) {
            dc.drawText(x + w / 2, y + h / 2, _stateFont(h), WatchUi.loadResource(Rez.Strings.Waiting), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        _drawMetrics(dc, model, safe, fg);
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

    private function _drawMetrics(dc as Dc, model as EbikeData, safe as Dictionary, fg as ColorType) as Void {
        var x = safe[:x] as Number;
        var y = safe[:y] as Number;
        var w = safe[:w] as Number;
        var h = safe[:h] as Number;
        var showLabels = EbikeConfig.showLabels();
        var ftp = _resolveFtp();

        var row2 = _collectRow2(model);
        var row3 = _collectRow3(model);

        var titleH = _titleHeight(w, h);
        var minG = _minGaugeH(w, h, showLabels);
        // The rows claim their natural height first: each cell fits the
        // tallest font that fits ITS OWN width (w / n), so the size already
        // adapts to how many metrics are enabled, and the fit is no longer
        // capped by a fixed band budget. Only a gauge squeezed under minG
        // pushes the rows down, and then each one is re-fitted at the height
        // it actually gets so the drawn font is always the one reserved.
        var row2H = _rowBandH(dc, row2, w, showLabels, h);
        var row3H = _rowBandH(dc, row3, w, showLabels, h);
        var avail = h - titleH - minG;
        if (avail < 0) {
            avail = 0;
        }
        if (row2H + row3H > avail) {
            var share2 = (avail * row2H) / (row2H + row3H);
            row2H = _rowBandH(dc, row2, w, showLabels, share2);
            row3H = _rowBandH(dc, row3, w, showLabels, avail - share2);
        }

        // The gauge always keeps its spot; sacrifice the title first, then the
        // last row, so the power arc never has to shrink below legibility.
        var gaugeH = h - titleH - row2H - row3H;
        if (gaugeH < minG) {
            titleH = 0;
            gaugeH = h - row2H - row3H;
        }
        if (gaugeH < minG) {
            row3H = 0;
            gaugeH = h - row2H;
        }

        var yTitle = y + h - titleH;
        var yRow3 = yTitle - row3H;
        var yRow2 = yRow3 - row2H;

        // The gauge is anchored to the whole screen (it rides the upper
        // contour), so it gets the absolute band from the field top to row 2.
        // NB: the value fit is computed here, not inside the gauge: invoking a
        // class method from that 8-arg drawing frame crashes the simulator VM.
        var gfit = _fitValueFont(dc, _fmt0(model.powerW3s), WatchUi.loadResource(Rez.Strings.W) + " 3s", w, yRow2 - y, showLabels);
        gfit[:value] = _fmt0(model.powerW3s);
        _drawPowerGauge(dc, model, safe, y, yRow2 - y, ftp, fg, showLabels, gfit);
        _drawValueRow(dc, row2, x, yRow2, w, row2H, showLabels);
        _drawValueRow(dc, row3, x, yRow3, w, row3H, showLabels);

        if (titleH > 0) {
            // The title is a narrow, centered strip, so it can sit lower than
            // the rows: push it down into the round bottom arc (the wide rows
            // must stay in the safe rect because they would clip there).
            var fh = dc.getHeight();
            var titleY = yTitle;
            var lowY = fh - titleH - 2;
            if (lowY > titleY) {
                titleY = lowY;
            }
            // Width available at that height is the circle's chord, so a long
            // bike name truncates instead of running off the glass.
            var titleMaxW = w - 4;
            if ((safe[:flags] as Number) != 0) {
                var sr = (dc.getWidth() < fh ? dc.getWidth() : fh) / 2;
                var dy = (titleY + titleH / 2) - fh / 2;
                if (sr * sr > dy * dy) {
                    var half = Math.sqrt((sr * sr - dy * dy).toFloat()).toNumber();
                    if (half * 2 - 8 < titleMaxW) {
                        titleMaxW = half * 2 - 8;
                    }
                }
            }

            var title = WatchUi.loadResource(Rez.Strings.Title);
            if (EbikeConfig.isDemo()) {
                title = WatchUi.loadResource(Rez.Strings.TitleDemo);
            } else {
                var bikeName = model.bikeName;
                if (bikeName != null && bikeName.length() > 0) {
                    title = _fitTitle(dc, bikeName, titleMaxW);
                }
            }
            dc.drawText(x + w / 2, titleY + 1, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! Fixed companion band under the gauge: motor power / cadence / assist.
    private function _collectRow2(model as EbikeData) as Array<Dictionary> {
        var cells = new [0];
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_MOTOR_POWER)) {
            cells.add({:label => WatchUi.loadResource(Rez.Strings.Motor), :value => _fmt0(model.motorPowerW), :unit => WatchUi.loadResource(Rez.Strings.W)});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_CADENCE)) {
            cells.add({:label => WatchUi.loadResource(Rez.Strings.Cadence), :value => _fmt0(model.cadenceRpm), :unit => "rpm"});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_ASSIST)) {
            cells.add({:label => WatchUi.loadResource(Rez.Strings.Assist), :value => _fmt0(model.assistMode), :unit => ""});
        }
        return cells;
    }

    //! Fixed bottom band: battery / range.
    private function _collectRow3(model as EbikeData) as Array<Dictionary> {
        var cells = new [0];
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_BATTERY)) {
            cells.add({:label => WatchUi.loadResource(Rez.Strings.Battery), :value => _fmt0(model.batterySoc), :unit => "%"});
        }
        if (EbikeConfig.isMetricEnabled($.CFG_KEY_METRIC_RANGE)) {
            cells.add({:label => WatchUi.loadResource(Rez.Strings.Range), :value => _fmt0(model.rangeKm), :unit => "km"});
        }
        return cells;
    }

    //! Height one companion row needs, driven by the largest fitted value font
    //! across its cells at their final cell width. `budget` is the height the
    //! row may claim: the fit is capped by it, and the returned band never
    //! exceeds it, so what the layout reserves and what the draw re-fits can
    //! never disagree.
    private function _rowBandH(dc as Dc, cells as Array<Dictionary>, w as Number, showLabels as Boolean, budget as Number) as Number {
        var n = cells.size();
        if (n == 0 || budget <= 0) {
            return 0;
        }
        var cellW = w / n;
        var maxH = 0;
        for (var i = 0; i < n; i++) {
            var c = cells[i] as Dictionary;
            var fit = _fitValueFont(dc, c[:value] as String, c[:unit] as String, cellW, budget, showLabels);
            var fh = Graphics.getFontHeight(fit[:valueFont] as FontType);
            if (fh > maxH) {
                maxH = fh;
            }
        }
        var labelH = showLabels ? Graphics.getFontHeight(Graphics.FONT_XTINY) + 2 : 0;
        // +8, not +2: _drawCell re-fits with availH = h - 6, so the band must
        // carry maxH + labelH + 6 or the tallest fitted font is rejected at
        // draw time and every companion cell drops one size.
        var band = maxH + labelH + 8;
        if (band > budget) {
            band = budget;
        }
        return band;
    }

    //! Height the gauge band must keep: the cap arc's own depth at the lowest
    //! theta it will ever use (55 deg) plus half the pen width and a margin.
    //! Replaces a hard-coded minimum that ignored the screen size, so rows can
    //! never grow into the space the arc needs to render whole.
    //! It ALSO reserves the height the power number needs to render one size
    //! above the plain-text fonts: the number is the point of the gauge, so it
    //! must not be squeezed into FONT_LARGE just because the companion rows
    //! claimed the screen first. The rows are fitted to what is left (their
    //! budget `avail` already follows this floor), and the value fit still
    //! degrades on its own if even this floor is not enough.
    private function _minGaugeH(w as Number, h as Number, showLabels as Boolean) as Number {
        var screenR = (w < h ? w : h) / 2;
        var r = screenR - 10;
        if (r < 30) {
            r = 30;
        }
        var depth = (r * (1.0 - Math.cos(55.0 * Math.PI / 180.0))).toNumber();
        var geom = depth + 16;
        var labelH = showLabels ? Graphics.getFontHeight(Graphics.FONT_XTINY) + 2 : 0;
        var need = Graphics.getFontHeight(Graphics.FONT_NUMBER_MEDIUM) + labelH + 6;
        var cap = (h * 6) / 10;
        if (need > cap) {
            need = cap;
        }
        return geom > need ? geom : need;
    }

    //! Draws a companion row as n equal cells centered in [x, x+w].
    private function _drawValueRow(dc as Dc, cells as Array<Dictionary>, x as Number, y as Number, w as Number, h as Number, showLabels as Boolean) as Void {
        var n = cells.size();
        if (n == 0 || h <= 0) {
            return;
        }
        var cellW = w / n;
        for (var i = 0; i < n; i++) {
            var c = cells[i] as Dictionary;
            _drawCell(dc, x + i * cellW, y, cellW, h, c[:label] as String, c[:value] as String, c[:unit] as String, showLabels);
        }
    }

    //! Radial power gauge riding the very top of the screen: a partial cap arc
    //! concentric with the display circle whose outer stroke edge is flush with
    //! the top of the screen (the crown IS the top of the visible circle, so
    //! there is no safe.top clamp). The cap spans 10h..14h (theta 60): f = 0
    //! (0 W) at a1 = 150 deg on the LEFT, f = 1 (2*FTP) at a0 = 30 deg on the
    //! RIGHT, FTP at the zenith (SDK convention: 0 deg = east, 90 = top).
    //! Seven EQUAL segments (each 2/7 FTP) read grey, light blue, light green,
    //! yellow (FTP centered), orange, red, purple; the needle is a short radial
    //! stub just inside the arc; the value (3 s average of the rider power, plus
    //! an optional label and a small "3s" after the W) is tucked as high as it
    //! can go inside the cap while still clearing the needle's sweep.
    //! NB: this frame is big and the simulator VM stack is shallow, so NO user
    //! class method may be invoked from here (not even _fmt0): the formatted
    //! value and the font fit are both handed in through `fit`.
    private function _drawPowerGauge(dc as Dc, model as EbikeData, safe as Dictionary, gaugeY as Number, gaugeH as Number, ftp as Number, fg as ColorType, showLabels as Boolean, fit as Dictionary) as Void {
        var value = fit[:value] as String;
        var wid = WatchUi.loadResource(Rez.Strings.W);
        var vf = fit[:valueFont] as FontType;
        var showUnit = fit[:showUnit] as Boolean;
        var vh = Graphics.getFontHeight(vf);
        var labelH = showLabels ? Graphics.getFontHeight(Graphics.FONT_XTINY) + 2 : 0;
        var uf = Graphics.FONT_XTINY;
        var uw = dc.getTextWidthInPixels(wid, uf);
        var sw = dc.getTextWidthInPixels("3s", uf);
        var vw = dc.getTextWidthInPixels(value, vf);

        // Arc circle = display circle. The arc is concentric with the screen,
        // so its zenith IS the top of the visible circle: ride the very top
        // edge, no inset. (Clamping the crown under safe.top pulled it down by
        // the whole top inset and left exactly the dead space above the arc
        // that was reported.)
        var cx = (dc.getWidth() / 2).toNumber();
        var scy = (dc.getHeight() / 2).toNumber();
        var bw = 21;
        var r = ((dc.getWidth() < dc.getHeight() ? dc.getWidth() : dc.getHeight()) / 2 - bw / 2).toNumber();
        if (r < 30) {
            r = 30;
        }

        // Cap half-angle: 60 deg, i.e. the arc spans 10h..14h (a1 = 150 deg on
        // the left down to a0 = 30 deg on the right). 60 is the default and the
        // floor is 55, so a full 10h-14h cap is what actually renders; the
        // shrink above is only a last-resort guard for a very short field.
        var theta = 60.0;
        var maxCos = 1.0 - (gaugeH - vh - labelH - 2).toFloat() / r.toFloat();
        if (maxCos > -1.0 && maxCos < 1.0) {
            var thetaLim = Math.acos(maxCos) * 180.0 / Math.PI;
            if (theta > thetaLim) {
                theta = thetaLim;
            }
        }
        if (theta > 64.0) {
            theta = 64.0;
        }
        if (theta < 55.0) {
            theta = 55.0;
        }

        // a1 = 90+theta (10h, low power, LEFT); the arc is drawn from a1 down
        // to a0 = 90-theta (14h, high power, RIGHT) as f goes 0..1.
        var a1 = 90.0 + theta;
        var tRad = theta * Math.PI / 180.0;

        // Equal-width ramp (each 2/7 FTP) so every segment is the same size:
        // grey, light blue, light green, yellow (FTP centered), orange, red,
        // purple. f runs 0..1 left->right, so LOW power is on the LEFT.
        var zoneColors = [
            Graphics.COLOR_LT_GRAY,  // 0.00 .. 0.29
            Graphics.COLOR_BLUE,     // 0.29 .. 0.57
            Graphics.COLOR_GREEN,    // 0.57 .. 0.86
            Graphics.COLOR_YELLOW,   // 0.86 .. 1.14  (FTP centered)
            Graphics.COLOR_ORANGE,   // 1.14 .. 1.43
            Graphics.COLOR_RED,      // 1.43 .. 1.71
            Graphics.COLOR_PURPLE    // 1.71 .. 2.00
        ];
        for (var i = 0; i < zoneColors.size(); i++) {
            var fLo = i / 7.0;
            var fHi = (i + 1) / 7.0;
            dc.setColor(zoneColors[i] as ColorType, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(bw);
            dc.drawArc(cx, scy, r, Graphics.ARC_CLOCKWISE, (a1 - 2.0 * theta * fLo).toNumber(), (a1 - 2.0 * theta * fHi).toNumber());
        }

        // FTP tick removed on purpose: the green apex marks FTP±15 % and its
        // center line is exactly FTP, so an extra tick just looks like a glitch.

        // Partial needle: a short radial stub just inside the arc, at the
        // current power, clamped at the gauge ends (0 and 2*FTP).
        var power = model.powerW3s;
        if (power != null) {
            var f = power.toFloat() / (2.0 * ftp);
            if (f < 0.0) {
                f = 0.0;
            }
            if (f > 1.0) {
                f = 1.0;
            }
            var alpha = (a1 - 2.0 * theta * f) * Math.PI / 180.0;
            var ri = (r - 29).toNumber();
            var xi = (cx + (ri * Math.cos(alpha)).toNumber()).toNumber();
            var yi = (scy - (ri * Math.sin(alpha)).toNumber()).toNumber();
            ri = (r - 8).toNumber();
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(6);
            dc.drawLine(xi, yi, (cx + (ri * Math.cos(alpha)).toNumber()).toNumber(), (scy - (ri * Math.sin(alpha)).toNumber()).toNumber());
        }
        dc.setPenWidth(1);

        // Value (+ optional label) tucked HIGH inside the cap: as close to the arc
        // as the needle's sweep allows. The needle lives at radius r-29..r-8, so
        // the block's top corners have to stay inside r-29-8 or the needle
        // would cut through the digits around the FTP zone.
        var valCx = ((safe[:x] as Number) + (safe[:w] as Number) / 2).toNumber();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var topY = (scy - (r * Math.cos(tRad)).toNumber()).toNumber() + 1;
        var halfW = (vw + (showUnit ? uw + 1 + sw : 0)) / 2 + 2;
        var riseSq = (r - 37) * (r - 37) - halfW * halfW;
        if (riseSq > 0 && scy - Math.sqrt(riseSq.toFloat()).toNumber() < topY) {
            topY = scy - Math.sqrt(riseSq.toFloat()).toNumber();
        }
        if (topY < scy - r + bw / 2 + 4) {
            topY = scy - r + bw / 2 + 4;
        }
        if (showLabels) {
            dc.drawText(valCx, topY, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Power), Graphics.TEXT_JUSTIFY_CENTER);
            topY += labelH;
        }
        if (topY + vh > gaugeY + gaugeH) {
            topY = gaugeY + gaugeH - vh;
        }
        if (showUnit) {
            var vx = valCx - (vw + uw + sw + 2) / 2;
            var uy = topY + vh - Graphics.getFontHeight(uf);
            dc.drawText(vx + vw / 2, topY, vf, value, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(vx + vw + 1, uy, uf, wid, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(vx + vw + 1 + uw + 1, uy, uf, "3s", Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(valCx, topY, vf, value, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! Largest value font whose value+unit fit horizontally and vertically.
    //! Candidates lead with the big digit-only number fonts (FONT_NUMBER_*)
    //! so values render as large as the cell allows; FONT_XTINY is the floor.
    //! The tallest font that fits wins, so the list order does not matter.
    private function _fitValueFont(dc as Dc, value as String, unit as String, w as Number, h as Number, showLabels as Boolean) as Dictionary {
        var ladder = [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MILD, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_XTINY];
        var uw = dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY);
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
        var labelH = withLabel ? Graphics.getFontHeight(Graphics.FONT_XTINY) : 0;
        if (withLabel && Graphics.getFontHeight(vf) + labelH + 2 > h - 6) {
            withLabel = false;
            fit = _fitValueFont(dc, value, unit, w, h, false);
            vf = fit[:valueFont] as FontType;
            labelH = 0;
        }
        var showUnit = fit[:showUnit] as Boolean;

        // NB: kept deliberately lean - this frame sits under onUpdate +
        // _drawMetrics + _drawValueRow, and the VM stack is shallow.
        var gap = withLabel ? 2 : 0;
        var top = y + (h - Graphics.getFontHeight(vf) - labelH - gap) / 2;
        var valueY = top + labelH + gap;
        var cx = x + w / 2;
        var vw = dc.getTextWidthInPixels(value, vf);

        if (showUnit) {
            var vx = cx - (vw + 1 + dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY)) / 2;
            dc.drawText(vx + vw / 2, valueY, vf, value, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(vx + vw + 1, valueY + Graphics.getFontHeight(vf) - Graphics.getFontHeight(Graphics.FONT_XTINY), Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(cx, valueY, vf, value, Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (withLabel) {
            dc.drawText(cx, top, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
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
            //! getShared(), never new BleManager(): the GATT profiles are
            //! registered once per run of the app and the failure is contained.
            var ble = BleManager.getShared(model);
            _ble = ble;
            _demo = null;
            if (ble != null) {
                ble.startScan();
            }
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
            //! Only stopped, never discarded: the shared manager keeps its
            //! registered profiles, so leaving demo mode does not register
            //! them a second time.
            var ble = _ble;
            if (ble != null && ble.isActive()) {
                ble.stop();
            }
        } else {
            var ble = _ble;
            if (ble == null) {
                ble = BleManager.getShared(model);
                _ble = ble;
            }
            if (ble != null && !ble.isActive()) {
                ble.startScan();
            }
            _demo = null;
        }
        return [new $.EbikeDataField(model, _ble, _demo)];
    }

    public function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        var menu = new $.EbikeSettingsMenu();
        return [menu, new $.EbikeSettingsMenuDelegate(menu)];
    }
}
