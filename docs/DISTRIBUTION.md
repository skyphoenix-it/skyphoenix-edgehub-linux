# Distributing, Packaging & Monetizing

How to let other people install this, and your options for making money.

---

## 1. What users need to build & run

**Runtime:** a Linux desktop with **Qt6 ≥ 6.5** (Quick, QuickControls2, Svg, DBus,
Network, VirtualKeyboard) and a working GPU/compositor. No web browser, no server.
The ≥ 6.5 floor is real — the widgets use `QtQuick.Effects`, which does not exist
before it.

**Build:** a C++17 toolchain, CMake ≥ 3.22, the Rust toolchain (`cargo`), and the
Qt6 dev packages. See `docs/installation/` for per-distro package lists
(`cachyos.md`, `ubuntu.md`, `generic-linux.md`), and
`.github/workflows/distro.yml` for the exact, CI-executed Fedora/Ubuntu lists.

### Distro support (workflow targets, not current-candidate proof)

`.github/workflows/distro.yml` is designed to build against each distro's **own**
Qt packages, install the package into a clean container, and launch it offscreen.
The workflow must pass for the exact release candidate before any row becomes a
public support claim. At this audit point that candidate run is still required:

| Distro | Distro's Qt | Status |
|---|---|---|
| **Fedora 43** | 6.10.3 | RPM workflow exists; exact-candidate result pending |
| **Ubuntu 26.04 LTS** | 6.10.2 | DEB workflow exists; exact-candidate result pending |
| **Arch / CachyOS** | rolling | Local staged lifecycle tested; AUR publication/current package not verified |
| **Ubuntu 24.04 LTS** | 6.4.2 | Native distro Qt is below the 6.5 floor; no native support claim |

Both Fedora 43 and Ubuntu 26.04 now ship Qt ≥ 6.5 themselves, so building from
source on either needs nothing beyond the distro's own packages. (`ci.yml` still
installs Qt 6.7 via `jurplel/install-qt-action` because its jobs run on Ubuntu
24.04, whose apt Qt is 6.4.2.)

### AppImage

Built by `packaging/appimage/build-appimage.sh` on **Ubuntu 24.04 + upstream Qt
6.7.3** (aqtinstall / `install-qt-action`), not 24.04's own Qt 6.4.2. That pairing
is deliberate: an AppImage's glibc floor is its build host's, so the oldest
practical distro gives the widest reach, while the bundled Qt still has to be
≥ 6.5 for `QtQuick.Effects`. ~46 MB, bundles 41 Qt libraries.

**What it does not bundle, by design:** `libGL`/`libGLX`/`libOpenGL`/`libEGL` and
`libfontconfig` + fonts. `linuxdeploy` excludes the graphics stack on purpose — a
bundled `libGL` breaks on a host with a different (e.g. NVIDIA) driver, so GL must
come from the host. Every normal desktop already has these; a bare container does
not, which is why `appimage-smoke` installs exactly that set (and nothing from Qt)
before running.

The AppImage workflow checks a bare `ubuntu:24.04` container with no Qt or Rust,
an offscreen launch, and all imported QML modules. That check must be rerun for
the exact candidate; it does not exercise a published zsync update.

The AppImage cannot install the auto-rotate udev rule (no package manager hooks) —
users install `packaging/udev/99-xeneon-edge.rules` by hand. Everything else works.

#### The two traps this recipe encodes

Both were hit for real while getting it to build, and both fail *silently*:

1. **No `--executable`** → `linuxdeploy` scans nothing, the Qt plugin reports
   `Found Qt modules:` (empty), and you get a ~29 MB "AppImage" containing **no Qt
   and no QML at all** — which still exits 0 and looks like a successful build.
2. **Qt not on `LD_LIBRARY_PATH`** → same silent-empty outcome (or
   `Could not find dependency: libQt6DBus.so.6`), because a Qt outside the ldconfig
   cache (`/opt/Qt/...`) is invisible to dependency resolution.

