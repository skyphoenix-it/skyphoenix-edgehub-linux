**The second alpha — and the first signed release.**

Every artifact below is signed by GPG key `2F0CAD36DC1D46F3347B7EF293CDC77EACF98990` (SKYPhoenix IT). Verify before installing — see [Verifying your download](https://github.com/skyphoenix-it/XeneonEdge_Linux#verifying-your-download):

```sh
gpg --import edgehub-signing.pub          # from the repo, or your keyring
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

---

## Since alpha.1 (two days, and most of the v1.0 plan)

### Widgets: 24 → 30
- **Wellness (E5)**: Medication reminder (taken/due/later — never a shaming red), Brain-dump quick capture, daily Routine checklist (stores *no* cross-day state, so there is nothing a bad day can break), Now/Next agenda.
- **Distro easter eggs**: Package count and Since-install age, read directly from pacman/dpkg databases — no subprocess, no privilege. RPM honestly reports "unsupported" rather than shelling out.

### Looks: 22 → 29 themes, 8 → 11 backgrounds
Seven distro-inspired palettes (Arch, CachyOS, Debian, Fedora, Pop!_OS, Aubergine, Crimson) — colour only, no marks, contrast measured 13.8–17.2:1. Three new original backdrops (Peaks, Loops, Ribbons). Two bundled accessibility fonts (Atkinson Hyperlegible, Lexend — OFL, off by default).

### The sizing rework, part 1
Widgets now know how much room they have (`compact/wide/tall/large/full`), every type declares which of the 7 fixed sizes it honestly supports, tiles use absolute cell positioning (a `0.5x0.5` tile is now exactly 1/12 of the screen — the old grid rendered it at *half*), packing is rotation-stable by construction, and all 15 presets fit one screen per page.

### Trust & control
- **Verifiable no-egress attestation in CI**: the hub runs network-isolated under syscall trace with a default config and the build **fails if a single `connect()` leaves the box** — with negative controls proving the check can fail.
- **Managed org policy** (`/etc/xeneon-edge-hub/policy.toml`): pin the offline switch, pin the host allowlist, force a preset, disable widget types — fail-closed on a corrupt policy.
- **Offline Ed25519 licence verification** (core only; no keypair issued yet — every key currently reads as the free tier, by design).
- **Opt-in update check** (off by default — the no-egress attestation enforces that default), through the same audited gate as all egress.
- **User widgets (Tier-0)**: drop a `manifest.json` + QML into `~/.local/share/xeneon-edge-hub/widgets/` — off by default, shipped types win collisions, org policy can veto.
- Control socket moved from world-writable `/tmp` to `$XDG_RUNTIME_DIR` (0700). SBOM published per release; `cargo-deny` gates licences and advisories.
- The Manager's display/autostart settings no longer race the hub (single-writer over IPC).

### Fixed
- The clock no longer stalls/jumps seconds (self-correcting tick, all 12 time widgets).
- World clocks use real IANA zones (~600) with correct DST via the OS tzdata.
- The Ubuntu `.deb` declared none of its QML module dependencies and crashed on launch; Fedora 43 + Ubuntu 26.04 packages are now built, installed and launch-tested in CI containers, and the AppImage is smoke-tested on a bare host with no Qt.

## Install
**Arch/CachyOS**: build from source or the portable tarball below (AUR package coming — the PKGBUILD now verifies release signatures). **Fedora/Ubuntu**: RPM/DEB from CI or build from source. **Anything else**: portable tarball or source.

> Alpha: feature set still settling. Per-widget size optimization (each widget genuinely redesigned per size) is the remaining sizing work.

**Not affiliated with Corsair.** MIT OR Apache-2.0.
