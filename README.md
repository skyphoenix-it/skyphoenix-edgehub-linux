# EdgeHub

**Pick the screen for what you're doing, and it's built for you.**

EdgeHub by [SKYPhoenix IT](https://skyphoenix-it.com) turns a Corsair Xeneon Edge — or any secondary/portrait touchscreen — into a native Linux widget dashboard. No browser, no Electron, no web server, no account, no telemetry.

[![CI](https://github.com/skyphoenix-it/XeneonEdge_Linux/actions/workflows/ci.yml/badge.svg)](https://github.com/skyphoenix-it/XeneonEdge_Linux/actions/workflows/ci.yml)
[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg)](#license)
[![Release: v1.0.0-alpha.1](https://img.shields.io/badge/release-v1.0.0--alpha.1-orange.svg)](https://github.com/skyphoenix-it/XeneonEdge_Linux/releases/tag/v1.0.0-alpha.1)

![EdgeHub running on the Corsair Xeneon Edge with the animated orbs background](docs/marketing-site/assets/edge-dashboard-orbs.png)

> **This is an alpha.** It runs, it's tested on real hardware, and it's built from a shipping-quality foundation — but the feature set is still fluid, the release is unsigned, and widget sizing is being reworked. See [Alpha status](#alpha-status) before you rely on it.

---

## What it is

The Corsair Xeneon Edge is a 2560×720 secondary touchscreen that works in either orientation. EdgeHub gives it — and other secondary or portrait displays — a purpose-built home screen: swipeable pages of live widgets you arrange by touch, right on the device.

**Who it's for:** anyone with a second screen they don't want to waste. Developers watching a build. Homelab owners watching a rack. People who want a calm timer and the weather instead of another browser window.

- **Native and light.** A Rust core handles metrics and configuration; Qt 6/QML draws the UI. No Chromium, no bundled runtime.
- **Designed for touch.** Large targets, swipe between pages, in-widget controls, on-device settings. You never need a keyboard to use it.
- **It finds the right screen.** Display detection puts EdgeHub on your Edge (or a display you choose), and a real HID orientation sensor follows the panel when you flip it.
- **Design it from your desk.** The companion **EdgeHub Manager** is a live clone of your Edge — drag, reorder, resize, and restyle from your main monitor.

---

## 15 ready-made screens

You don't start from a blank grid. Each preset is a designed layout — a small, purposeful set of widgets, with a fitting background and motion character.

| Screen | For |
|---|---|
| **Calm Focus** | Deep work, quietly. A big timer, your one thing, and a place to dump distractions. |
| **Home & Ambient** | A desk companion — time, weather, what's playing, and tonight's moon. |
| **Remote Work** | The time, your calendar, today's tasks, and how much workday is left. |
| **Developer** | Your build and your box, side by side — CI status, a number you watch, machine health. |
| **Homelab Ops** | Service uptime and container health beside CPU, memory, network and disk. |
| **Gaming Cockpit** | Rig telemetry beside your game — GPU/CPU temps, memory, network. |
| **Trading Desk** | Your time and the market's, two numbers that matter, and what's next. |
| **Health & Routine** | Gentle nudges toward a good day — water, breaks, and a daily streak. |
| **Creator / Media** | Now-playing front and centre, a focus timer, and a spark of inspiration. |
| **System Monitor** | The classic — CPU, GPU, memory, network, disk, sensors. |
| **Minimalist** | Almost nothing. A clock, the weather, and the moon. |
| **Analyst / Data** | Two headline numbers, a monitoring feed, the time and your tasks. |
| **Student / Study** | A focus timer, your tasks, a countdown to the exam, and a streak. |
| **Productivity** | Focus, tasks, a habit streak and your day's progress, with system stats a swipe away. |
| **Enterprise / Locked** | A clean, managed baseline — time, agenda, workday, and one approved team number. |

Applying a preset keeps *your* theme and accent — it changes the screen, not your taste.

The data-connected presets (Developer, Homelab Ops, Trading Desk, Analyst, Enterprise) ship their data tiles **labelled but deliberately unconnected** — "CI status → Add a URL in settings". A preset never guesses an endpoint, so a fresh install never polls a stranger's host.

*Defined in [`ui/qml/PresetCatalog.qml`](ui/qml/PresetCatalog.qml).*

---

## 24 widgets

| Category | Widgets |
|----------|---------|
| **System** (6) | CPU load & temp, GPU (AMD Radeon utilization & temp), Memory, Network throughput, Disk usage, combined Sensors |
| **Data** (2) | **HTTP / JSON** — poll any endpoint, pull a value out by path, show it as a number, gauge or list · **KPI** — one number that matters, from a URL *or a local file*, with colour-coded thresholds |
| **Time** (3) | Clock (**real IANA time zones — daylight saving included**), Analog Clock, Moon Phase |
| **Focus** (7) | Focus Timer (Pomodoro), Tasks, Right Now, Quick Note, Habit Streak, Hydration, Break Reminder |
| **Media** (1) | Now Playing (MPRIS — Spotify, browsers, any player on the machine) |
| **Info** (5) | Calendar (subscribe via ICS URL), Weather (Open-Meteo), Countdown, End of Day, Daily Quote |

System metrics come from the Rust core and the kernel. Focus, task, note, habit and hydration widgets persist your data locally.

**Real time zones, properly.** The clock is backed by a `QTimeZone` bridge, so it follows actual IANA rules — every zone your OS `tzdata` knows (~600), daylight saving included, and correct through a `tzdata` update with no code change. QML has no `Intl`, and `Date.toLocaleString(…, { timeZone })` silently returns host-local time — which is exactly the kind of quiet wrongness a clock cannot afford.

*Defined in [`ui/qml/WidgetCatalog.qml`](ui/qml/WidgetCatalog.qml).*

---

## Connect your own data

The **HTTP/JSON** and **KPI** widgets point at *your* endpoint: a CI status, a queue depth, a P&L number, a Prometheus query, a file on disk. No integration, no account, no vendor. KPI's local-file source works with no network at all.

**Credentials are references, not secrets.** Write `${env:MY_TOKEN}` or `file:/run/secrets/token`, and the value is read at request time and **never written to your config**. A token typed in directly still works — the app tells you it's in plain text so you can migrate.

| Form | Meaning |
|---|---|
| `${env:VAR}` | Read environment variable `VAR` at request time |
| `file:/path/to/token` | Read the file's contents at request time |
| anything else | A plaintext literal — still honoured, and flagged in the UI |

*Implemented in [`core/src/secrets.rs`](core/src/secrets.rs).*

---

## Privacy, enforced rather than asserted

Most apps promise they don't phone home. EdgeHub's design makes the promise checkable.

- **One audited egress gate.** Every outbound request goes through [`NetHub.request()`](ui/qml/widgets/NetHub.qml) — the only place in the QML tree that may construct a network call. It owns a **global offline kill switch**, a **per-host allowlist**, and **per-host counters** for what was actually sent.
- **A lint enforces it.** [`scripts/check_no_raw_xhr.sh`](scripts/check_no_raw_xhr.sh) fails if any file outside the gate constructs its own request, and also fails if the gate stops being the one construction site. It runs as a suite in [`scripts/run_all_tests.sh`](scripts/run_all_tests.sh). There is no exemption list — an exception there would be a hole in the claim, not a lint detail.
- **Unknown schemes are refused, not guessed.** The gate recognises a fixed set of local forms (`file:`, `qrc:`, bare paths). Anything else is egress. An earlier shape treated every unknown scheme as local, so a `webcal://` calendar URL skipped both the kill switch and the allowlist — that class of bug is now structurally impossible.
- **The Rust core has no network stack at all.** "No outbound" is true there by construction, not by policy.
- **Your config stays yours.** Plain TOML at `~/.config/xeneon-edge-hub/config.toml`, written atomically and **owner-only (`0600`) at creation** — not chmod'd afterwards, so a credential is never briefly world-readable.
- **No telemetry, no account, no cloud.** EdgeHub touches the network only for widgets you explicitly configure — Weather, a Calendar feed, or a data widget you pointed somewhere. All of it through the same gate.

### Performance

| | |
|---|---|
| CPU, worst case (every animation running) | ~3.5% |
| CPU, reduced motion | ~0.5% |
| RSS, steady state | ~378 MB |

---

## Make it yours

- **22 themes** — dark, light, OLED, high-contrast, and Nord, Dracula, Gruvbox, Catppuccin, Tokyo Night, Solarized, Synthwave, Matrix and more.
- **22 accent colors** — 14 named tones, plus the 8 published **Okabe–Ito** colors, chosen to stay mutually distinguishable under protanopia, deuteranopia and tritanopia.
- **7 animated backgrounds** — orbs, waves, starfield, mesh gradient, aurora, bokeh, grid — plus static wallpapers, settable globally or per page.
- **Glass, glow, and a reduced-motion mode.** One shared design system keeps every widget consistent.
- **Edit mode** to add, remove, move and resize tiles across multiple pages, with schema-driven per-widget configuration.
- **First-run wizard**, on-device **Settings**, and a **Diagnostics** screen.

![EdgeHub with the aurora background](docs/marketing-site/assets/edge-dashboard-aurora.png)

*These screenshots predate the preset library and the data widgets — they show the dashboard and theming, not the presets.*

### EdgeHub Manager

A companion desktop app (`xeneon-edge-manager`) that mirrors your Edge in real time over a control socket, with Dark / Light / Default chrome:

| Tab | What it does |
|---|---|
| **Layout** | Drag, reorder and resize tiles on a live clone of your Edge |
| **Appearance** | Themes, accents, backgrounds, glass/glow |
| **Images** | Wallpapers and per-widget imagery |
| **Display** | Pick and orient the target screen |
| **About** | Version and project info |

---

## Install

The current release is **[v1.0.0-alpha.2](https://github.com/skyphoenix-it/XeneonEdge_Linux/releases/tag/v1.0.0-alpha.2)** — the first **signed** release.

### Portable tarball (any distro)

Download `xeneon-edge-hub_1.0.0-alpha.2_x86_64.tar.gz`, `SHA256SUMS` and `SHA256SUMS.asc` from the [release page](https://github.com/skyphoenix-it/XeneonEdge_Linux/releases/tag/v1.0.0-alpha.2), then:

```sh
gpg --verify SHA256SUMS.asc SHA256SUMS   # key import: see "Verifying your download"
sha256sum -c SHA256SUMS
tar -xf xeneon-edge-hub_1.0.0-alpha.2_x86_64.tar.gz
```

An AUR package is in preparation. (`v1.0.0-alpha.1` remains available but unsigned — it predates the release key, which is not retroactively fixable.)

### Verifying your download

Releases from `v1.0.0-alpha.2` onward ship `SHA256SUMS` alongside a detached signature `SHA256SUMS.asc`, made with the EdgeHub release key. (`v1.0.0-alpha.1` predates the key and is checksum-only — it has no `.asc`.)

**1. Import the key.** It is not on a keyserver yet, so `gpg --recv-keys` will not find it. Use either route:

```sh
curl -sL https://github.com/SimonKreitmayer.gpg | gpg --import   # from GitHub
gpg --import packaging/edgehub-signing.pub                        # from a clone
```

**2. Verify the signature, then the files:**

```sh
gpg --verify SHA256SUMS.asc SHA256SUMS   # is the checksum list authentic?
sha256sum -c SHA256SUMS                  # do the files match the list?
```

`gpg --verify` must say **Good signature** for this fingerprint:

```
SKYPhoenix IT <simon.kreitmayer@skyphoenix-it.com>
2F0C AD36 DC1D 46F3 347B  7EF2 93CD C77E ACF9 8990
```

**Check the fingerprint, not just the words "Good signature."** Any key can produce a good signature over anything — including one an attacker made and shipped next to a tampered download. The signature is only worth what the fingerprint is, so compare it against the line above (published here, in [`packaging/edgehub-signing.pub`](packaging/edgehub-signing.pub), and on [GitHub](https://github.com/SimonKreitmayer.gpg)).

gpg will also warn `This key is not certified with a trusted signature`. That is expected and not a failure: it means you haven't personally certified the key. Trust here rests on the fingerprint matching, not on the web of trust.

Policy, scope and key rotation: [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md#release-signing).

### Everything else

Build from source (below). AppImage, Flatpak, `.deb` and `.rpm` recipes are authored in this repo but are not yet published, verified artifacts — see [`packaging/README.md`](packaging/README.md) for the honest status of each format. Fedora and Ubuntu packages are planned for v1.1.

---

## Build from source

### Prerequisites

- **Rust** 1.75+ (stable)
- **C++17 compiler** (GCC 12+ or Clang 16+)
- **CMake** 3.22+
- **Qt 6.5+** with development headers (QtQuick, QtWayland, QtDBus, QtSvg)

**Arch / CachyOS**

```sh
sudo pacman -S rust cmake gcc qt6-base qt6-declarative qt6-wayland qt6-tools
```

**Ubuntu 24.04 LTS** — note that Ubuntu's apt Qt is 6.4.2; the project needs Qt ≥ 6.5, so install a newer Qt if apt's is too old.

```sh
sudo apt install cargo cmake g++ qt6-base-dev qt6-declarative-dev \
  qt6-wayland-dev qt6-tools-dev libglib2.0-dev
```

### Build & run

```sh
git clone https://github.com/skyphoenix-it/XeneonEdge_Linux.git
cd XeneonEdge_Linux
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

./build/app/xeneon-edge-hub          # the on-device hub
./build/manager/xeneon-edge-manager  # the companion Manager
```

`--reset` loads fresh defaults; `--reset-wizard` re-triggers the first-run wizard.

### Test

```sh
cd core && cargo test        # Rust core
./scripts/run_ui_tests.sh    # QML GUI suite (offscreen, no cmake needed)
./scripts/run_all_tests.sh   # everything: Rust + QML + ctest + behavior matrix + lints
```

---

## Architecture

```
Rust core (config · EDID · metrics · FFI)  ──C ABI──▶  Qt 6 / QML (hub + Manager)
                                                         │
                    local TOML config ◀── control-socket IPC · single-instance
```

- **Rust core** owns configuration, EDID display identity, and system metrics, and exposes a stable, hand-written C ABI. It has no network stack.
- **Qt 6/QML** renders both the hub and the Manager on top of that core. Widgets are declared once in a registry and reused by the grid, the expanded overlay, and the add-widget picker.
- The hub and Manager talk over a **control socket** (`QLocalServer`), which is how the Manager pushes a live layout to a running hub. The app is **single-instance**.

Further reading: [architecture overview](docs/architecture/overview.md) · [ADR 0001 — application stack](docs/adr/0001-application-stack.md) · [ADR 0002 — widget runtime](docs/adr/0002-widget-runtime.md).

---

## Quality

Verified on the **actual Corsair Xeneon Edge**, not just in CI:

| Layer | Result |
|---|---|
| **Real hardware** ([`tests/hardware/`](tests/hardware/README.md)) | **212/212 checks in 22.2 min** on a real Edge — every widget type added, rendered, resized and removed; every theme and background; synthetic touch via `/dev/uinput`; IPC latency p50 0.02 ms; and a 20-minute soak of **2,156 mixed operations** with no crash |
| **Rust** | **116 tests**, **97.4%** line coverage (`cargo llvm-cov`) |
| **C++** | **15/15** ctest (QtTest), ~97% filtered line coverage |
| **QML** | GUI suite against a real `DashboardStore`, plus a behavior matrix at **100%** |
| **Lints** | Egress lint (no raw request outside the gate) and a widget-icon lint |
| **Runtime E2E** | Drives the real hub binary headless and asserts what it persists to `config.toml` |

CI runs Rust format, clippy, tests, `cargo-audit`, a build, docs/link checking, the QML suite, C++ tests, and a **merged Rust + C++ coverage gate at ≥95%** — see [`.github/workflows/ci.yml`](.github/workflows/ci.yml). The hardware suite needs a physical Edge, so it runs locally rather than in CI. Full plan: [`docs/DEV_AND_TEST_PLAN.md`](docs/DEV_AND_TEST_PLAN.md).

The hardware suite asserts its widget list against `WidgetCatalog.qml`, so a new widget cannot go silently unexercised — a drift check added after the list had quietly omitted two widgets while still reporting green.

---

## Alpha status

What works is tested. What isn't done yet:

- **Widget sizing is not final.** Widgets have two layouts (tile and full-screen overlay); a tall tile stretches the compact layout rather than using the room. A fixed, per-widget-optimized size system is the v1.1 headline. The foundation is in this build.
- **This alpha release is unsigned.** Verify the checksum. The release key now exists and the signing flow is in place ([`scripts/release.sh`](scripts/release.sh)), so the beta is the first signed release — but nothing signs `v1.0.0-alpha.1` after the fact.
- **Packaging is incomplete.** Only an Arch package is published. AppImage / Flatpak / `.deb` / `.rpm` are authored but unverified; Fedora and Ubuntu come in v1.1.
- **Weather and Calendar reach the network** for the feeds you configure — as designed, through the same audited gate as everything else.
- **The Manager's display/autostart settings** write config directly; a narrow two-writer window with a running hub remains (tracked).
- **Physical rotation** is wired and debounced from the HID sensor, but only a person can turn a panel — so it's verified by hand, not by the suite.
- **GPU metrics are AMD Radeon only.**

---

## Roadmap

The foundations — 24 widgets, the Manager, the theme system, the test suite, and live CI — are done. v1.0 adds the preset library and generic primitive widgets (both shipped in this alpha), a calm/accessibility foundation, wellness widgets, and trust & control work, on an **alpha → beta → RC → GA** train. GA is the tagged 1.0 with signed artifacts and published packages.

Beyond 1.0: segment integration packs (OBS, MangoHud, Prometheus, smart home, market data), a WASM widget SDK, and internationalization.

Full plan: **[ROADMAP.md](ROADMAP.md)** · changes: **[CHANGELOG.md](CHANGELOG.md)** · overview: [`docs/marketing-site/index.html`](docs/marketing-site/index.html).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). Bug reports from the alpha are especially welcome — please say what broke and on what hardware.

## Security

See [SECURITY.md](SECURITY.md) for the security policy and how to report a vulnerability.

## License

Dual-licensed under either of:

- **MIT License** ([LICENSE-MIT](LICENSE-MIT) · <http://opensource.org/licenses/MIT>)
- **Apache License 2.0** ([LICENSE-APACHE](LICENSE-APACHE) · <http://www.apache.org/licenses/LICENSE-2.0>)

at your option.

**Qt note:** EdgeHub links against Qt 6 (LGPLv3). Dynamic linking against system Qt satisfies the LGPL; static linking carries the usual re-linking obligations.

**Bundled fonts:** the accessibility font options bundle [Atkinson Hyperlegible](https://github.com/googlefonts/atkinson-hyperlegible) (© Braille Institute of America) and [Lexend](https://github.com/googlefonts/lexend) (© The Lexend Project Authors), both unmodified and licensed under the SIL Open Font License 1.1. The OFL texts ship alongside the fonts in [`assets/fonts/`](assets/fonts/) (`LICENSE-OFL-AtkinsonHyperlegible.txt`, `LICENSE-OFL-Lexend.txt`).

App-id: `com.skyphoenix_it.XeneonEdgeHub` · Companion: `com.skyphoenix_it.XeneonEdgeManager`

---

## Not affiliated with Corsair

EdgeHub is an independent product of SKYPhoenix IT. It is **not affiliated with, sponsored by, or endorsed by Corsair.** "Corsair" and "Xeneon Edge" are used only to describe hardware compatibility.
