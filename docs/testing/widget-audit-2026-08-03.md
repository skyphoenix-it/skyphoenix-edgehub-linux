# Widget-by-widget feature audit (opened 2026-08-03)

Running record for a full pass over all 30 catalog widgets: enumerate what each
one actually offers, prove every option is honoured, and file what is not.

## Why this exists

`ui/qml/WidgetConfigSchema.qml` opens with a promise:

> IMPORTANT: every option here is honoured by the corresponding widget - nothing
> is decorative.

Nothing verifies that promise. The enumerated-requirements matrix
(`scripts/qml_coverage.py`) requires every `schema:<widget>.<key>` to be
"assertion-backed", but its bar is that *some* assertion mentions the key's leaf
token — and a schema-shape test (`findField(s, "showPerCore")`, then asserting it
is a toggle whose default is `true`) satisfies that bar completely while proving
nothing about the widget. A regression that ignored the option entirely would
ship green.

So the matrix answers "is this option declared and shaped correctly?" This audit
answers the different question: **does the widget do what the option says?**

## Method, per widget

1. **Enumerate** the feature surface: every `schema:` key, the catalog `sizes`
   the widget claims, and the states it renders (nominal / zero / saturated /
   empty / error, compact vs roomy tile vs expanded, micro).
2. **Classify** each key by the strongest coverage that exists today:
   - `behaviour` — a test sets the key and asserts the widget's response
   - `shape-only` — a test asserts the schema field's type/default and nothing else
   - `absent` — no test names it at all
3. **Exercise** everything that is not `behaviour`. Read the widget source to
   find what the key is supposed to do, then assert it.
4. **Record** every mismatch below and file it in `BACKLOG.md`. A key the widget
   does not read is a broken promise; a help string that describes the wrong
   place is a user-facing defect even when the option works.
5. **Fix** them one at a time, each with a negative control proving the new
   assertion fails when the behaviour is removed.

Coverage added by this audit lives with the widget's existing tests
(`tests/ui/tst_gen_<widget>.qml` for logic, `tests/gui/` for rendered state), not
in a new parallel suite.

## Progress

| # | Widget | Audited | Findings | Fixed |
|---|---|---|---|---|
| 1 | cpu | 2026-08-03 | 2 | 2 |
| 2 | gpu | — | — | — |
| 3 | ram | — | — | — |
| 4 | net | — | — | — |
| 5 | disk | — | — | — |
| 6 | sensors | — | — | — |
| 7 | packages | — | — | — |
| 8 | sinceinstall | — | — | — |
| 9 | clock | — | — | — |
| 10 | analog | — | — | — |
| 11 | moon | — | — | — |
| 12 | focus | — | — | — |
| 13 | tasks | — | — | — |
| 14 | rightnow | — | — | — |
| 15 | notes | — | — | — |
| 16 | habit | — | — | — |
| 17 | hydration | — | — | — |
| 18 | break | — | — | — |
| 19 | meds | — | — | — |
| 20 | braindump | — | — | — |
| 21 | routine | — | — | — |
| 22 | media | — | — | — |
| 23 | httpjson | — | — | — |
| 24 | kpi | — | — | — |
| 25 | calendar | — | — | — |
| 26 | nownext | — | — | — |
| 27 | weather | — | — | — |
| 28 | countdown | — | — | — |
| 29 | eod | — | — | — |
| 30 | quote | — | — | — |

---

## 1. cpu

Schema keys: `showTemp`, `tempSource`, `showHistory`, `historyWindow`,
`graphStyle`, `showFrequency`, `showLoadAverage`, `showPerCore`,
`showTopProcess`, `warnTemp`, plus the universal `title` / `accent` /
`cardBackdrop`.

| key | coverage before this audit |
|---|---|
| `tempSource` | **behaviour** — all three modes, plus the missing-requested-sensor path |
| `historyWindow` | **behaviour** — retention limit and live pruning |
| `showTemp` | **behaviour** |
| `showHistory` | **behaviour** |
| `warnTemp` | **behaviour** |
| `showFrequency` | **shape-only** |
| `showLoadAverage` | **shape-only** |
| `showPerCore` | **shape-only** |
| `showTopProcess` | **shape-only** |

### Finding 1.1 — four display toggles have no behaviour coverage

`showFrequency`, `showLoadAverage`, `showPerCore` and `showTopProcess` appear in
the test suite only inside `test_config_schema_*`, which resolves the field and
checks its `type`/`dflt`. The widget does read all four
(`CpuWidget.qml:37-40`, gating `expandedDetails`, `glanceDetails` and the
per-core section), so they work today — but nothing would notice if they stopped.

### Finding 1.2 — two help strings name the wrong surface

Both of these tell the user the option only affects the expanded view. Both also
change the ordinary tile:

- `showPerCore` — help says *"Expanded view shows live activity for the eight
  busiest logical CPUs."* The section's condition is
  `(w.expanded || w.roomyTile)` (`CpuWidget.qml:324`), and `roomyTile` is
  explicitly `!w.expanded` (a tall tile over 1000px, or a wide one over 1000px).
  So it also drives a large tile.
- `showTopProcess` — help says *"Expanded view shows the local process using the
  most CPU in the latest sample."* It is also one of `glanceDetails`
  (`CpuWidget.qml:227`), which returns `[]` **only** when `micro || expanded` —
  i.e. it is the compact-tile path.

A user turning these off to declutter a *tile* would be told the setting does
not apply there.

### Both fixed 2026-08-03

- **1.1** — four behaviour tests added to `tests/ui/tst_gen_cpu.qml`, each driving
  the real setting through the store and asserting the surface it governs:
  `expandedDetails` for the expanded view and `glanceDetails` / the
  `cpuCorePanel` item for the tile. Negative control: making all four properties
  ignore `cfg` (`readonly property bool X: true`) fails all four tests; reverted,
  all four pass. The per-core case also pins the "eight busiest, sorted" contract
  and that empty core data hides the panel regardless of the toggle.
- **1.2** — both help strings now name every surface they govern:
  *"…in the expanded view and on a large tile"* and *"…on the tile and in the
  expanded view"*.
