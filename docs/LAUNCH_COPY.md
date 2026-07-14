# EdgeHub — Launch copy (Product Hunt + Show HN)

Two audiences, opposite registers. Product Hunt wants the story and the payoff;
Hacker News wants the engineering and the honest caveats — no hype, no emoji.
Don't cross-post the same text. Fill the `<...>` links before posting.

> **Branding for all posts:** it's **EdgeHub by SKYPhoenix IT**. Unlike the website
> and trailer (which lead generically with "your second screen"), launch posts *do*
> need to name the hardware nominatively — a Show HN or r/unixporn post makes no sense
> without saying which panel it's for — so keep "Corsair Xeneon Edge" as a
> *compatibility* mention plus the "independent, not affiliated with Corsair" line.
> Never use Corsair logos/branding or imply endorsement. Add "by SKYPhoenix IT" to the
> maker comment / details comment.

---

## PRODUCT HUNT

### Name
**EdgeHub**

### Tagline (≤60 chars — pick one, A/B the rest)
1. Turn your Xeneon Edge into a live Linux dashboard _(49)_
2. The native Linux dashboard Corsair never shipped _(48)_
3. Widgets for your second screen — finally on Linux _(49)_

### Topics
Linux · Open Source · Developer Tools · Productivity · Desktop

### Description (≤260 chars)
> Corsair's Xeneon Edge is a gorgeous touchscreen — and blank on Linux, because
> iCUE is Windows-only. EdgeHub fills it: a fast, touch-first widget dashboard —
> 22 widgets, 22 themes, drag-and-drop styling from a desktop companion.
> Rust + Qt6. No telemetry. Open source.

### Maker's first comment
> 👋 Hey Product Hunt — maker here.
>
> I bought a Corsair Xeneon Edge (a 14.5", ultra-tall 2560×720 touchscreen that
> sits next to your monitor) and then booted Linux… to a blank second screen.
> Corsair's software is Windows-only, so there was nothing native to actually
> *put on it*. So I built the thing I wanted.
>
> **EdgeHub** auto-detects the panel, snaps fullscreen, and turns it into a
> living dashboard you drive by touch:
>
> • **22 widgets** — CPU/GPU/RAM/net/disk gauges, clock & calendar, weather &
>   moon, a Pomodoro focus timer, tasks, habits, hydration, now-playing media,
>   countdowns and more, across swipeable pages.
> • **Style it without config files** — a desktop **Manager** app shows a live
>   WYSIWYG clone of your Edge. Drag to reorder, resize, retheme, drop in
>   wallpapers; it pushes to the device instantly.
> • **22 themes + animated backdrops** — Nord, Dracula, Gruvbox, Catppuccin,
>   Synthwave… over frosted glass and aurora/waves/starfield motion.
> • **Featherweight & private** — ~3.5% CPU worst-case, near-zero idle, no
>   telemetry, no account. Everything stays on your machine.
>
> Under the hood it's a **Rust** core with a **Qt6** UI, and it ships with 95%+
> automated test coverage — including a suite that drives the real binary
> end-to-end. Open source (MIT/Apache-2.0); there's also a prebuilt,
> auto-updating build if you'd rather not compile.
>
> It works with the Xeneon Edge today, plus other portrait secondary
> touchscreens. I'd love to know **which widget you'd want next** — and if you're
> on Linux with any spare touchscreen, give it a shot and tell me what breaks. 🙏
>
> _(EdgeHub is an independent project, not affiliated with Corsair.)_

### Gallery captions
1. **Blank no more** — your Xeneon Edge, fullscreen, native, glanceable.
2. **22 widgets, your pages** — system, time, focus, media. Swipe between them.
3. **Style it live** — the companion Manager mirrors your device in real time.
4. **22 themes** — from Nord calm to Synthwave neon, backdrops and all.
5. **Light on the machine** — ~3.5% CPU, no telemetry, config stays local.

