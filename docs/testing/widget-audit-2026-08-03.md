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
| 2 | gpu | 2026-08-03 | 1 | 1 |
| 3 | ram | 2026-08-03 | 1 | 1 |
| 4 | net | 2026-08-03 | 1 | 1 |
| 5 | disk | 2026-08-03 | 1 | 1 |
| 6 | sensors | 2026-08-03 | 2 | 2 |
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

---

## 2. gpu

Schema keys: `gpuDevice`, `showTemp`, `showHistory`, `showDetails`, `warnTemp`,
plus the universal three.

Better shape than cpu: `showTemp` (header temperature disappears), `showHistory`
(sparkline is fed an empty history while sampling continues), `warnTemp`
(thermal state) and `gpuDevice` (selection, and the not-connected path) all have
real behaviour coverage.

### Finding 2.1 — `showDetails` had property-level coverage only

Tests proved the setting REACHED the widget (`compare(w.showDetails, false)`) but
never asserted either surface it governs: the `MetricGauge` `sub:` line
(`GpuWidget.qml:244`) and the `gpuDetailPanel` visibility (`:271`). A widget that
read the property and then ignored it would have passed.

**Fixed 2026-08-03.** `test_show_details_toggle_gates_both_surfaces` feeds a real
device (so there IS a hardware detail to show — the point of the toggle) and
asserts both surfaces on and off. Needed a `findObjectName` helper in that file,
so an assertion can name the exact item a setting governs instead of a
shape-alike. Negative control: making `showDetails` ignore `cfg` fails the test;
reverted, it passes.

### Note — this widget's own test file carries three unfiled bug notes

`tst_gen_gpu.qml` contains three `BUG (audit, low)` comments. They are part of a
larger seam: **36 such notes across the widget tests**, none of them in
`BACKLOG.md`. Several are already stale — the `active`-is-never-read note in
gpu, cpu and net is fixed in all three (`GpuWidget.qml:205`,
`CpuWidget.qml:256`, `NetWidget.qml:217` all check it now). Triaging all 36
against current code, discarding the stale ones and filing the live ones, is
tracked separately.

---

## Interlude: the 36 unfiled bug notes, triaged

Auditing gpu surfaced `BUG (audit ...)` comments in its test file, and a sweep
found **36 of them** across nine widget test files, none in `BACKLOG.md`. Five
ended with *"This assertion is expected to FAIL"*.

**Every single one is already fixed.** Each note sits above a test whose
assertions state the INTENDED behaviour, and the whole suite is green — so the
defects were repaired after the notes were written and the comments were left
behind. Spot-checked against the product rather than inferred from the tests
alone: `DiskWidget.human()` now labels `TiB`/`GiB` with a comment explaining
why, `DiskWidget.col()` rounds before banding so critical can no longer sit
below the warn line, and `active` is honoured in cpu, gpu, net and analog.

So the correct action was **not** to file 36 backlog items. Filing from the
comments would have imported 36 phantom defects into a backlog whose value is
that it is trusted.

The notes were rewritten as what they actually are — provenance for a regression
guard: *"FIXED, and this test pins it (audit high). The defect was: …"*. The
`tst_gen_break.qml` "AUDITED BUGS" block and the `tst_gen_habit.qml` file header
got the same treatment, both found by the new guard rather than by the original
grep.

### The real finding: a comment cannot go stale silently if it may not exist

`scripts/check_no_open_bug_notes.sh` fails on `BUG (audit`, `FIXME`, `XXX`,
`HACK` and "expected to fail" **in test comments**. A known defect belongs in
`BACKLOG.md`, where it is tracked and closed; a test states what it pins.
Past-tense provenance is explicitly allowed. It carries the same anti-vacuity
floor as its siblings — scanning zero files is a failure, not an OK — and it is
wired into both `run_all_tests.sh` and `ci.yml`.

It earned its place before it was even committed: the first run found two
annotations the original `BUG (audit` grep had missed, in `tst_gen_break.qml`
and `tst_gen_habit.qml`. Negative control: reinserting a marker fails the gate.

---

## 3. ram

Schema keys: `unit`, `showHistory`, `historyWindow`, `showDetails`,
`warnPercent`, plus the universal three.

The best-covered of the three metric widgets so far: `unit` (percent vs GiB in
the gauge centre), `showHistory` (gauge history emptied live), `historyWindow`
(limit, label and buffer cap) and `warnPercent` (the colour bands) all have real
behaviour coverage.

### Finding 3.1 — `showDetails` had property-level coverage only

Identical in shape to gpu's finding 2.1: `test_showDetails_reacts_live` set the
setting and asserted `w.showDetails === false`, and stopped there. A widget that
read the property and then ignored it would have passed.

**Fixed 2026-08-03.** The test now asserts the `ramDetailPanel` item's visibility
on and off. The gauge sub-line is the toggle's other surface, but every branch
that fills it needs live byte counts this case does not feed, so it is left to
the cases that have that data rather than pinned to `""` here. Negative control:
making `showDetails` ignore `cfg` fails the test; reverted, it passes.

