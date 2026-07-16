# EdgeHub — Marketing & Go-to-Market

**Live marketing site (design):** https://claude.ai/code/artifact/7fe493eb-13dc-4719-82b2-5f205bc3c660
(private artifact — share from the page menu). Source: `docs/marketing-site/index.html`
(single self-contained HTML file: landing + pricing + a demo checkout view).


_Product: **EdgeHub** — a native Linux widget dashboard for the Corsair Xeneon Edge
(and other secondary touchscreens). Working repo name: `xeneon-edge-hub`._

> **Ownership & branding.** EdgeHub is a product of **SKYPhoenix IT** — market it as
> "**EdgeHub by SKYPhoenix IT**" with the SKYPhoenix logo/wordmark. Public surfaces
> (site, trailer) lead with the generic promise ("your second screen, finally native
> on Linux") and keep exactly **one nominative compatibility line** ("compatible with
> the Corsair Xeneon Edge™ · an independent product, not affiliated with Corsair").
>
> **Trademark note.** "Corsair" and "Xeneon Edge" are trademarks of their owner.
> EdgeHub is **independent and unofficial** — never use Corsair logos, branding, or
> imply endorsement; name the hardware only *nominatively* for compatibility. The
> brand **EdgeHub** deliberately avoids the "Xeneon" mark. (This internal doc still
> names the target hardware for planning; the *public* copy does not lead with it.)

---

## 1. Positioning (one sentence)

**EdgeHub turns the Corsair Xeneon Edge into a living Linux dashboard — the
software Corsair never shipped for Linux.**

## 2. The wedge (why anyone buys)

Corsair's own software (iCUE) is **Windows-only**. Every Linux owner of a Xeneon
Edge — or any spare portrait touchscreen — has a beautiful panel and *nothing
native to put on it*. EdgeHub is that missing piece: auto-detects the display,
goes fullscreen, and runs a fast, touch-first, deeply configurable widget
dashboard that actually belongs on Linux.

High-intent, underserved niche: people who already spent ~€100+ on the hardware,
run Linux by choice, and want it to *just work*.

## 3. Taglines (pick per channel)

- **"Your Xeneon Edge. Finally native on Linux."**
- "The dashboard Corsair forgot to build for Linux."
- "A second screen that finally does something."
- "22 widgets. 22 themes. Zero Windows required."
- "Glanceable everything — CPU, calendar, focus, media — on your side screen."

## 4. Elevator pitch (100 words)

> You bought a gorgeous secondary touchscreen and Linux left it blank. EdgeHub
> fills it. It auto-detects your Corsair Xeneon Edge, snaps to fullscreen, and
> gives you a fast, native, touch-first dashboard: system gauges, a Pomodoro focus
> timer, tasks, habits, calendar, weather, now-playing media, and more — 22 widgets
> across swipeable pages. Style it with 22 themes, animated backdrops, and
> wallpapers, all from a desktop companion app with a live WYSIWYG preview. It sips
> resources (~3.5% CPU, static when idle), remembers everything, and never phones
> home. Open source at the core; a few euros for the prebuilt, auto-updating build.

## 5. Feature highlights (benefit-first)

| Feature | Why it matters |
|---|---|
| **Auto-detects the Edge (EDID)** | Plug in, it lands on the right screen fullscreen — survives hotplug & reboots. |
| **22 widgets** | CPU/GPU/RAM/Net/Disk/Sensors, Clock/Analog/Calendar/Weather/Moon, Focus/Tasks/Habit/Hydration/Break/Notes/RightNow/Quote, Media (MPRIS), Countdown, End-of-Day. |
| **Touch-first UI** | Swipe pages, tap to expand, on-device configuration — built for a 720×2560 panel. |
| **Companion Manager app** | Desktop app with a **live WYSIWYG clone** of your Edge: drag-reorder, resize, theme, upload wallpapers — no config files. |
| **22 themes, 14 accents, animated backgrounds** | Orbs, aurora, waves, starfield, mesh, bokeh, grid + frosted-glass cards and wallpapers. Make it yours. |
| **Featherweight & private** | ~3.5% CPU worst-case (0.5% reduced-motion), ~378 MB RSS steady, **no telemetry, no account, all local.** |
| **Rock-solid** | Rust core + Qt6; single-instance safe; persistent state; 95%+ automated test coverage across four layers incl. real-binary E2E. |
| **Packaged for Linux** | AUR, AppImage, Flatpak, `.pkg`/CPack. KWin/Wayland tested on real hardware. |

## 6. Audience & personas

- **"Linux daily-driver + new Corsair panel"** — searched "xeneon edge linux",
  found nothing official. Primary buyer.
- **r/unixporn ricers** — want a stunning, themeable side-screen. Sell on looks.
- **Focus/productivity crowd** — Pomodoro + tasks + habits on a dedicated glance
  screen, off the main monitor.
- **Homelab / sysadmin** — live CPU/GPU/net/disk gauges on a spare portrait panel.

## 7. Pricing (recommendation)

**Model: one-time purchase, no subscription.** Linux prosumers dislike subscriptions
for a local utility; a spare-screen dashboard isn't a SaaS. Open-core keeps goodwill
(and is honest about the MIT/Apache-2.0 license — see §9) while the paid build sells
*convenience*: prebuilt, signed, auto-updating packages + support + extras.

| Tier | Price | What you get |
|---|---|---|
| **Source** | **Free** | Full app, build from source (MIT/Apache-2.0). Community support. |
| **Personal** | **€18** _(launch €12)_ | Prebuilt signed AppImage + Flatpak + AUR-bin, one-click updates, all 22 themes, email support. Lifetime updates within the current major version. Unlimited personal machines. |
| **Supporter** | **€39** | Everything in Personal + **all future major versions**, priority support, a premium theme & wallpaper pack, early-access builds, name in credits. |

_Commercial / multi-seat deployment: contact for a site license (~€99+)._

**Plus donations (optional, no-pressure).** Alongside the paid tiers, offer a "just say
thanks" row — **Buy Me a Coffee** (one-off tips), **Patreon** (recurring, for people who
want to follow the roadmap), and **GitHub Sponsors** (right next to the open-source repo).
Goal isn't to get rich; it's to let happy users chip in for the time invested. These are
on the site under the pricing section.