---

## SHOW HN

### Title (≤80 chars — no emoji, no hype)
- `Show HN: EdgeHub – a native Linux dashboard for the Corsair Xeneon Edge`
- alt: `Show HN: Native Linux dashboard for the Corsair Xeneon Edge touchscreen`

Submit the **site or repo** as the URL, then post this as the first comment:

### First comment
> Hi HN. I have a Corsair Xeneon Edge — a 14.5", 2560×720 secondary touchscreen
> that sits beside your main monitor. Corsair's software (iCUE) is Windows-only,
> so on Linux it's just a blank extra display. EdgeHub is what I built to make it
> useful: it detects the panel, goes fullscreen on it, and runs a touch-first
> widget dashboard.
>
> How it's put together, in case it's interesting:
>
> - Core is **Rust** (metrics collection, config/persistence, and the FFI
>   boundary); UI is **Qt6/QML**. Metrics run on a worker thread and MPRIS/media
>   is async D-Bus, so neither blocks the GUI thread.
> - Display identity is an **EDID-hash + connector match**, not a display index,
>   so it lands on the right screen across hotplug and reboots and migrates the
>   window if you replug it.
> - **Wayland and X11** (developed on KWin/Wayland). All state is local TOML;
>   no account, no telemetry, no network calls unless a widget needs one (e.g.
>   weather).
> - A companion desktop **Manager** app mirrors the running device over a local
>   socket (newline-delimited JSON) and edits push live — so you configure by
>   drag-and-drop, not by hand-editing files. Both apps share the same QML store.
> - ~3.5% CPU worst-case with every animation on (~0.5% reduced-motion),
>   ~378 MB RSS steady.
> - ~95% automated coverage across four layers: Rust unit tests, a QML
>   behavior-matrix gate, a C++ QtTest harness, and an end-to-end suite that
>   launches the real binary headless (offscreen QPA) and asserts on the state it
>   persists to config.toml.
>
> Honest caveats:
> - Only really tested against the Xeneon Edge and generic portrait secondary
>   displays; other panels should work via EDID but I can't promise it.
> - Widget metrics are limited to what the Rust layer exposes today
>   (cpu/gpu/ram/aggregate-net/root-disk) — no per-interface or arbitrary mounts
>   yet.
> - Wayland makes some things (screenshots, global input) compositor-specific;
>   verified on KWin, less so elsewhere.
> - It's a solo project.
>
> Licensing: the source is **MIT/Apache-2.0** on GitHub — build it yourself for
> free. I also sell a prebuilt, signed, auto-updating package for a few euros for
> people who don't want to compile; happy to hear whether that split makes sense
> to you.
>
> I'd especially like feedback on the display-detection approach and the
> Rust↔QML split, and on which widgets are actually worth having on a glance
> screen. It is an independent project, not affiliated with Corsair.
>
> Repo: `<github-url>` · Demo/site: `<site-url>`

### Prepared replies (HN tends to ask these)
- **"Why not just Rainmeter/Conky/a web page in kiosk mode?"** Those work, but
  none handle a touch-first portrait panel, EDID auto-placement, and live
  drag-and-drop config as one native thing. EdgeHub is that integrated piece;
  the widgets are also genuinely touch-sized, not mouse controls shrunk down.
- **"You're selling MIT-licensed software?"** The source is free to build; the
  paid tier is convenience — prebuilt, signed, auto-updating packages plus
  support. No feature is paywalled out of the source today. If I ever add a
  proprietary Pro build, the core stays open.
- **"Corsair trademark?"** I use "Xeneon Edge" only to describe compatibility,
  with no Corsair branding and a clear unaffiliated notice. Open to correction.
- **"Does it need the daemon/root?"** No root. It talks to standard Linux
  interfaces; `/dev/uinput` touch and sensor access use existing device
  permissions.

---

## REDDIT