`QML_SOURCES_PATHS` is equally load-bearing: the QML is compiled into the binaries
via qrc, so `qmlimportscanner` has no `.qml` files to read and must be pointed at
the source tree — otherwise the lazily-imported modules are dropped and the app
**still starts cleanly**, then fails when a widget loads.

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
| **AppImage** | Portable candidate | Recipe exists; target-host smoke and published zsync round trip are release gates |
| **AUR (PKGBUILD)** | Arch / CachyOS | Recipe exists; do not infer AUR publication or freshness from the file |
| **.deb / .rpm** | Ubuntu 26.04+ & Fedora | CPack recipes exist; exact-candidate clean install/launch/uninstall jobs are required |
| **Flatpak / Flathub** | Sandboxed distribution | Recipe exists; no Flathub publication or support claim |

No rollout order is committed. Publish only formats whose exact artifact lifecycle
has passed and whose maintenance/update path is documented.

The CMake install already places the binaries, the `.desktop` entry, and the udev
rule (`-DUDEV_RULES_DIR=/etc/udev/rules.d` for a real system path). `cpack` on top
gives you `.deb`/`.rpm`/`.tar.gz` for free.

---

## Updates (E10)

How an installed EdgeHub gets newer. Two halves: **how each format updates**
(below) and **how the app finds out** (the opt-in in-app check, further down).
EdgeHub never self-replaces its own binaries in any format.

### Per-format update story

| Format | How it updates |
|---|---|
| **AUR** | `paru`/`yay` (or `git pull && makepkg -si`). The PKGBUILD verifies the source tarball signature via `validpgpkeys`. |
| **.deb / .rpm** | The distro's package manager (`apt`, `dnf`), like any other package. No self-update — that would fight dpkg/rpm ownership of the files. |
| **Flatpak** *(future)* | Flathub's native mechanism: `flatpak update` / GNOME Software / Discover. This is the format's own update path — do **not** bolt zsync or an in-app downloader onto it. |
| **AppImage** | Download the new file — or delta-update via **zsync** (below), which transfers only the blocks that changed instead of the whole ~46 MB. |

### AppImage + zsync

> **Status: NOT YET EXERCISED. No release has ever shipped an AppImage.**
> `v1.0.0-alpha.1` and `v1.0.0-alpha.2` published neither an `.AppImage` nor a
> `.zsync`, so the `zsyncmake` branch of `scripts/release.sh` has never once
> executed and no user has ever delta-updated anything. The CI `appimage` job
> builds an AppImage but only uploads it as a workflow artifact (which expires);
> attaching it to a release is a manual `--extra` step that has not been done.
> Everything below describes the *designed* contract, not an observed one.
> Exercising it end-to-end is an **RC exit criterion** — see BACKLOG.md.

Every release that ships an AppImage also ships `<name>.AppImage.zsync`,
generated by `scripts/release.sh` when the AppImage is passed as an `--extra`
artifact (the build script `packaging/appimage/build-appimage.sh` deliberately
does not generate it — the `.zsync` must embed the release tag's download URL,
which only the release flow knows). Properties worth knowing:

- The `.zsync` is generated from the exact bytes in `dist/`, **before**
  `SHA256SUMS` is written, so it is checksummed and covered by the release
  signature like every other artifact.
- Its `-u` URL pins the **versioned** download
  (`releases/download/<tag>/<name>.AppImage`), never `releases/latest/` — a
  `.zsync` names the bytes it indexes, and "latest" changes meaning.
- Updating with the zsync client:
  ```sh
  zsync https://github.com/skyphoenix-it/XeneonEdge_Linux/releases/download/<tag>/<name>.AppImage.zsync \
        -i ./your-current-EdgeHub.AppImage        # seeds unchanged blocks locally
  ```
  Tools like `AppImageUpdate` can consume the same file.
- **Tool dependency:** `zsyncmake` must be on the maintainer's machine
  (Arch/CachyOS: `zsync` from the AUR; Debian/Ubuntu/Fedora: `zsync`).
  `release.sh` checks this in preflight and **refuses the release** rather
  than publishing an AppImage without its `.zsync` — a missing `.zsync`
  silently breaks delta updates for everyone on the previous release.
- The AppImage embeds
  `gh-releases-zsync|skyphoenix-it|XeneonEdge_Linux|latest|xeneon-edge-hub-*-x86_64.AppImage.zsync`
  as `X-AppImage-UpdateInformation` (via linuxdeploy-plugin-appimage's
  `LDAI_UPDATE_INFORMATION`). `AppImageUpdate` / `appimaged` can therefore
  discover the newest matching release and its `.zsync` without a manually
  copied URL. The `.zsync` itself still pins its versioned `-u` target: discovery
  follows `latest`, while the block map always describes one immutable artifact.

