---
name: packaging
description: "How the Xeneon Edge apps are packaged (icons, desktop, metainfo, AUR/CPack/AppImage/Flatpak) and what's build-tested"
metadata: 
  node_type: memory
  type: project
  originSessionId: 59076df8-2015-4bf2-9a34-fa4a0f7bc65f
---

Packaging added 2026-07 (after the real-hardware test pass). Strategy in
`docs/DISTRIBUTION.md`; overview + per-format instructions in `packaging/README.md`.
Rollout: AUR → AppImage → deb/rpm → Flatpak.

Shared install metadata (all wired into the top-level `CMakeLists.txt` `install(...)`):
- `assets/icon/*.svg` — branded icons (hub = Edge device with ring gauge + bars;
  manager = same base + a sliders "controls" badge). Rasterized to
  `assets/icon/hicolor/<size>x<size>/apps/*.png` (16-512, committed). Installed to
  `share/icons/hicolor/{scalable,<size>}/apps`.
- `assets/xeneon-edge-{hub,manager}.desktop` (both, single main Category; pass
  `desktop-file-validate`).
- `assets/metainfo/com.skyphoenix_it.XeneonEdge{Hub,Manager}.metainfo.xml` (pass
  `appstreamcli validate`). **App/AppStream/Flatpak ID = `com.skyphoenix_it.*`** —
  underscore, NOT hyphen: the real domain is skyphoenix-it.com but a hyphen in the
  rDNS component id fails AppStream validation (`cid-rdns-contains-hyphen`);
  underscore is allowed. Revisit before a Flathub submission.
- `LICENSE` → `share/licenses/xeneon-edge-hub/`.

GOTCHA (cost a CPack failure): the udev-rule `install(... DESTINATION ...)` must be
RELATIVE to the prefix (`lib/udev/rules.d`), not absolute (`/usr/lib/...`) — an
absolute DESTINATION makes CPack try to write the real `/usr` (permission denied).
Relative works for CPack, DESTDIR/makepkg, and plain installs. `UDEV_RULES_DIR`
cache var overrides it (absolute for a system install to /etc).

Build-tested HERE (Arch/CachyOS): **AUR PKGBUILD** via `makepkg` → valid
`xeneon-edge-hub-0.1.0-1-x86_64.pkg.tar.zst`, correct Qt6 deps
(qt6-base/declarative/svg/virtualkeyboard/wayland + hicolor). **CPack TGZ** via
`cpack -G TGZ`. NOT testable here (tooling absent): CPack DEB/RPM (no dpkg/rpmbuild),
AppImage (no appimagetool/linuxdeploy), Flatpak (no flatpak-builder). To test the
PKGBUILD without a published release, `tar` the working tree as
`XeneonEdge_Linux-0.1.0/` and point a copy of the PKGBUILD `source=()` at it.

Not yet done: a tagged GitHub release `v0.1.0` (PKGBUILD/Flatpak source point at it),
real `sha256sums` (currently SKIP), Flatpak open items (cargo vendoring via
flatpak-cargo-generator, /sys metrics access, cross-sandbox Manager↔hub IPC),
metainfo screenshots. `qt6-wayland` IS a runtime dep (Wayland platform plugin, not
caught by ldd). Auto-rotate udev rule ships in AUR/deb/rpm under /usr/lib/udev/rules.d;
AppImage/Flatpak users install it manually.
