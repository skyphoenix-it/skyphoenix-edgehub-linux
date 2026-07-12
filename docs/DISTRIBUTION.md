# Distributing, Packaging & Monetizing

How to let other people install this, and your options for making money.

---

## 1. What users need to build & run

**Runtime:** a Linux desktop with Qt6 (Quick, QuickControls2, Svg, DBus, Network,
VirtualKeyboard) and a working GPU/compositor. No web browser, no server.

**Build:** a C++17 toolchain, CMake ≥ 3.22, the Rust toolchain (`cargo`), and the
Qt6 dev packages. See `docs/installation/` for per-distro package lists
(`cachyos.md`, `ubuntu.md`, `generic-linux.md`).

### Do they need sudo?

**To build and run: no.** The whole thing works from a normal user build:

```sh
git clone <repo> && cd xeneon-edge-linux-hub
./scripts/build.sh release
./build/xeneon-edge-hub        # the dashboard
./build/xeneon-edge-manager    # the companion app
```

Config lives in `~/.config/xeneon-edge-hub/`. Metrics come from world-readable
`/proc` and `/sys`; media from the session D-Bus. None of that needs root.

**Sudo is needed only for two optional things:**

1. **A system-wide install** (`sudo cmake --install build`) — or install to
   `~/.local` with `-DCMAKE_INSTALL_PREFIX=~/.local` and skip sudo entirely.
2. **Auto-rotate** — the Edge's orientation sensor lives on a root-only HID node,
   so the one-time udev rule in `packaging/udev/99-xeneon-edge.rules` must be
   installed with sudo:
   ```sh
   sudo cp packaging/udev/99-xeneon-edge.rules /etc/udev/rules.d/
   sudo udevadm control --reload && sudo udevadm trigger --action=change --subsystem-match=hidraw
   ```
   Without it, everything works except auto-rotate (manual orientation modes still
   do). This is a genuine hardware-permission requirement, not app design.

So: **"clone, build, run" is clean and sudo-free.** Auto-rotate is the only thing
that asks for a one-line root command, and it degrades gracefully without it.

---

## 2. Packaging formats

Ranked by effort-vs-reach for this app:

| Format | Best for | Notes |
|---|---|---|
| **AppImage** | Widest reach, zero install | One portable file that bundles Qt. Ship the udev rule + a helper script alongside. Easiest for non-technical users. Recommended first target. |
| **AUR (PKGBUILD)** | Arch / CachyOS (your distro) | Cheap to maintain; installs the udev rule as part of the package. Great starting point since you're on CachyOS. |
| **.deb / .rpm** | Debian/Ubuntu & Fedora | `cpack` can generate these from CMake; package the udev rule under `/usr/lib/udev/rules.d`. |
| **Flatpak / Flathub** | Discoverability + auto-update + a built-in donation link | Sandboxed — you must grant `--device=all` (or specific hidraw) and `/proc`/`/sys` access, and the udev rule still has to be installed on the host. More work; do it after AppImage/AUR. |

Practical rollout: **AUR first** (you, today) → **AppImage** (everyone) →
**Flathub** (reach + donations) later.

The CMake install already places the binaries, the `.desktop` entry, and the udev
rule (`-DUDEV_RULES_DIR=/etc/udev/rules.d` for a real system path). `cpack` on top
gives you `.deb`/`.rpm`/`.tar.gz` for free.

---

## 3. Licensing (the part that decides your money options)

- **This project is MIT** (`LICENSE`) — the most permissive license. You may sell
  it, ship binaries, and build a business on it. So can everyone else (MIT lets
  others redistribute too), which is why the usual model here is **goodwill +
  donations + paid extras**, not locked-down sales.
- **Qt6 is LGPLv3** (or a paid Qt commercial license). Dynamically linking it — as
  this app does — is fine for both open-source and commercial distribution, as
  long as users can replace/relink the Qt libraries. AppImage/Flatpak that ship Qt
  as separate `.so` files satisfy this. You do **not** need a paid Qt license.
- **Rust crates** are MIT/Apache-2.0; **Phosphor icons** are MIT. The whole stack
  is commercial-friendly.
- The Edge orientation protocol was **independently reverse-engineered from your
  own device's HID reports** — no third-party (e.g. GPL) code was copied, so it
  doesn't encumber the MIT license.

> If you ever want to sell a **closed-source "Pro" edition**, keep the open core
> MIT and put the proprietary widgets/features in a separate, differently-licensed
> module. The MIT core stays free; your additions can be commercial.

---

## 4. Making money (you want to, but don't have to)

Low-friction, community-friendly options — you can stack several:

**Donations (easiest, keeps everything free & open):**
- **GitHub Sponsors** — zero fees, shows on the repo, monthly or one-off.
- **Ko-fi / Buy Me a Coffee** — one-off tips, no account needed by donors.
- **Liberapay / Open Collective** — recurring, transparent, FOSS-friendly.
- Add a `.github/FUNDING.yml` so a **Sponsor** button appears on the repo, and a
  "Support this project" section in the README with the links.

**Paid, while staying open:**
- **Flathub + donation link** — reach + a prominent donate button.
- **Sell convenience, not the code:** paid AppImage/installer on **itch.io** or
  **Gumroad** ("pay what you want", suggested price), pre-built & signed, so people
  who don't want to compile just buy it. The source stays free.
- **Paid support / setup / custom widgets** — consulting or commissioned widgets.
- **A "Pro" widget pack** (proprietary module on the MIT core) — advanced/branded
  widgets, integrations (Home Assistant, stocks, calendars), sold once or as a
  small subscription.

**Recommended starting point:** MIT core stays free; add **GitHub Sponsors +
Ko-fi** now (5 minutes), ship an **AUR package** and an **AppImage** so people can
actually use it, and put a friendly "if this is useful, buy me a coffee" line in
the README. If it gets traction, add a **Pro widget pack** for real revenue. This
keeps goodwill high (which drives adoption) while leaving the door open to income.

**Don't:** relicense away from MIT retroactively (you can't, for existing
contributions, without every contributor's consent), or hide the whole thing
behind a paywall (kills the community that makes it valuable).

---

## 5. Checklist to go public

- [ ] Fill in the real repo URL/badges in `README.md` (currently `your-org`).
- [ ] Confirm per-distro build docs in `docs/installation/` are current.
- [ ] Add `.github/FUNDING.yml` + a Support section in the README.
- [ ] Write an AUR `PKGBUILD` (installs binaries + udev rule).
- [ ] Produce an AppImage (bundle Qt; ship the udev rule + install helper).
- [ ] Tag a release; attach the AppImage + `.deb`/`.rpm` from `cpack`.
- [ ] (Later) Flathub submission.

See also: [authoring widgets](widgets/authoring.md) · [installation](installation/).