### The in-app update check (opt-in, and why it is off)

`ui/qml/widgets/UpdateChecker.qml` is a check-only service — it reports, it
never downloads or installs. The privacy constraint is structural, not a
preference:

- **Off by default.** The product's core claim is zero egress with a default
  config, and CI *attests* it (`packaging/ci/no-egress.sh` fails the build on
  a single `connect()` from a default-config hub). The toggle lives in
  Settings → "Software updates" and persists as the `updateCheck` appearance
  flag.
- **One request, through the gate.** When (and only when) opted in, the check
  performs one GET of
  `https://api.github.com/repos/skyphoenix-it/XeneonEdge_Linux/releases` through
  `NetHub.request()`. The list endpoint is deliberate: GitHub's `latest`
  endpoint excludes pre-releases, so it cannot represent the alpha/beta/RC
  train. The same audited choke point as every widget applies the global
  offline kill switch and host allowlist, and its attestation counters count the
  request. No token, machine identifier, or telemetry is sent beyond what a GET
  inherently carries. It re-checks daily while enabled, plus a manual "Check
  now".
- **Install-type honest.** An AppImage sets `$APPIMAGE` in the environment
  (read via the audited `${env:}` resolver on ConfigBridge — QML cannot read
  the environment itself); only then does the result line point at the
  zsync/download path. Anything else is told to **update via your package
  manager** — the app never suggests bypassing the distro.
- **Version-compare honest.** `tag_name` is ordered against
  `ConfigBridge.appVersion()` with SemVer pre-release rules
  (`1.0.0-alpha.2 < 1.0.0-beta.1 < 1.0.0-rc.1 < 1.0.0`, numeric identifiers
  numerically — a naive string compare calls `v1.0.0-alpha.2` *newer* than
  `v1.0.0`). Unversioned `dev` builds report the latest tag without claiming
  an update. Pinned by `tests/ui/tst_update_checker.qml`.

---

## Release signing

### The key

| | |
|---|---|
| **Fingerprint** | `2F0CAD36DC1D46F3347B7EF293CDC77EACF98990` |
| **Short id** | `93CDC77EACF98990` (display only — **never** use a short id to decide trust; they are forgeable by construction) |
| **UID** | SKYPhoenix IT `<simon.kreitmayer@skyphoenix-it.com>` |
| **Type** | ed25519, created 2026-07-15, **expires 2028-07-14** |
| **Public half** | [`packaging/edgehub-signing.pub`](../packaging/edgehub-signing.pub) in this repo, and <https://github.com/SimonKreitmayer.gpg> |
| **Secret half** | The maintainer's machine. Nowhere else. |

### What is signed, and what isn't

| Release | Signed? |
|---|---|
| `v0.1.0` | ❌ predates the key |
| `v1.0.0-alpha.1` | ❌ predates the key — checksum-only, and its release notes say so |
| `v1.0.0-alpha.2` | ✅ signed tag; release page documents signed checksums |
| later releases | Must pass the signing/release gate; never assume |

`v1.0.0-alpha.1` is **not** retroactively signed. Signing an old artifact today
would attest that it was vouched for at publication, which isn't true; the honest
record is that it shipped before the key existed. Its notes stay as they are.

Per release, `scripts/release.sh` signs:

- **`SHA256SUMS.asc`** — a detached armored signature over the checksum list. One
  signature covers every artifact transitively: sign the list, and the list
  fixes the files.
- **`<tarball>.tar.gz.sig`** — a detached binary signature over the source
  tarball, which is what `packaging/aur/PKGBUILD` verifies via `validpgpkeys`.

Binaries themselves are not individually signed, and there is no Secure Boot /
kernel-module signing story — there's nothing here that needs one.

### The policy: signing is interactive, local, and never automated

**The passphrase belongs to the maintainer and is never delegated** — not to a CI
secret, not to an environment variable, not to a script. `scripts/release.sh`
runs on the maintainer's own machine and gpg prompts a human, who answers.

