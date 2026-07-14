import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// DashboardStore — the single source of truth for the dashboard.
//
// Owns the persisted UI-state document (layout + per-widget settings +
// appearance) and mediates all reads/writes. Persistence goes through the C++
// `configBridge` (→ Rust config, atomic XDG write). Reactivity is provided by
// `revision`: every mutation bumps it, so widgets that bind through it re-read
// automatically — this is what lets a tile and its expanded overlay (two
// separate instances) share the same live state.
//
// Document schema (JSON):
//   {
//     "version": 1,
//     "appearance": { themeMode, accent, glass, glow, reduceMotion },
//     "pages": [ { "name": "System", "tiles": [ { "id": "...", "type": "cpu" } ] } ],
//     "settings": { "<tileId>": { ...arbitrary per-widget state... } }
//   }
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: store
    visible: false

    // The full document. Structural changes reassign this (clone) to fire
    // bindings; per-widget settings changes mutate in place + bump `revision`.
    property var data: ({ "version": 1, "appearance": {}, "pages": [], "settings": {} })
    property int revision: 0
    // Bumps ONLY on structural changes (pages/tiles added/removed/moved/resized,
    // page rename/bg/cols, load/applyExternal). The dashboard's page+tile Repeater
    // binds to THIS, not `revision`, so per-widget settings edits (which fire every
    // keystroke/toggle) no longer tear down and rebuild every tile Loader.
    property int structureRevision: 0
    property bool loaded: false

    signal changed()

    Timer {
        id: saveTimer
        interval: 400; repeat: false
        onTriggered: store._flush()
    }
    // True while a debounced disk save is pending (introspection for tests).
    readonly property alias _savePending: saveTimer.running

    function _hasBridge() {
        return (typeof configBridge !== "undefined") && configBridge
    }

    // Setting keys that hold volatile, per-session runtime state (metric sparkline
    // history + session peaks). They are shared in memory so the compact tile and
    // its expanded overlay draw the same sparkline, but they must NEVER be persisted
    // or schedule a disk write — otherwise the metric widgets rewrite config.toml on
    // every sample (~2s), which is constant flash wear on the device and races the
    // Manager's own save (transient ENOENT). They're also stripped from the on-disk
    // document, so a genuine save never carries stale history across restarts (S4).
    // Volatile per-session keys that must NEVER reach config.toml. `hist`/`peakRx`/
    // `peakTx` back the metric sparklines; `http*` back the HTTP/JSON + KPI polling
    // primitives (value/text/error/list) — a poll every N seconds must not rewrite
    // the config (flash wear + a save race with the Manager).
    readonly property var _ephemeralKeys: ({ "hist": true, "peakRx": true, "peakTx": true,
        "httpVal": true, "httpText": true, "httpErr": true, "httpList": true, "httpAt": true })
    function _isEphemeralKey(k) { return store._ephemeralKeys[k] === true }

    // Deep copy of the document with all ephemeral runtime keys removed — the exact
    // bytes written to disk.
    function _persistableData() {
        var d = _clone(store.data)
        if (d.settings) {
            for (var id in d.settings) {
                var b = d.settings[id]
                for (var k in store._ephemeralKeys)
                    if (b[k] !== undefined) delete b[k]
            }
        }
        return d
    }

    function _flush() {
        if (_hasBridge())
            configBridge.saveUiState(JSON.stringify(store._persistableData()))
    }

    // Force an immediate (non-debounced) save — used on structural edits.
    function flushNow() { saveTimer.stop(); _flush() }

    function _clone(o) { return JSON.parse(JSON.stringify(o)) }

    // Validate + normalise a loaded/pushed document in place. `load`/applyExternal
    // only gate on truthiness, so a corrupt or hostile doc (`"pages":5`,
    // `"pages":{}`, string/number tiles, id-less tiles, a non-object `settings`)
    // would otherwise reach the page/tile Repeater and `addTile` → TypeError →
    // blank dashboard. This coerces every structural field into the exact shape the
    // rest of the store and the QML assume, dropping anything that can't be healed.
    function _isPlainObject(v) {
        return v !== null && typeof v === "object" && !Array.isArray(v)
    }
    function _normaliseDoc(doc) {
        if (!_isPlainObject(doc.appearance)) doc.appearance = {}
        if (!_isPlainObject(doc.settings)) doc.settings = {}
        // Pages MUST be an array; anything else (number/object/string/null) is junk.
        if (!Array.isArray(doc.pages)) doc.pages = []

        // Coerce each page into a well-formed { name:String, tiles:[objects with a
        // non-empty string id] }. Non-object pages are dropped entirely; a page's
        // tiles array is reset to [] when it isn't an array; each tile survives only
        // if it's a plain object carrying a non-empty string id (a bare string,
        // number, or id-less object is dropped rather than crashing addTile/binds).
        var cleanPages = []
        for (var i = 0; i < doc.pages.length; i++) {
            var p = doc.pages[i]
            if (!_isPlainObject(p)) continue
            if (typeof p.name !== "string" || p.name === "")
                p.name = "Page " + (cleanPages.length + 1)
            var srcTiles = Array.isArray(p.tiles) ? p.tiles : []
            var cleanTiles = []
            for (var j = 0; j < srcTiles.length; j++) {
                var t = srcTiles[j]
                if (_isPlainObject(t) && typeof t.id === "string" && t.id !== "") {
                    // Clamp span to [1,2]: a crafted/corrupt w/h (e.g. h:9999) would
                    // otherwise drive a runaway rowSpan and blow up the grid layout.
                    if (t.w !== undefined) t.w = Math.max(1, Math.min(2, Math.round(Number(t.w)) || 1))
                    if (t.h !== undefined) t.h = Math.max(1, Math.min(2, Math.round(Number(t.h)) || 1))
                    cleanTiles.push(t)
                }
            }
            p.tiles = cleanTiles
            cleanPages.push(p)
        }
        doc.pages = cleanPages

        // De-duplicate page names on load. renamePage/addPage reject NEW collisions,
        // but a config that already carries two identical page names (the real "two
        // Page 5 tabs" bug) was never reconciled. Walk in order, keep the first
        // occurrence, and disambiguate later duplicates deterministically by
        // appending " 2", " 3", … — tiles/order/all other fields are untouched.
        var seenNames = Object.create(null)
        for (var n = 0; n < doc.pages.length; n++) {
            var pg = doc.pages[n]
            var nm = String(pg.name)
            if (seenNames[nm]) {
                var suffix = 2
                while (seenNames[nm + " " + suffix]) suffix++
                nm = nm + " " + suffix
                pg.name = nm
            }
            seenNames[nm] = true
        }
        // Prune settings whose id is no longer owned by any surviving tile (plus the
        // stray empty-id entry).
        var live = {}
        for (var k = 0; k < doc.pages.length; k++) {
            var tiles = doc.pages[k].tiles
            for (var j2 = 0; j2 < tiles.length; j2++) live[tiles[j2].id] = true
        }
        for (var key in doc.settings)
            if (!live.hasOwnProperty(key)) delete doc.settings[key]
        return doc
    }

    // Bump reactivity for in-place settings mutations. `persist` (default true)
    // controls whether a disk save is scheduled: volatile metric writes bump
    // revision so the live sparkline updates, but do not touch disk.
    function _touchSettings(persist) {
        revision++
        changed()
        if (persist === undefined || persist) saveTimer.restart()
    }

    // Reassign `data` (clone) for structural mutations so Repeaters refresh.
    // Structural edits are force-flushed (not debounced) so a page/tile added
    // outside edit mode survives an abrupt power-off.
    function _commitStructure() {
        data = _clone(data)
        revision++
        structureRevision++
        changed()
        flushNow()
    }

    // ── Load / seed ──────────────────────────────────────────────────────
    function load(seedLayout) {
        var raw = _hasBridge() ? configBridge.uiState() : ""
        var parsed = null
        if (raw && raw.length) {
            try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
        }
        // Honour any valid saved layout — including an intentionally-blank
        // pages:[] — consistently with applyExternal(); only re-seed when there
        // is no usable document at all.
        if (parsed && parsed.pages) {
            data = _normaliseDoc(parsed)
        } else {
            data = seed(seedLayout && seedLayout.length ? seedLayout : "productivity")
            _flush()
        }
        loaded = true
        revision++
        structureRevision++
        changed()
    }

    // Apply a UI-state document pushed from the companion Manager app (over the
    // hub's control socket). Reassigns `data` and bumps reactivity so the live
    // dashboard rebuilds — WITHOUT persisting again (the hub already saved it).
    function applyExternal(json) {
        var parsed = null
        try { parsed = JSON.parse(json) } catch (e) { parsed = null }
        if (!parsed || !parsed.pages) return false
        // Cancel any pending debounced save so the externally-applied doc is
        // never echoed back to the hub 400ms later.
        saveTimer.stop()
        data = _normaliseDoc(parsed)
        loaded = true
        revision++
        structureRevision++
        changed()
        return true
    }

    // ── Appearance ─────────────────────────────────────────────────────────
    function appearance() { return data.appearance || {} }
    function setAppearance(key, val) {
        if (!data.appearance) data.appearance = {}
        data.appearance[key] = val
        _touchSettings()
    }

    // ── Per-widget settings ─────────────────────────────────────────────────
    // NON-mutating read: returns the live settings object when it exists, else a
    // throwaway empty default. Must NOT create a persisted entry — it is called
    // inside widget bindings (with a possibly-empty instanceId), and materialising
    // ghost `{}`/`settings['']` entries would grow and poison the document.
    function settingsFor(id) {
        if (!id || !data.settings || !data.settings[id]) return ({})
        return data.settings[id]
    }
    // Get-or-create the persisted bucket for a MUTATION. Empty ids are rejected.
    function _bucket(id) {
        if (!id) return null
        if (!data.settings) data.settings = {}
        if (!data.settings[id]) data.settings[id] = {}
        return data.settings[id]
    }
    // Seed defaults for an instance without clobbering existing values. Bumps
    // revision (so a second instance — the expanded overlay — re-reads the seeded
    // values) and schedules a save (so defaults survive an immediate close).
    function ensureSettings(id, defaults) {
        var s = _bucket(id)
        if (!s) return ({})
        // Only bump revision + schedule a save when a default was ACTUALLY seeded.
        // Otherwise every tile Loader rebuild (e.g. after applyExternal bumps
        // structureRevision) re-ran ensureSettings → unconditional _touchSettings →
        // a redundant ~400ms flash write echoing back the doc the hub just pushed.
        var added = false
        for (var k in defaults)
            if (s[k] === undefined) { s[k] = defaults[k]; added = true }
        if (added) _touchSettings()
        return s
    }
    function setSetting(id, key, val) {
        var s = _bucket(id)
        if (!s) return
        s[key] = val
        // A write to a volatile metric key bumps reactivity but is never persisted.
        _touchSettings(!_isEphemeralKey(key))
    }
    function patchSettings(id, obj) {
        var s = _bucket(id)
        if (!s) return
        var persist = false
        for (var k in obj) { s[k] = obj[k]; if (!_isEphemeralKey(k)) persist = true }
        // Persist only when the patch carries at least one real (non-volatile) key.
        _touchSettings(persist)
    }
    // Replace an instance's settings with a DEEP COPY of `defaults` (drops any
    // stale keys). The clone is essential: assigning array/object defaults by
    // reference would share one instance across every reset (e.g. every widget's
    // tasks:[] becoming the same list). Used by "Reset to defaults".
    function resetSettings(id, defaults) {
        var s = _bucket(id)
        if (!s) return
        for (var k in s) delete s[k]
        var d = _clone(defaults || {})
        for (var kk in d) s[kk] = d[kk]
        _touchSettings()
    }

    // ── Pages / tiles ────────────────────────────────────────────────────────
    function pages() { return data.pages || [] }
    function pageCount() { return pages().length }

    function _newId(type) {
        // Stable-ish unique id from type + revision + running counter.
        _idSeq++
        return type + "-" + _idSeq + "-" + revision
    }
    property int _idSeq: 0

    function addTile(pageIdx, type) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        var id = _newId(type)
        data.pages[pageIdx].tiles.push({ "id": id, "type": type })
        _commitStructure()
        return id
    }
    function removeTile(pageIdx, tileId) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        var tiles = data.pages[pageIdx].tiles || []
        for (var i = 0; i < tiles.length; i++) {
            if (tiles[i].id === tileId) {
                tiles.splice(i, 1)
                if (data.settings) delete data.settings[tileId]
                _commitStructure()
                return
            }
        }
    }
    // Cycle sizes: 1x1 -> 2x1 (wide) -> 1x2 (tall) -> 2x2 (large) -> 1x1
    function setTileSize(pageIdx, tileId, w, h) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        var tiles = data.pages[pageIdx].tiles
        for (var i = 0; i < tiles.length; i++) {
            if (tiles[i].id === tileId) {
                tiles[i].w = Math.max(1, Math.min(2, Math.round(Number(w)) || 1))
                tiles[i].h = Math.max(1, Math.min(2, Math.round(Number(h)) || 1))
                _commitStructure()
                return
            }
        }
    }
    function moveTile(pageIdx, fromIdx, toIdx) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        var tiles = data.pages[pageIdx].tiles || []
        if (fromIdx < 0 || fromIdx >= tiles.length) return
        toIdx = Math.max(0, Math.min(tiles.length - 1, toIdx))
        if (fromIdx === toIdx) return
        var t = tiles.splice(fromIdx, 1)[0]
        tiles.splice(toIdx, 0, t)
        _commitStructure()
    }
    function addPage(name) {
        data.pages.push({ "name": name || _uniquePageName(), "tiles": [] })
        _commitStructure()
    }
    // Generate a "Page N" name that doesn't collide with existing page names.
    function _uniquePageName() {
        var existing = Object.create(null)
        for (var i = 0; i < data.pages.length; i++) existing[data.pages[i].name] = true
        var n = data.pages.length + 1
        while (existing["Page " + n]) n++
        return "Page " + n
    }
    function removePage(pageIdx) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return   // ignore out-of-range
        if (data.pages.length <= 1) return   // keep at least one page
        var removed = data.pages.splice(pageIdx, 1)[0]
        if (removed && data.settings)
            for (var i = 0; i < removed.tiles.length; i++)
                delete data.settings[removed.tiles[i].id]
        _commitStructure()
    }
    // Validated: trims, keeps the old name if blank, and de-duplicates against the
    // other pages (so the tab bar never gets an empty or ambiguous label).
    function renamePage(pageIdx, name) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        var trimmed = String(name || "").trim()
        if (trimmed === "") trimmed = data.pages[pageIdx].name
        var others = Object.create(null)
        for (var i = 0; i < data.pages.length; i++)
            if (i !== pageIdx) others[data.pages[i].name] = true
        if (others[trimmed]) {
            var base = trimmed, n = 2
            while (others[base + " " + n]) n++
            trimmed = base + " " + n
        }
        data.pages[pageIdx].name = trimmed
        _commitStructure()
    }

    // Per-page background override: key ∈ {"style","wallpaper"}. Empty value
    // clears the override so the page falls back to the global appearance.
    function setPageBackground(pageIdx, key, val) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        if (!data.pages[pageIdx].bg) data.pages[pageIdx].bg = {}
        if (val === "" || val === null || val === undefined)
            delete data.pages[pageIdx].bg[key]
        else
            data.pages[pageIdx].bg[key] = val
        _commitStructure()
    }
    function pageBackground(pageIdx) {
        var ps = pages()
        var p = (pageIdx >= 0 && pageIdx < ps.length) ? ps[pageIdx] : {}
        return p.bg || {}
    }

    // Per-page column count override (0 = use the global appearance default).
    function setPageColumns(pageIdx, cols) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        if (!cols || cols <= 0) delete data.pages[pageIdx].cols
        else data.pages[pageIdx].cols = cols
        _commitStructure()
    }
    function pageColumns(pageIdx) {
        var ps = pages()
        var p = (pageIdx >= 0 && pageIdx < ps.length) ? ps[pageIdx] : {}
        return p.cols || 0
    }

    // Reset the whole dashboard to a named starter layout.
    function resetTo(seedLayout) {
        data = seed(seedLayout || "productivity")
        loaded = true
        _commitStructure()   // force-flushes; no extra save needed
    }

    // ── Starter layouts (seed the grid from the wizard's / preset choice) ─────
    // The curated preset library is the source of truth for starter layouts; the
    // legacy _mk/_page helpers are kept for any code-built layouts.
    property QtObject _presetCatalog: PresetCatalog {}
    function _mk(type) {
        var id = type + "-" + (_idSeq++)
        // Guard the fresh-launch counter reset: if a persisted settings bucket
        // still owns this id from a prior session, drop it so the freshly-seeded
        // tile can't silently inherit stale state.
        if (data.settings && data.settings.hasOwnProperty(id)) delete data.settings[id]
        return { "id": id, "type": type }
    }
    function _page(name, types) {
        var tiles = []
        for (var i = 0; i < types.length; i++) tiles.push(_mk(types[i]))
        return { "name": name, "tiles": tiles }
    }
    function _blankDoc() {
        return { "version": 1, "appearance": {}, "settings": {}, "pages": [ { "name": "Home", "tiles": [] } ] }
    }
    function seed(which) {
        if (which === "blank") return _blankDoc()
        // Route through the curated preset library. Legacy ids "productivity",
        // "gaming", "minimal" are preset ids too, so old configs keep working.
        var id = (which && _presetCatalog.has(which)) ? which : "productivity"
        var doc = _presetCatalog.buildDoc(id)
        return doc ? doc : _blankDoc()
    }
}