### Pattern across the three metric widgets

Three audited, three found the same class of hole — a config key whose *plumbing*
is tested and whose *effect* is not:

| widget | key(s) | strongest coverage before |
|---|---|---|
| cpu | `showFrequency`, `showLoadAverage`, `showPerCore`, `showTopProcess` | schema shape only |
| gpu | `showDetails` | property only |
| ram | `showDetails` | property only |

Worth carrying into the remaining 27 as the first thing to check.

---

## 4. net

Schema keys: `unit`, `showHistory`, `historyWindow`, `showDetails`, `scaleMode`,
`fixedScaleMbps`, `interfaceName`, plus the universal three.

Strong on the hard parts: `scaleMode` + `fixedScaleMbps` are proven through
`graphScaleLabel` ("Fixed ceiling…"), `interfaceName` through the selected-vs-
aggregate counters, and `unit` / `showHistory` / `historyWindow` all have real
behaviour coverage.

### Finding 4.1 — `showDetails` was the weakest instance of the family yet

Not property-only like gpu and ram — **default-only**. The single assertion was
`compare(w.showDetails, true)` inside `test_defaults_when_settings_empty`, and no
test ever turned it off. Three `Text` rows are gated on it
(`NetWidget.qml:388/402/411`): the link/source line, the session totals, and the
drops/errors line. A widget that stopped honouring it entirely would have shipped
green.

**Fixed 2026-08-03.** `test_show_details_toggle_gates_the_detail_rows` feeds a
live rate (the rows need `rateAvailable`), asserts the totals and drops rows are
present and visible, turns the toggle off and asserts both hide, then turns it
back on. Negative control: making `showDetails` ignore `cfg` fails the test;
reverted, it passes.

### The pattern is now four for four

| widget | key(s) | strongest coverage before | grade |
|---|---|---|---|
| cpu | `showFrequency`, `showLoadAverage`, `showPerCore`, `showTopProcess` | schema shape | weakest |
| gpu | `showDetails` | property round-trip | |
| ram | `showDetails` | property round-trip | |
| net | `showDetails` | default value only | weakest |

Every metric widget shipped at least one display toggle whose *effect* nothing
asserted, and in three of the four it is the same key. Worth checking
`showDetails` first on `disk` and `sensors`.

---

## 5. disk

Schema keys: `mountPath`, `showActivity`, `warnPercent`, plus the universal three.

`warnPercent` is the best-covered key in the whole audit so far (eleven cases,
including the band-ordering and rounding-boundary regressions), and `mountPath`
covers selection and the offline-mount path.

### Finding 5.1 — `showActivity` was only ever set to `true`

The on-path was proven — `test_activity_has_non_color_direction_labels_and_real_rates`
sets it true and asserts the read/write rows render — and the off-path never was.
The whole `diskActivity` column is gated on it (`DiskWidget.qml:406`).

**Fixed 2026-08-03.** The new case asserts the column visible with the toggle on,
hidden with it off, and — the part worth having — that `ioAvailable` and
`readRate` are *unchanged* underneath: the toggle governs the display, not the
sampling. Negative control: making `showActivity` ignore `cfg` fails the test.

---

## 6. sensors

Schema keys: `gpuDevice`, `rowOrder`, `showCpu`, `showGpu`, `showRam`, `showDisk`,
`showTemps`, `showGpuPower`, `showGpuFan`, `warnCpu`, `warnGpu`, `warnRam`,
`warnDisk`, `warnCpuTemp`, `warnGpuTemp` — the largest surface of any widget so
far.

### Finding 6.1 — five of the six thresholds were never set by any test

`warnCpu`, `warnGpu`, `warnRam`, `warnDisk` and `warnGpuTemp` appeared only in a
schema key-list assertion. Only `warnCpuTemp` was ever driven. Each one feeds
`stateFor()` for its row (`SensorsWidget.qml:163-175`: warning at the value,
critical ten points above), so the widget could have ignored any of the five and
every existing case would still have passed.

**Fixed 2026-08-03** with one data-driven case over all five, asserting the full
band walk per row — Normal below the line, Warning at it, Critical ten above —
and then that the line is *genuinely the config value*: raising it to 90 returns
the same 71 reading to Normal. Negative control: pinning `warnRam` to a constant
fails the ram row.

### Finding 6.2 — the first attempt at that test silently did not run

Worth recording because the suite stayed green while it happened. The insertion
landed **inside** `test_temp_colour_thresholds`, nesting both new functions where
QtTest cannot see them — legal JavaScript, zero test functions added, suite green.
`check_live_tests.sh` did not catch it: that guard is for a `_data` provider with
no matching test, and here both halves existed, just out of reach.

The lesson is a procedural one for the rest of this audit: **after adding a test,
confirm it appears in the run log by name.** A green suite is not evidence that a
new test ran. Re-inserted at TestCase level; all five data rows now appear
individually, and the disk row failed first time on a missing availability
companion (`disk_metrics_available`), which is exactly the kind of honest failure
a test that actually runs produces.
