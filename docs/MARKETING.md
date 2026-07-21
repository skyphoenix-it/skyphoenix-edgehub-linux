# EdgeHub marketing claim register

**Status:** internal draft; not approved for publication
**Product status:** alpha/development; no beta, freeze or release candidate declared

Marketing work remains on hold until the release gate in
[`BETA_PLAN.md`](BETA_PLAN.md) passes. Screenshots and design experiments may be
used for internal review, but this file does not authorize a launch, sale or
availability claim.

## Positioning

EdgeHub is a native Linux widget dashboard for the Corsair Xeneon Edge and other
secondary or portrait touch displays. A Rust core handles configuration and
metrics; Qt 6/QML renders the Hub and companion Manager.

Public wording must use “Corsair Xeneon Edge” only to describe compatibility and
must include that EdgeHub is independent and is not affiliated with, sponsored
by or endorsed by Corsair. Do not use Corsair logos or trade dress.

## Claims supported by the current source

- 30 registered first-party widgets.
- 19 registered preset screens.
- 29 themes: 20 free and 9 Pro theme entries.
- 29 accents: 14 standard, 8 Okabe–Ito and 7 theme-completing accents.
- 10 animated backgrounds plus Gradient, and 18 bundled wallpapers.
- Multi-page portrait/landscape layouts and a standalone Manager that pushes
  changes to a running Hub over a local socket.
- Local TOML configuration, no account requirement, no telemetry implementation,
  and a central egress gate for configured network widgets and the opt-in update
  check.
- MIT OR Apache-2.0 source licensing.

These implementation facts do not prove release availability, cross-distro
support, performance, stability or store fulfilment.

## Claims prohibited until evidence exists

- “Released beta”, “release ready”, “shipping quality”, “feature frozen”, “code
  frozen” or equivalent wording.
- Any CPU, RSS, startup, leak or battery number. Earlier performance estimates
  were unsupported.
- “Available on AUR/AppImage/Flatpak/Flathub/DEB/RPM” unless the exact referenced
  package is published, downloadable and verified.
- “Auto-updating” or “one-click updates” until the AppImage zsync path has been
  exercised against published artifacts.
- A price, launch discount, refund promise, support SLA, site licence, instant
  delivery or live checkout until those business systems and policies exist and
  are tested.
- GNOME, X11, arbitrary-display or broad distro support beyond recorded
  candidate evidence.
- A 48–72-hour stability claim until that physical-hardware soak completes.

## Material that may be prepared after the gate

1. Fresh, real-device captures for portrait and landscape Hub layouts.
2. Manager Layout and Appearance captures from the same candidate.
3. A short demo showing display targeting, touch navigation and live Manager sync.
4. An evidence appendix linking the exact tag, checksums, signatures, package
   lifecycle results, performance protocol and hardware soak log.
5. Channel-specific copy generated from this register and reviewed for trademark,
   price, refund, privacy and platform accuracy.

The existing files under `docs/marketing-site/assets/` are design assets, not
proof that the candidate, theme names or depicted data are release-ready.
