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

    // Bump reactivity for in-place settings mutations, schedule a save.
    function _touchSettings() { revision++; changed(); saveTimer.restart() }

    // Reassign `data` (clone) for structural mutations so Repeaters refresh.
    function _commitStructure() {
        data = _clone(data)
        revision++
        changed()
        saveTimer.restart()
    }

    // ── Load / seed ──────────────────────────────────────────────────────
    function load(seedLayout) {
        var raw = _hasBridge() ? configBridge.uiState() : ""
        var parsed = null
        if (raw && raw.length) {
            try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
        }
        if (parsed && parsed.pages && parsed.pages.length) {
            if (!parsed.settings) parsed.settings = {}
            if (!parsed.appearance) parsed.appearance = {}
            delete parsed.settings[""]   // scrub any stray empty-id state
            data = parsed
        } else {
            data = seed(seedLayout && seedLayout.length ? seedLayout : "productivity")
            _flush()
        }
        loaded = true
        revision++
        changed()
    }

    // ── Appearance ─────────────────────────────────────────────────────────
    function appearance() { return data.appearance || {} }
    function setAppearance(key, val) {
        if (!data.appearance) data.appearance = {}
        data.appearance[key] = val
        _touchSettings()
    }

    // ── Per-widget settings ─────────────────────────────────────────────────
    function settingsFor(id) {
        if (!data.settings) data.settings = {}
        if (!data.settings[id]) data.settings[id] = {}
        return data.settings[id]
    }
    // Seed defaults for an instance without clobbering existing values.
    function ensureSettings(id, defaults) {
        var s = settingsFor(id)
        for (var k in defaults)
            if (s[k] === undefined) s[k] = defaults[k]
        return s
    }
    function setSetting(id, key, val) {
        settingsFor(id)[key] = val
        _touchSettings()
    }
    function patchSettings(id, obj) {
        var s = settingsFor(id)
        for (var k in obj) s[k] = obj[k]
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
        var tiles = data.pages[pageIdx].tiles
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
        var tiles = data.pages[pageIdx].tiles
        if (fromIdx < 0 || fromIdx >= tiles.length) return
        toIdx = Math.max(0, Math.min(tiles.length - 1, toIdx))
        if (fromIdx === toIdx) return
        var t = tiles.splice(fromIdx, 1)[0]
        tiles.splice(toIdx, 0, t)
        _commitStructure()
    }
    function addPage(name) {
        data.pages.push({ "name": name || ("Page " + (data.pages.length + 1)), "tiles": [] })
        _commitStructure()
    }
    function removePage(pageIdx) {
        if (data.pages.length <= 1) return   // keep at least one page
        var removed = data.pages.splice(pageIdx, 1)[0]
        if (removed && data.settings)
            for (var i = 0; i < removed.tiles.length; i++)
                delete data.settings[removed.tiles[i].id]
        _commitStructure()
    }
    function renamePage(pageIdx, name) {
        if (pageIdx < 0 || pageIdx >= data.pages.length) return
        data.pages[pageIdx].name = name
        _commitStructure()
    }

    // Reset the whole dashboard to a named starter layout.
    function resetTo(seedLayout) {
        data = seed(seedLayout || "productivity")
        loaded = true
        _commitStructure()
        flushNow()
    }

    // ── Starter layouts (seed the grid from the wizard's choice) ──────────────
    function _mk(type) { return { "id": type + "-" + (_idSeq++), "type": type } }
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
