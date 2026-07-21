# Packaging

Distro packages for the Xeneon Edge Linux Hub (and the bundled Manager). See
`docs/DISTRIBUTION.md` for the strategy/rationale. Rollout order: **AUR → AppImage
→ .deb/.rpm → Flatpak**.

Shared install metadata lives in `assets/` and is wired into `install(...)` in the
top-level `CMakeLists.txt`: both `.desktop` files, both AppStream `metainfo` files,
the hicolor icons (scalable SVG + PNG 16–512), the `LICENSE`, and the udev rule.

| Format | Location | Status |
|---|---|---|
| **AUR** | `packaging/aur/` (`PKGBUILD`, `.SRCINFO`, `.install`) | ✅ **published** - [aur/xeneon-edge-hub](https://aur.archlinux.org/packages/xeneon-edge-hub) (v1.0.0alpha.2, maintainer SKYPhoenix_IT); builds from the signed release tarball, `validpgpkeys` verified against a cold clone |
| **CPack .rpm** | `CMakeLists.txt` (CPack block) | ✅ Fedora 43: built, installed on a clean image, launches (CI: `distro.yml`) |
| **CPack .deb** | `CMakeLists.txt` (CPack block) | ✅ Ubuntu 26.04 LTS: built, installed on a clean image, launches (CI: `distro.yml`) |
| **CPack .tgz** | `CMakeLists.txt` (CPack block) | ✅ TGZ tested |
| **AppImage** | `packaging/appimage/build-appimage.sh` | ✅ built (Ubuntu 24.04 + Qt 6.7.3) + smoke-tested in a bare container with no Qt. **CI-verified** (`distro.yml`: build + bare-container smoke, both green) |
| **Flatpak** | `packaging/flatpak/` | ⚠️ starter manifest, open items (see `flatpak/README.md`) |

"Installs on a clean image" means the package was installed into a container with
**no Qt and no `-devel` packages present**, so its declared dependencies had to
pull the entire runtime themselves. Installing into the build container proves
nothing - the `-devel` packages already dragged Qt in.

### Verified distro support

| Distro | Qt (distro's own) | Build | Package | Clean install | Launch |
|---|---|---|---|---|---|
| Fedora 43 | 6.10.3 | ✅ | ✅ RPM | ✅ | ✅ |
| Ubuntu 26.04 LTS | 6.10.2 | ✅ | ✅ DEB | ✅ | ✅ |
| Arch / CachyOS | rolling | ✅ (dev box + AUR) | ✅ AUR | - | ✅ |
| Ubuntu 24.04 LTS | 6.4.2 (too old) | ✅ w/ Qt 6.7.3 | ✅ AppImage | ✅ bare, no Qt | ✅ |

Both distros now ship Qt ≥ 6.5 in their own repos, so neither needs the
`jurplel/install-qt-action` Qt that `ci.yml` uses for the Ubuntu 24.04 jobs
(24.04's apt Qt is 6.4.2 - too old for `QtQuick.Effects`).

Ubuntu 24.04 LTS is **not** supported for the `.deb`: its Qt is 6.4.2 and the app
requires ≥ 6.5. 24.04 users need the AppImage or a backported Qt.

### The .deb dependency gotcha

QML modules are `dlopen`'d plugins, so `dpkg-shlibdeps` cannot see them, and
Debian/Ubuntu ship each as a separate `qml6-module-*` package. With only the
shlibdeps-derived list the `.deb` installed perfectly and then died on launch:

```
module "QtQuick.Controls" plugin "qtquickcontrols2plugin" not found
```

`CPACK_DEBIAN_PACKAGE_DEPENDS` in `CMakeLists.txt` therefore lists every
`qml6-module-*` explicitly; keep it in sync with the `import` lines under
`ui/qml/` and `manager/`. Fedora needs no equivalent - `qt6-qtdeclarative`
bundles all of them in one RPM.

`packaging/ci/smoke.sh` guards this. It launches the installed binary offscreen
**and** checks every module imported by the sources is present, because launching
alone is not enough: `main.qml` only imports QtQuick/Controls/Layouts/Window/
VirtualKeyboard, so `QtQuick.Effects`/`Shapes`/`Dialogs` (reached via lazily
loaded widgets) can be missing and the app still starts cleanly for 10s.

The same script covers the AppImage via `packaging/ci/smoke-appimage.sh`, which
extracts the AppImage (containers have no FUSE), puts a wrapper on `PATH`, and
points `QML_DIR` at the bundled `usr/qml`. The AppImage is the case that needs the
module check most: `linuxdeploy`'s Qt plugin bundles what it can *see*, and it
cannot see a lazily-imported QML module. `distro.yml` therefore also runs a
**negative control** - it deletes `QtQuick.Effects` from the AppImage and asserts
the smoke FAILS. (Confirmed: with `Effects` deleted the hub still runs a clean 10s
launch; only the module check catches it. A smoke that cannot fail proves nothing.)

## AUR

```sh
cd packaging/aur
makepkg -si            # build + install the signed release named by _tag
```
Publishing: push `PKGBUILD` + `.SRCINFO` to `ssh://aur@aur.archlinux.org/xeneon-edge-hub.git`.
Before publishing an update, set the pacman-compatible `pkgver`, the exact Git
release `_tag`, and the release-asset checksum together, then regenerate
`.SRCINFO` with `makepkg --printsrcinfo`. The detached signature is mandatory and
is verified against the full fingerprint in `validpgpkeys`.

## CPack (.deb / .rpm / portable tarball)

Configure + build the project, passing the release version explicitly so the
embedded app version, package metadata and filename cannot diverge:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DXENEON_VERSION_OVERRIDE=1.0.0-beta.1
cmake --build build -j"$(nproc)"
```

Then from the build dir:

```sh
cpack -G TGZ           # portable archive; system glibc/Qt compatibility required
cpack -G DEB           # on Debian/Ubuntu (needs dpkg + dpkg-shlibdeps)
cpack -G RPM           # on Fedora/openSUSE (needs rpmbuild)
```

Build each on the distro it targets - the generated dependency versions come from
whatever is installed on the build host. Generator preflight fails closed when
the required native tools are absent; in particular, it prevents CPack from
returning success with an empty-architecture `.deb` and no shlibdeps. The exact
per-distro build dependencies are in `.github/workflows/distro.yml`, which is the
executable version of this:

For DEB/RPM metadata, a SemVer prerelease such as `1.0.0-beta.1` is encoded as
`1.0.0~beta.1`, which sorts before the later `1.0.0` final package. The TGZ and
its filename retain the human-facing SemVer spelling.

```sh
# Fedora 43
dnf -y install cmake gcc-c++ make rpm-build cargo rust mesa-libGL-devel \
  qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg-devel \
  qt6-qtvirtualkeyboard-devel qt6-qtwayland-devel

# Ubuntu 26.04 LTS (ca-certificates is required or cargo's crates.io fetch
# fails with "[77] Problem with the SSL CA cert" on a bare image)
apt-get install -y ca-certificates cmake g++ make file dpkg-dev rustc cargo \
  libgl1-mesa-dev qt6-base-dev qt6-declarative-dev qt6-svg-dev \
  qt6-virtualkeyboard-dev
```

## AppImage

```sh
./packaging/appimage/build-appimage.sh          # needs qmake6 (Qt >= 6.5) on PATH
```
Downloads `linuxdeploy` + the Qt plugin and bundles Qt into a single portable
`xeneon-edge-hub-<version>-x86_64.AppImage` (~46 MB, 41 Qt libs).

Build it on the **oldest** distro you intend to support - an AppImage's glibc floor
is its build host's. CI uses Ubuntu 24.04 with upstream Qt 6.7.3 via
`install-qt-action`, deliberately *not* 24.04's apt Qt 6.4.2 (too old for
`QtQuick.Effects`). `build-appimage.sh` needs the xcb/wayland/fontconfig runtime
libs present on the build host so `linuxdeploy` can resolve every ELF it bundles,
even though they are excluded from the result - the exact list is in the `appimage`
job in `.github/workflows/distro.yml`.

Smoke it the way CI does - in a container with **no Qt**:
```sh
bash packaging/ci/smoke-appimage.sh xeneon-edge-hub-VERSION-x86_64.AppImage "$(pwd)"
```

It bundles Qt but **not** libGL/libGLX/libOpenGL/libEGL/libfontconfig or fonts;
`linuxdeploy` excludes the graphics stack on purpose (a bundled libGL breaks on a
host with a different driver), so those come from the host. Desktops have them,
bare containers don't.

Two failure modes are baked into the script as comments because both are **silent**
- they produce a smaller AppImage with *no Qt in it* and still exit 0: omitting
`--executable` for both binaries, and leaving Qt off `LD_LIBRARY_PATH`. See
`docs/DISTRIBUTION.md`.

## Flatpak

See `packaging/flatpak/README.md` - the manifest is a starting point; a Flathub
submission still needs cargo vendoring and the sandbox-access items resolved.

## Note on auto-rotate

No package format can enable the Edge's orientation sensor by itself - it lives on
a root-only hidraw node. The udev rule (`packaging/udev/99-xeneon-edge.rules`) is
installed by the AUR/deb/rpm packages under `/usr/lib/udev/rules.d`; AppImage/Flatpak
users install it manually. Everything else works without it (manual orientation
modes still apply).