Two subs, two registers. r/unixporn is **image-first** — the screenshot carries
the post, the title follows the `[environment]` convention, and details/links go
in a comment; keep any selling almost invisible. r/linux wants a **plain,
open-source-forward** announcement from a disclosed developer and reacts badly to
marketing tone or a paywall lede. Both **require an actual screenshot** — grab one
from the real device (`XENEON_GRAB` hook) before posting. Fill `<links>`.

### r/unixporn

**Title** (must use the `[DE/WM]` bracket format; pick one):
- `[KDE Plasma] I turned my Corsair Xeneon Edge into a live Linux dashboard`
- `[KWin/Wayland] Xeneon Edge as a widget dashboard (my project, EdgeHub)`

**Top "details" comment** (the r/unixporn ritual — post it yourself right away):
> Thanks! Details:
>
> - **OS:** CachyOS (Arch)
> - **Compositor:** KWin / Wayland
> - **Display:** Corsair Xeneon Edge — a 2560×720 portrait secondary touchscreen
> - **App:** EdgeHub — my own project, native **Rust + Qt6** (not a web page in a
>   kiosk). It auto-detects the panel over EDID and goes fullscreen on it.
> - **Theme shown:** Midnight (one of 22 built in) with the aurora backdrop
> - **Widgets on screen:** clock, CPU/RAM ring gauges, focus timer, now-playing
> - **Config:** all drag-and-drop from a companion desktop app — no dotfiles to
>   share this time, it's a GUI
> - **Source (MIT/Apache-2.0):** `<github-url>`
>
> Happy to answer anything. Works with other portrait secondary touchscreens too,
> not just the Edge. (Independent project — not affiliated with Corsair.)

**Note:** don't put price/"buy" in the r/unixporn post or top comment — link the
repo, mention it's open source, and let people find the rest. Overt selling gets
downvoted there.

### r/linux

**Title** (plain, descriptive — no hype):
`EdgeHub: a native Linux dashboard for the Corsair Xeneon Edge (open source, Rust + Qt6)`

**Body:**
> _Disclosure: I'm the developer._
>
> The Corsair Xeneon Edge is a 14.5", 2560×720 touchscreen meant to sit next to
> your monitor — but Corsair's software (iCUE) is Windows-only, so on Linux it's
> just a blank second display. I got tired of that and wrote **EdgeHub**.
>
> It detects the panel by its EDID, goes fullscreen on it, and runs a touch-first
> widget dashboard: 22 widgets (system gauges, clock/calendar, weather, a focus
> timer, tasks, habits, media, and more) across swipeable pages. A companion
> desktop app mirrors the device live over a local socket, so you configure it by
> drag-and-drop instead of editing files.
>
> Technical notes for this crowd:
> - **Rust** core (metrics/config/FFI) + **Qt6/QML** UI; metrics on a worker
>   thread, media over async D-Bus.
> - **Wayland and X11** (developed on KWin). Config is local TOML — no account,
>   no telemetry.
> - ~3.5% CPU worst-case, ~378 MB RSS; ~95% automated coverage including an
>   end-to-end suite that drives the real binary.
> - Packaged for AUR, AppImage and Flatpak.
>
> It's **open source (MIT/Apache-2.0)** — build it yourself: `<github-url>`.
> There's also a prebuilt, auto-updating package for a few euros if you'd rather
> not compile, but nothing is paywalled out of the source.
>
> Feedback very welcome — especially on the display-detection and on which
> widgets are actually worth having on a glance screen. It works with other
> portrait secondary touchscreens too. (Independent project, not affiliated with
> Corsair.)

**Etiquette:** post from your own account as the dev, reply to comments, and read
r/linux's self-promotion rules first (they limit frequency). Good adjacent subs to
cross-post (not simultaneously): **r/Corsair**, **r/linuxhardware**, **r/kde**,
**r/archlinux** (as a project share). Lead every one of them with open source, not
price.