**Why these numbers.** Anchor to the hardware (~€100+) and to premium one-time
desktop utilities (€10–30). €18 is an easy impulse buy for someone who just spent
€100 on the screen; €12 launch pricing drives early reviews; €39 Supporter captures
enthusiasts and funds development. Expect most revenue from Personal, most goodwill
from Free, most margin from Supporter.

## 8. Launch plan

1. **Seed the niche**: r/linux, r/unixporn (screenshots!), r/Corsair, Level1Techs,
   the Corsair user forums (as an independent project), Arch/AUR announcement.
2. **Show, don't tell**: a 20-second screen-capture loop of the live dashboard +
   the Manager's WYSIWYG editor. Looks sell this product.
3. **Hacker News / Lobsters**: "Show HN: EdgeHub — native Linux dashboard for the
   Corsair Xeneon Edge (Rust + Qt6, 95% tested)". Lead with the Linux-gap story.
4. **Product Hunt** launch with the website below.
5. **SEO**: own "xeneon edge linux", "corsair secondary screen linux", "linux
   touchscreen dashboard widgets".
6. **Free tier as funnel**: AUR/GitHub visibility → upsell the prebuilt/auto-update
   Personal build.

## 9. The one real decision to make (licensing)

The repo is currently **MIT/Apache-2.0** (see `LICENSE`, PKGBUILD). You *can* sell an
open-source app — but anyone can rebuild it for free, so you're selling convenience,
not the bits. Two viable paths:

- **Open-core (recommended):** keep the core OSS; sell prebuilt, signed,
  auto-updating packages + support + a proprietary premium theme/wallpaper pack and
  the "Supporter" perks. Maximizes reach and reputation.
- **Proprietary Pro build:** relicense a "Pro" edition (extra widgets/themes/cloud
  sync) under a commercial license while the free core stays OSS.

Decide this before charging — it changes the checkout copy ("buy the prebuilt build"
vs "buy a license key"). The website's checkout is written for the open-core framing.

---

## Assets

**Real device screenshots** (captured on the live Edge via the `XENEON_GRAB` hook,
720×2532, on-brand "midnight" theme):
- `docs/marketing-site/assets/edge-dashboard-orbs.png` — **primary hero**; soft
  "orbs" backdrop, compact widgets (clock, CPU/GPU/RAM gauges with live data,
  focus, weather, moon).
- `docs/marketing-site/assets/edge-dashboard-aurora.png` — alternate; "aurora"
  backdrop, taller focus tile.

Reproduce / vary (theme, background, widgets) with
`tests/../tmp` helper `marketing_seed.py` + the grab command in
[[runtime-e2e-testing]] style:
`env -u WAYLAND_DISPLAY XDG_CONFIG_HOME=… XDG_RUNTIME_DIR=… DISPLAY=:0
QT_QPA_PLATFORM=xcb XENEON_GRAB=out.png XENEON_GRAB_W=720 XENEON_GRAB_H=2560
build/xeneon-edge-hub --windowed` (needs the real X/XWayland display — offscreen
returns a null pixmap).

_Still to produce: a 20s demo screen-capture, a Manager (companion app) shot, and a
theme-gallery montage. The 1024² app icon already lives in `assets/`._