This is deliberate, and it costs something: releases cannot be cut by CI. That
cost *is* the feature. A signature exists to prove a specific person vouched for
specific bytes; a key a build server can use unattended proves only that the
build server was reachable, and it moves the trust root to whoever can push a
workflow file or read a secret. `.github/workflows/` therefore has no signing
step, and must not grow one.

Consequences worth stating plainly:

- **Releases are cut by hand.** No tag-triggered publishing.
- **Release provenance must be exact.** `release.sh` requires a completely clean
  worktree, requires the requested signed tag to resolve to `HEAD`, and verifies
  that the tag was signed by the pinned release-key fingerprint before running
  the mandatory strict release gate. A gate failure aborts before `dist/`, the
  shipping build, signing, or publishing can begin; there is no skip option.
  After the gate, provenance is checked again and the shipping build uses a fresh
  tree extracted from the verified commit archive, not the mutable checkout or a
  reusable CMake cache.
- **A compromised CI cannot forge a release.** It can forge an *unsigned* one, so
  users must check the signature — which is why the verification steps are in the
  README and not buried here.
- **`release.sh` refuses rather than degrades.** Every path that cannot sign exits
  non-zero *before* any artifact is written. An unsigned release that looks
  signed is worse than an honest unsigned one, so a half-failed run cannot leave
  publishable-looking output in `dist/`.

### Known gaps

- **The key is not on a keyserver.** `gpg --recv-keys` does not find it, so users
  (and `makepkg`, which fails with "unknown public key") must import from GitHub
  or this repo. Publishing to <https://keys.openpgp.org> is a maintainer action:
  ```sh
  gpg --send-keys --keyserver keys.openpgp.org 2F0CAD36DC1D46F3347B7EF293CDC77EACF98990
  ```
- **AUR status is not release evidence.** The recipe must be checked against the
  exact published tag and assets, and the package's public availability/freshness
  must be verified separately.
- **No revocation certificate is published.** If the key is lost, there is no way
  to tell users to stop trusting it. Generate one (`gpg --gen-revoke`) and store
  it offline, separately from the key.

### Expiry and rotation

The key **expires 2028-07-14**. Expiry is a dead-man's switch: if the key is lost
or abandoned, it stops being trusted on its own rather than staying valid
forever. It is not a deadline to dread — extending is routine:

```sh
gpg --edit-key 2F0CAD36DC1D46F3347B7EF293CDC77EACF98990   # > expire > save
gpg --export --armor 2F0CAD36DC1D46F3347B7EF293CDC77EACF98990 > packaging/edgehub-signing.pub
```

Extending keeps the fingerprint, so every published signature and
`validpgpkeys` entry stays valid — **prefer this over rotating.** Re-export the
public key afterwards, or users importing from the repo will still see the old
expiry.

Rotate to a *new* key only on compromise or loss. That is expensive and should be
treated as such: the new fingerprint must be published in the README,
`packaging/edgehub-signing.pub`, `packaging/aur/PKGBUILD` (`validpgpkeys`),
`scripts/release.sh` (`RELEASE_KEY`), and this file — and, if the old key is
compromised rather than merely lost, users must be told which releases predate
the rotation, via the revocation certificate above.

Calendar note: **check the expiry at the 2028 GA planning point**, not on
2028-07-14. A key that expires between an RC and a GA is a bad afternoon.

---

## 3. Licensing (the part that decides your money options)

- **This project is MIT OR Apache-2.0** (`LICENSE-MIT`, `LICENSE-APACHE`) — both
  are permissive licenses. You may sell
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

## 5. Release distribution checklist

- [ ] Exact-candidate Fedora RPM and Ubuntu DEB lifecycle jobs pass.
- [ ] Exact-candidate AppImage builds and launches on the minimum target host.
- [ ] Published AppImage N discovers and zsync-updates to published N+1.
- [ ] AUR recipe matches the signed tag/assets and its public status is verified.
- [ ] Upgrade, reinstall and uninstall preserve user config and remove owned files.
- [ ] Release key is available to the maintainer; tag and artifacts are signed and
      verify from a clean consumer environment.
- [ ] Revocation certificate is generated and stored offline; public-key
      distribution instructions are current.
- [ ] Every advertised download URL is live and its platform boundary is stated.
- [ ] Flatpak/Flathub remains unadvertised until its own lifecycle and publication
      are complete.

See also: [authoring widgets](widgets/authoring.md) · [installation](installation/).
