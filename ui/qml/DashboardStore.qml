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

    function _hasBridge() {
        return (typeof configBridge !== "undefined") && configBridge
    }

    function _flush() {
        if (_hasBridge())
            configBridge.saveUiState(JSON.stringify(store.data))
    }

    // Force an immediate (non-debounced) save — used on structural edits.
    function flushNow() { saveTimer.stop(); _flush() }

    function _clone(o) { return JSON.parse(JSON.stringify(o)) }

    // Normalise a loaded/pushed document in place: ensure the standard maps
    // exist, guarantee every page carries a `tiles` array, and prune settings
    // whose id is no longer owned by any tile (plus the stray empty-id entry).
    function _normaliseDoc(doc) {
        if (!doc.appearance) doc.appearance = {}
        if (!doc.settings) doc.settings = {}
        if (!doc.pages) doc.pages = []
        var live = {}
        for (var i = 0; i < doc.pages.length; i++) {
            var p = doc.pages[i]
            if (!p.tiles) p.tiles = []
            for (var j = 0; j < p.tiles.length; j++) live[p.tiles[j].id] = true
        }
        for (var key in doc.settings)
            if (!live.hasOwnProperty(key)) delete doc.settings[key]
        return doc
    }

    // Bump reactivity for in-place settings mutations, schedule a save.
    function _touchSettings() { revision++; changed(); saveTimer.restart() }

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
        for (var k in defaults)
            if (s[k] === undefined) s[k] = defaults[k]
        _touchSettings()
        return s
    }
    function setSetting(id, key, val) {
        var s = _bucket(id)
        if (!s) return
        s[key] = val
        _touchSettings()
    }
    function patchSettings(id, obj) {
        var s = _bucket(id)
        if (!s) return
        for (var k in obj) s[k] = obj[k]
        _touchSettings()
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
                tiles[i].w = w
                tiles[i].h = h
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
        var existing = {}
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
        var others = {}
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

    // ── Starter layouts (seed the grid from the wizard's choice) ──────────────
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
    function seed(which) {
        var doc = { "version": 1, "appearance": {}, "settings": {}, "pages": [] }
        switch (which) {
        case "gaming":
            doc.pages = [
                _page("System", ["cpu", "gpu", "ram", "net", "disk", "sensors"]),
                _page("Play",   ["clock", "weather", "focus", "media"]),
            ]
            break
        case "minimal":
            doc.pages = [
                _page("Home", ["clock", "weather", "focus", "media"]),
            ]
            break
        case "blank":
            doc.pages = [ { "name": "Home", "tiles": [] } ]
            break
        case "productivity":
        default:
            doc.pages = [
                _page("Focus",  ["focus", "tasks", "rightnow", "habit", "hydration", "break"]),
                _page("System", ["cpu", "gpu", "ram", "net", "disk", "clock"]),
                _page("Life",   ["calendar", "weather", "media", "countdown", "eod", "moon"]),
            ]
            break
        }
        return doc
    }
}
