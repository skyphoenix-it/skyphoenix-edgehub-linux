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
//     "pages": [ { "name": "System", "tiles": [ { "id": "...", "type": "cpu",
//                                                 "size": "1x1" } ] } ],
//     "settings": { "<tileId>": { ...arbitrary per-widget state... } }
//   }
//
// `size` is a NAMED size from WidgetSizes (see that file for what a name means).
// It replaced the old `w`/`h` span pair, and it is a NEW KEY rather than a
// reinterpretation of the old ones for one decisive reason: a new key makes an
// old document STRUCTURALLY DETECTABLE. `size === undefined` ⇒ pre-migration,
// full stop. Reusing `w`/`h` would have silently reinterpreted them — old `h:2`
// meant "twice as tall as my siblings", new means "two thirds of the screen" —
// and there would have been no way to tell a migrated tile from a stale one.
// `version` cannot serve as that guard: it is WRITTEN (here and by
// PresetCatalog) but never read or branched on anywhere in the codebase, so
// every document on disk claims `1` regardless of its actual shape.
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

    // ── Tile sizes ───────────────────────────────────────────────────────────
    // The size vocabulary itself lives in WidgetSizes; which sizes a given widget
    // TYPE may legally take lives in WidgetCatalog. The store owns neither — it
    // only enforces them on the way in.
    property QtObject _sizes: WidgetSizes {}
    property QtObject _catalog: WidgetCatalog {}

    // The catalog's per-type size API is consulted defensively: the store is
    // instantiated standalone in tests (and the catalog gained these functions
    // separately), so an absent/older catalog must degrade to "legality alone"
    // rather than throw and take the whole dashboard down.
    function _catalogFn(name) {
        var c = store._catalog
        return (c && typeof c[name] === "function") ? c[name] : null
    }
    function _defaultSizeFor(type) {
        var fn = store._catalogFn("defaultSize")
        var d = fn ? fn(type) : null
        return store._sizes.isLegal(d) ? d : store._sizes.baseline
    }
    function _sizeSupported(type, size) {
        if (!store._sizes.isLegal(size)) return false
        var fn = store._catalogFn("supports")
        return fn ? (fn(type, size) === true) : true
    }

    // Geometry → the closest legal size name.
    //   shortFrac  — fraction of the short screen axis (the axis has exactly two
    //                stops: 0.5 and 1)
    //   longThirds — count of thirds along the long axis
    // An exact match wins. Otherwise the tile's SHARE OF THE SCREEN (area) is
    // preserved, because that is the closest honest proxy for the emphasis the
    // old sibling-ratio encoded: e.g. a half-wide two-thirds-tall tile (0.5x2 —
    // not a legal size, the short axis has no 2-thirds partner) and `1x1` both
    // occupy exactly a third of the screen, so the tile keeps its weight even
    // though it changes shape.
    function _nearestSize(shortFrac, longThirds) {
        var names = store._sizes.all()   // smallest → largest
        var i, s
        for (i = 0; i < names.length; i++) {
            s = store._sizes.table[names[i]]
            if (s.short === shortFrac && s.long === longThirds) return names[i]
        }
        var want = shortFrac * longThirds / 3
        var best = store._sizes.baseline, bestD = Infinity
        for (i = 0; i < names.length; i++) {
            var d = Math.abs(store._sizes.area(names[i]) - want)
            if (d < bestD - 1e-9) { bestD = d; best = names[i] }   // ties keep the smaller
        }
        return best
    }

    // Best-effort {w,h} → size for ONE tile. THIS IS LOSSY AND CANNOT BE OTHERWISE.
    //
    // Old `w` was a column span against the page's declared column count, so it
    // IS recoverable as a fraction: w/cols. Old `h` was a row span against
    // siblings — its on-screen height depended on how many rows the page happened
    // to pack, which nothing on disk records — whereas the new long axis is a
    // fixed count of thirds of the screen. So `h` is mapped 1:1 onto thirds
    // (h:1 → a third, h:2 → two thirds), which is exactly right only for a page
    // whose rows already totalled three, and merely proportional otherwise.
    function _migratedSize(tile, declaredCols) {
        var cols = Math.max(1, Math.min(6, Math.round(Number(declaredCols)) || 1))
        var span = Math.max(1, Math.min(Math.round(Number(tile.w)) || 1, cols))
        var frac = span / cols
        // Snap to the short axis' two stops, biasing to the WIDER one on a tie so
        // migration never shrinks a tile it simply cannot represent.
        var shortFrac = (Math.abs(frac - 0.5) < Math.abs(frac - 1)) ? 0.5 : 1
        // Mirror the old [1,2] span clamp: no pre-migration document could mean
        // more than 2 rows, so a crafted h:9999 must not become a full screen.
        var longThirds = Math.max(1, Math.min(2, Math.round(Number(tile.h)) || 1))
        return store._nearestSize(shortFrac, longThirds)
    }

    // Give one tile a legal, type-supported `size`, migrating it if needed.
    // Returns a human-readable note when the tile's stored intent changed meaning
    // (for the migration log), else "".
    function _coerceTileSize(tile, declaredCols) {
        var note = ""
        if (tile.size === undefined) {
            // No `size` key ⇒ pre-migration. The vast majority of stored tiles are
            // a bare {id,type} — `addTile` never wrote w/h — and carry no sizing
            // intent at all, so they land on whatever the page's column count
            // implies (with the default 1-column grid: the `1x1` baseline).
            var carriedIntent = (tile.w !== undefined || tile.h !== undefined)
            var before = "w:" + (tile.w !== undefined ? tile.w : "1(default)") +
                         " h:" + (tile.h !== undefined ? tile.h : "1(default)") +
                         " on a " + declaredCols + "-col page"
            tile.size = store._migratedSize(tile, declaredCols)
            // Only tiles that carried a REAL intent are worth reporting; logging
            // every bare {id,type} would bury the signal in the common case.
            if (carriedIntent) note = before + " → " + tile.size
        }
        if (!store._sizeSupported(tile.type, tile.size)) {
            var bad = tile.size
            tile.size = store._defaultSizeFor(tile.type)
            note = "unsupported size " + JSON.stringify(bad) + " → " + tile.size
        }
        // w/h are dead vocabulary. Leaving them would let a stale reader apply the
        // old ratio on top of the new size, and would defeat the `size === undefined`
        // detection above on the next load.
        delete tile.w
        delete tile.h
        return note
    }

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
        var migrationLog = []
        for (var i = 0; i < doc.pages.length; i++) {
            var p = doc.pages[i]
            if (!_isPlainObject(p)) continue
            if (typeof p.name !== "string" || p.name === "")
                p.name = "Page " + (cleanPages.length + 1)
            // The column count the old `w` span was measured against: the page
            // override, else the global grid setting, else 1 (Dashboard's own
            // resolution order). Dashboard additionally clamped this by the runtime
            // WIDTH — information that does not exist on disk and is unknowable
            // here, so the declared count is the best available truth.
            var declaredCols = Number(p.cols) || Number(doc.appearance.gridCols) || 1
            var srcTiles = Array.isArray(p.tiles) ? p.tiles : []
            var cleanTiles = []
            for (var j = 0; j < srcTiles.length; j++) {
                var t = srcTiles[j]
                if (_isPlainObject(t) && typeof t.id === "string" && t.id !== "") {
                    // Every tile entering `data` leaves here with a legal, supported
                    // `size` — migrated from w/h, or coerced if the document handed
                    // us junk. This runs on load AND applyExternal (another process
                    // pushes that one), so it is the hostile-input boundary too.
                    var note = _coerceTileSize(t, declaredCols)
                    if (note !== "") migrationLog.push(p.name + "/" + t.type + " " + note)
                    cleanTiles.push(t)
                }
            }
            p.tiles = cleanTiles
            // `cols` chose how many columns the page laid its tiles out in. The grid
            // is now FIXED at WidgetSizes.shortHalves (2 half-cells) across the short
            // axis, because a size is a fraction of the SCREEN — a user-chosen column
            // count would make `1x1` mean something different per page, which is the
            // exact property the size model exists to remove. So the key is dead, and
            // it is dropped HERE rather than left to rot: it is read one last time
            // just above (it is the only record of what the old `w` span was measured
            // against) and must not survive to be read again by a later pass.
            delete p.cols
            cleanPages.push(p)
        }
        doc.pages = cleanPages
        // The global default behind the per-page `cols`, dead for the same reason.
        delete doc.appearance.gridCols
        // Best-effort migration is REPORTED, never silent: the user's layout is
        // preserved as closely as the two vocabularies allow (a tile is never
        // dropped, and nothing is re-seeded from a preset), but a tile whose old
        // height was a sibling-ratio may well have changed its share of the screen,
        // and that is not something to hide.
        //
        // A migrated page may exceed the screen's 6 long half-cells — six bare
        // {id,type} tiles become 6 × `1x1` = 12, two screens' worth. That is fine
        // and deliberate: the store does not do capacity. Forcing tiles to fit here
        // would silently destroy the layout this function exists to preserve, so a
        // long page is placed in full by WidgetPacker and SCROLLS (Dashboard.qml).
        if (migrationLog.length)
            console.log("DashboardStore: migrated " + migrationLog.length +
                        " tile(s) from the w/h span vocabulary to named sizes " +
                        "(best-effort: old h was a ratio against sibling tiles, a " +
                        "size is a fraction of the screen):\n  " + migrationLog.join("\n  "))

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
            // Seeded docs are normalised too: the curated presets still declare the
            // old w/h vocabulary, so this is what gives a fresh install's tiles a
            // `size` — the invariant "every tile in `data` has one" must hold on
            // EVERY path into `data`, not just the load-from-disk one.
            data = _normaliseDoc(seed(seedLayout && seedLayout.length ? seedLayout : "productivity"))
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
        // A freshly-added tile is born WITH a size, so `size === undefined` keeps
        // meaning exactly one thing — "this document predates the size key" — and
        // never "this tile is simply new".
        data.pages[pageIdx].tiles.push({ "id": id, "type": type, "size": _defaultSizeFor(type) })
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
    // Set a tile's NAMED size (a WidgetSizes name — not a w/h span). Rejects a
    // size the widget type does not support, so the picker/drag UI cannot put a
    // tile into a shape its widget was never built to render. Returns whether the
    // size was applied.
    function setTileSize(pageIdx, tileId, size) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return false
        var tiles = data.pages[pageIdx].tiles
        for (var i = 0; i < tiles.length; i++) {
            if (tiles[i].id === tileId) {
                if (!_sizeSupported(tiles[i].type, size)) return false
                tiles[i].size = size
                _commitStructure()
                return true
            }
        }
        return false
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
    //
    // DEAD, and kept only because its callers are: the column pickers in
    // ui/qml/widgets/SettingsPanel.qml and manager/qml/Manager.qml still bind to
    // these, and deleting the functions under a live binding is a TypeError, not a
    // clean removal. Nothing READS the count any more — the grid is fixed at 2
    // half-cells across — and `_normaliseDoc` strips `cols`/`gridCols` off the
    // document, so a value written here does not survive a reload. Removing the two
    // pickers and then these two functions is a tracked follow-up.
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
        data = _normaliseDoc(seed(seedLayout || "productivity"))
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
