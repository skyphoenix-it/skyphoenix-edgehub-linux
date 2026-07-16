import QtQuick
import QtTest
import "../../ui/qml" as App

// ─────────────────────────────────────────────────────────────────────────
// tst_gen_media — COMPREHENSIVE coverage for area "widget:media"
// (ui/qml/widgets/MediaWidget.qml, driven by the MPRIS `media` bridge —
// mocked here by MockMedia).
//
// Covers: the effAccent binding-loop bug (MediaWidget is the only widget that
// sets accentColor: w.effAccent, creating a 2-node cycle so the DEFAULT card
// renders a black accent), per-widget accent recolouring, real mouse clicks on
// the compact + expanded transport, the leading " · " subtitle bug, progress
// clamping/reactivity, the honest "nothing playing" placeholder, album-art
// fallback, header status, touch-target sizing, the reduce-motion progress
// animation bug, and the shared config-schema area.
//
// Some assertions intentionally encode the CORRECT behaviour and therefore
// FAIL against real bugs (effAccent loop → black accent; leading " · " when
// artist is empty; progress animation ignoring reduceMotion). Those failures
// are the point and are reported as likelyRealBug.
//
// NOT covered here (C++-only, needs the real MprisBridge — MockMedia cannot
// model them): GetAll-timeout debounce, Identity→friendly-name mapping, the
// Seeked-while-paused signal, and tile-level tap-to-expand propagation.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 460; height: 900

    // Main expanded harness — accent, subtitle, progress, transport, placeholder.
    WidgetHarness {
        id: h; x: 0; y: 0; width: 420; height: 760
        widgetFile: "MediaWidget.qml"; expanded: true
    }
    // Compact tile harness — compact play/pause click + compact touch target.
    WidgetHarness {
        id: hC; x: 0; y: 760; width: 360; height: 120
        widgetFile: "MediaWidget.qml"; expanded: false
    }

    // Shared config-schema area, instantiated directly.
    App.WidgetConfigSchema { id: sc }

    // ── tree helpers ─────────────────────────────────────────────────────────
    function colEq(a, b) { return Qt.colorEqual(a, b) }
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function isRect(n) { return n && n.hasOwnProperty("radius") && n.hasOwnProperty("gradient") && n.hasOwnProperty("color") }
    function isText(n) { return n && typeof n.paintedWidth === "number" && typeof n.text === "string" }
    function isMouseArea(n) { return n && n.hasOwnProperty("pressed") && n.hasOwnProperty("containsMouse") }
    function isImage(n) { return n && n.hasOwnProperty("fillMode") && n.hasOwnProperty("sourceSize") && n.hasOwnProperty("status") }

    function effVisible(n) {
        while (n) { if (n.visible === false) return false; n = n.parent }
        return true
    }
    function findAll(node, pred, acc) {
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }
    function findByProp(node, prop, val) {
        if (!node) return null
        if (node[prop] !== undefined && node[prop] === val) return node
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) {
            var r = findByProp(kids[i], prop, val); if (r) return r
        }
        return null
    }
    function texts(harness) { return findAll(harness.item, isText, []) }
    function textContaining(harness, sub) {
        var t = texts(harness)
        for (var i = 0; i < t.length; i++) if (t[i].text.indexOf(sub) >= 0) return t[i]
        return null
    }
    // The AppIcon component exposes `name`/`color`/`size`.
    function appIcon(harness, nm) { return findByProp(harness.item, "name", nm) }
    // Rectangle with a laid-out width (transport buttons are sized by width===target).
    function rectByWidth(harness, wpx) {
        var rs = findAll(harness.item, isRect, [])
        for (var i = 0; i < rs.length; i++) if (Math.round(rs[i].width) === wpx) return rs[i]
        return null
    }
    // The progress track is the ONLY Rectangle whose FILL colour is cardBorder.
    function progressTrack(harness) {
        var rs = findAll(harness.item, isRect, [])
        for (var i = 0; i < rs.length; i++)
            if (colEq(rs[i].color, harness.theme.cardBorder)) return rs[i]
        return null
    }
    function progressFill(harness) {
        var tr = progressTrack(harness); if (!tr) return null
        var kids = tr.children
        for (var i = 0; kids && i < kids.length; i++) if (isRect(kids[i])) return kids[i]
        return null
    }
    // Effectively-visible circular transport MouseAreas (excludes the invisible
    // compact play when expanded and the NoButton hover ring).
    function transport(harness) {
        var all = findAll(harness.item, isMouseArea, [])
        var out = []
        for (var i = 0; i < all.length; i++) {
            var ma = all[i]
            if (ma.acceptedButtons === Qt.NoButton) continue
            if (!effVisible(ma)) continue
            out.push(ma)
        }
        return out
    }
    function globalX(item) { var p = item.mapToItem(root, 0, 0); return p.x }

    function seed(harness, title, artist, album) {
        var m = harness.mediaCtl
        m.available = true; m.title = title; m.artist = artist
        m.album = (album === undefined ? "" : album)
        m.artUrl = ""; m.playerName = "MockPlayer"; m.status = "Playing"; m.position = 0.3
    }

    // ── effAccent binding-loop (HIGH-severity bug) ───────────────────────────
    TestCase {
        name: "MediaAccent"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.item.accentName = ""            // default: no per-widget accent
            h.mediaCtl.clearTrack()
        }

        // MediaWidget sets `accentColor: w.effAccent`, and WidgetChrome's
        // effAccent falls back to accentColor when accentName=="" → a direct
        // binding cycle. The correct behaviour is a visible accent colour; the
        // loop resolves it to black/transparent.
        function test_default_accent_is_visible_not_black() {
            var w = h.item
            verify(!colEq(w.effAccent, "#000000"),
                   "default effAccent must not resolve to black (binding loop): got " + w.effAccent)
            verify(w.effAccent.a > 0.5,
                   "default effAccent must be opaque/visible, got alpha " + w.effAccent.a)
        }

        // The expanded play button fills with effAccent and paints a near-black
        // (#0D1117) glyph on top — under the loop both are ~black, so the glyph
        // is invisible. Assert real contrast between button fill and glyph.
        function test_play_button_glyph_has_contrast() {
            seed(h, "Song", "Artist", "Album")
            var play = rectByWidth(h, h.theme.touchPrimary)   // 76px primary button
            verify(play !== null, "found the expanded play button")
            verify(colEq(play.color, h.item.effAccent), "play button fill == effAccent")
            var glyph = Qt.color("#0D1117")
            verify(lum(play.color) - lum(glyph) > 0.15,
                   "play glyph (#0D1117) must contrast against the button fill; "
                   + "fill lum=" + lum(play.color).toFixed(3))
        }

        // Choosing a per-widget accent breaks the loop and recolours everything.
        function test_per_widget_accent_recolours_live() {
            seed(h, "Song", "Artist", "Album")
            h.item.accentName = "green"
            var green = Qt.color(h.theme.accentPresets["green"].a)
            compare(String(h.item.effAccent), String(green), "effAccent = green preset")

            var icon = appIcon(h, "media")
            verify(icon !== null, "found the header 'media' icon")
            verify(colEq(icon.color, green), "header icon recoloured to accent")

            var play = rectByWidth(h, h.theme.touchPrimary)
            verify(colEq(play.color, green), "play button recoloured to accent")

            var fill = progressFill(h)
            verify(fill !== null, "found the progress fill")
            verify(colEq(fill.color, green), "progress fill recoloured to accent")
        }
    }

    // ── expanded subtitle: leading " · " bug ─────────────────────────────────
    TestCase {
        name: "MediaSubtitle"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.item.accentName = "green"       // avoid black-render noise
            h.mediaCtl.clearTrack()
        }

        // Artist empty, album set (podcasts / some streams) → subtitle should be
        // just the album, NOT "  ·  Album" with a stray leading separator.
        function test_empty_artist_omits_leading_separator() {
            seed(h, "Podcast Ep 12", "", "Abbey Road")
            var node = textContaining(h, "Abbey Road")
            verify(node !== null, "found the subtitle showing the album")
            compare(node.text, "Abbey Road",
                    "subtitle must omit the leading ' · ' when artist is empty")
        }
        function test_both_present_joins_with_middot() {
            seed(h, "Come Together", "The Beatles", "Abbey Road")
            var node = textContaining(h, "Abbey Road")
            verify(node !== null, "found the subtitle")
            verify(node.text.indexOf("The Beatles") === 0, "starts with the artist")
            verify(node.text.indexOf("·") > 0, "joins artist and album with a middot")
        }
        function test_artist_only_no_trailing_separator() {
            seed(h, "Track", "Solo Artist", "")
            var node = textContaining(h, "Solo Artist")
            verify(node !== null, "found the subtitle")
            compare(node.text, "Solo Artist", "no separator when only the artist is set")
        }
    }

    // ── progress bar: clamping + reactivity ──────────────────────────────────
    TestCase {
        name: "MediaProgress"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.item.accentName = "green"
            h.theme.reduceMotion = false
            h.mediaCtl.clearTrack()
            seed(h, "Song", "Artist", "Album")
        }

        function test_position_half_fills_half() {
            var fill = progressFill(h), track = progressTrack(h)
            verify(fill !== null && track !== null, "found the progress bar")
            h.mediaCtl.position = 0.5
            tryVerify(function () { return Math.abs(fill.width - track.width * 0.5) < 3 }, 1500,
                      "0.5 → half width")
        }
        function test_position_clamps_above_one() {
            var fill = progressFill(h), track = progressTrack(h)
            h.mediaCtl.position = 5.0
            tryVerify(function () { return Math.abs(fill.width - track.width) < 3 }, 1500,
                      "position 5.0 clamps to full width (not overflow)")
        }
        function test_position_clamps_below_zero() {
            var fill = progressFill(h), track = progressTrack(h)
            h.mediaCtl.position = -1.0
            tryVerify(function () { return fill.width < 2 }, 1500,
                      "position -1.0 clamps to zero width")
        }
        function test_position_reactive() {
            var fill = progressFill(h), track = progressTrack(h)
            h.mediaCtl.position = 0.2
            tryVerify(function () { return Math.abs(fill.width - track.width * 0.2) < 3 }, 1500)
            h.mediaCtl.position = 0.8
            tryVerify(function () { return Math.abs(fill.width - track.width * 0.8) < 3 }, 1500,
                      "progress updates reactively when position changes")
        }
    }

    // ── progress animation must honour reduceMotion (LOW-severity bug) ────────
    TestCase {
        name: "MediaProgressMotion"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.item.accentName = "green"
            h.mediaCtl.clearTrack()
            seed(h, "Song", "Artist", "Album")
        }
        function cleanup() { h.theme.reduceMotion = false }

        // The fill's `Behavior on width` is hardcoded to 400ms and ignores
        // theme.reduceMotion; with reduce-motion on the bar should SNAP, so a
        // frame after a jump the width is already at target.
        function test_reduce_motion_snaps_progress() {
            var fill = progressFill(h), track = progressTrack(h)
            h.theme.reduceMotion = true
            h.mediaCtl.position = 0.0
            tryVerify(function () { return fill.width < 2 }, 1500, "settled at zero")
            h.mediaCtl.position = 1.0
            wait(16)                          // one frame
            verify(Math.abs(fill.width - track.width) < 3,
                   "reduce-motion should snap the progress fill (no 400ms sweep); "
                   + "width=" + Math.round(fill.width) + " target=" + Math.round(track.width))
        }
    }

    // ── "nothing playing" placeholder + no stale content ─────────────────────
    TestCase {
        name: "MediaPlaceholder"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.item.accentName = "green"
            h.mediaCtl.clearTrack()
        }

        function test_placeholder_visible_when_unavailable() {
            compare(h.item.avail, false)
            var node = textContaining(h, "Nothing playing")
            verify(node !== null, "placeholder text present")
            verify(effVisible(node), "placeholder shows when nothing is playing")
        }
        function test_placeholder_hidden_when_available() {
            seed(h, "Song", "Artist", "Album")
            compare(h.item.avail, true)
            var node = textContaining(h, "Nothing playing")
            verify(node !== null, "placeholder node still exists")
            verify(!effVisible(node), "placeholder hides once a track is available")
        }
        function test_no_stale_title_after_clear() {
            seed(h, "Old Song", "Old Artist", "Old Album")
            compare(h.item.avail, true)
            h.mediaCtl.clearTrack()
            compare(h.item.avail, false)
            verify(textContaining(h, "Old Song") === null, "no stale title retained after clear")
            verify(textContaining(h, "Old Album") === null, "no stale album retained after clear")
        }
    }

    // ── album art fallback glyph ─────────────────────────────────────────────
    TestCase {
        name: "MediaArt"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.item.accentName = "green"
            h.mediaCtl.clearTrack()
        }

        function test_glyph_fallback_when_no_art() {
            seed(h, "Song", "Artist", "Album")
            h.mediaCtl.artUrl = ""
            // Two ♪ glyphs exist (compact + expanded); the compact one is hidden
            // in expanded mode, so require an EFFECTIVELY-visible fallback.
            var all = findAll(h.item, isText, [])
            var shown = false
            for (var i = 0; i < all.length; i++)
                if (all[i].text.indexOf("♪") >= 0 && effVisible(all[i])) shown = true
            verify(shown, "album-art ♪ fallback visible when the art image is not Ready")
        }
        function test_art_image_source_tracks_arturl() {
            // The art <Image> source must reactively follow media.artUrl (and the
            // ♪ fallback is gated on Image.status, not shown once Ready). We assert
            // the reactive binding, not offscreen decode (which is environment
            // dependent).
            seed(h, "Song", "Artist", "Album")
            var url = "https://example.com/cover-abc.png"
            h.mediaCtl.artUrl = url
            var imgs = findAll(h.item, isImage, [])
            var art = null
            for (var i = 0; i < imgs.length; i++)
                if (String(imgs[i].source) === url) art = imgs[i]
            verify(art !== null, "album-art Image source reactively tracks media.artUrl")
            // Its ♪ sibling is gated on status (not shown when the image is Ready).
            var sib = art.parent
            verify(sib !== null && sib.hasOwnProperty("radius"), "art sits in the art tile")
        }
    }

    // ── header status ────────────────────────────────────────────────────────
    // NOTE: the C++ bridge exposes the raw D-Bus service suffix as playerName
    // (a real medium bug) — not reproducible via MockMedia, which supplies a
    // friendly name. Here we pin the avail-gating of the header status.
    TestCase {
        name: "MediaHeaderStatus"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.mediaCtl.clearTrack()
        }
        function test_status_empty_when_unavailable() {
            compare(h.item.status, "", "no header status when nothing plays")
        }
        function test_status_shows_player_when_available() {
            seed(h, "Song", "Artist", "Album")
            compare(h.item.status, "MockPlayer", "header shows the player name when available")
        }
    }

    // ── real mouse clicks: compact play/pause ────────────────────────────────
    TestCase {
        name: "MediaCompactClick"
        when: windowShown
        function init() {
            tryVerify(function () { return hC.ready }, 3000)
            hC.mediaCtl.clearTrack()
        }
        function test_compact_playpause_fires_once() {
            seed(hC, "Song", "Artist", "Album")
            wait(32)
            var tps = transport(hC)
            verify(tps.length >= 1, "found the compact play/pause target (" + tps.length + ")")
            var before = hC.mediaCtl.playPauseCount
            mouseClick(tps[0])
            compare(hC.mediaCtl.playPauseCount, before + 1, "compact play/pause fired exactly once")
        }
        function test_compact_target_is_touch_sized() {
            seed(hC, "Song", "Artist", "Album")
            wait(32)
            var tps = transport(hC)
            verify(tps.length >= 1)
            var btn = tps[0].parent
            verify(btn.width >= 44 && btn.height >= 44,
                   "compact play/pause is a >=44px touch target (" + btn.width + "x" + btn.height + ")")
        }
    }

    // ── real mouse clicks: expanded prev / play / next ───────────────────────
    TestCase {
        name: "MediaExpandedClicks"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            h.item.accentName = "green"
            h.mediaCtl.clearTrack()
        }

        function transportSorted() {
            var tps = transport(h)
            // Expect prev(60) / play(76) / next(60); sort left-to-right.
            tps.sort(function (a, b) { return globalX(a) - globalX(b) })
            return tps
        }

        function test_three_transport_buttons_present() {
            seed(h, "Song", "Artist", "Album")
            wait(32)
            var tps = transportSorted()
            compare(tps.length, 3, "prev / play / next are all present and visible")
        }
        function test_prev_play_next_fire_independently() {
            seed(h, "Song", "Artist", "Album")
            wait(32)
            var tps = transportSorted()
            verify(tps.length === 3, "need three transport controls")
            var prevBtn = tps[0], playBtn = tps[1], nextBtn = tps[2]

            var p0 = h.mediaCtl.previousCount, pp0 = h.mediaCtl.playPauseCount, n0 = h.mediaCtl.nextCount
            mouseClick(prevBtn)
            compare(h.mediaCtl.previousCount, p0 + 1, "prev fired previous()")
            compare(h.mediaCtl.playPauseCount, pp0, "prev did not fire play/pause")
            compare(h.mediaCtl.nextCount, n0, "prev did not fire next")

            mouseClick(playBtn)
            compare(h.mediaCtl.playPauseCount, pp0 + 1, "middle button fired play/pause")
            compare(h.mediaCtl.previousCount, p0 + 1, "play did not fire prev again")

            mouseClick(nextBtn)
            compare(h.mediaCtl.nextCount, n0 + 1, "next fired next()")
            compare(h.mediaCtl.playPauseCount, pp0 + 1, "next did not fire play/pause")
        }
        function test_expanded_transport_are_touch_sized() {
            seed(h, "Song", "Artist", "Album")
            wait(32)
            var tps = transportSorted()
            for (var i = 0; i < tps.length; i++) {
                var b = tps[i].parent
                verify(b.width >= 44 && b.height >= 44,
                       "transport button " + i + " is >=44px (" + b.width + "x" + b.height + ")")
            }
        }
    }

    // ── shared config-schema area ────────────────────────────────────────────
    TestCase {
        name: "MediaSchema"
        when: windowShown

        function test_media_schema_has_title_and_appearance() {
            var s = sc.schemaFor("media")
            verify(s && s.sections && s.sections.length > 0, "media has a schema")
            var keys = {}
            for (var i = 0; i < s.sections.length; i++)
                for (var j = 0; j < (s.sections[i].fields || []).length; j++)
                    if (s.sections[i].fields[j].key) keys[s.sections[i].fields[j].key] = true
            verify(keys["title"] === true, "schema exposes a custom title")
            verify(keys["accent"] === true, "schema exposes a per-widget accent")
            verify(keys["cardBackdrop"] === true, "schema exposes a per-widget card backdrop")
        }
        function test_accent_default_is_empty() {
            var s = sc.schemaFor("media")
            var f = null
            for (var i = 0; i < s.sections.length; i++)
                for (var j = 0; j < (s.sections[i].fields || []).length; j++)
                    if (s.sections[i].fields[j].key === "accent") f = s.sections[i].fields[j]
            verify(f !== null, "accent field present")
            compare(f.dflt, "", "default accent is empty (this triggers the effAccent loop)")
        }
    }
}
