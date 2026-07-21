# EdgeHub v1.0.0-beta.1

EdgeHub beta.1 is the first beta of the native Linux dashboard and companion
Manager for the Corsair Xeneon Edge. It focuses on the complete physical-panel
workflow: display targeting, touch navigation, portrait and landscape layouts,
live Manager-to-Hub editing, reconnect behavior, and durable configuration.

## See it in action

Watch the [52-second Hub and Manager feature tour](https://github.com/skyphoenix-it/skyphoenix-edgehub-linux/releases/download/v1.0.0-beta.1/edgehub-v1.0.0-beta.1-feature-tour.mp4).
It uses the exact signed beta.1 binaries on the physical secondary display and
shows portrait and landscape layouts, screen creation, live page selection,
Manager previews, and theme changes. English captions are included in the
repository and the [capture evidence](https://github.com/skyphoenix-it/skyphoenix-edgehub-linux/blob/master/docs/testing/release-media-validation-2026-07-21.md)
records the binaries, hashes, display, and safety controls.

## Highlights

- 30 first-party widgets and 19 preset screens.
- Touch-first portrait and landscape dashboards.
- EdgeHub Manager can add, resize, reorder, restyle, and switch the screen shown
  by the running Hub over a local socket.
- 29 themes, 29 accents, 10 animated backgrounds plus Gradient, and 18 bundled
  wallpapers.
- Local TOML configuration, no account requirement, and no telemetry
  implementation.
- All functional features, widgets, presets, layouts, backgrounds, wallpapers,
  accessibility options, and the Manager are available in Free.
- Pro entitlement is limited to nine optional colour themes; Pro keys are not
  sold as part of this beta.

## Verification summary

The development candidate completed the real-device and integration campaign:

- physical Edge workflow: 269/269 checks;
- 20-minute hardware soak: 2,169 update cycles and 54 touch swipes;
- Manager/Hub integration: 53/53 scenarios;
- display lifecycle: 18/18 scenarios;
- Rust: 242 tests; QML: 93 files; C++: 22 tests;
- nested compositor: 1,311/1,311 local checks;
- hosted coverage: 96.60% C++, 96.62% Rust, 97.06% combined.
- exact-candidate marketing capture: 8/8 Manager reflection checks and 8/8
  Manager-to-Hub screen mirror checks on KDE Plasma Wayland.

The release owner accepted the risk of publishing beta.1 without the previously
planned 48-hour soak. The final hosted compositor rerun was cancelled to stop
excessive CI usage after the corrected failing function passed locally in 3.472
seconds. No 48-hour stability or formal performance claim is made for this beta.

## Artifacts

This beta advertises only:

- the signed source tarball;
- the portable x86-64 tarball;
- `SHA256SUMS` and its detached signature;
- the detached source-tarball signature.

AppImage/zsync, AUR freshness, DEB/RPM repositories, Flatpak, and automatic
updating are not advertised for beta.1. Package recipes and CI jobs may exist,
but they are not release availability claims.

## Known limitations

- Auto-rotate needs the included udev rule; manual orientation works without it.
- Network widgets require explicit configuration and remain subject to the
  central egress gate.
- AppImage delta updating has not completed a published release-to-release
  round trip.
- This is beta software. Keep a copy of `~/.config/xeneon-edge-hub/config.toml`
  before upgrading.

## Independence notice

EdgeHub is an independent product by SKYPhoenix IT. It is not affiliated with,
sponsored by or endorsed by Corsair. “Corsair” and “Xeneon Edge” are used only
to describe hardware compatibility.

## Verification

Release artifacts are signed by GPG key
`2F0CAD36DC1D46F3347B7EF293CDC77EACF98990`. Verify the checksums and signatures
before installation. Source, downloads, issues, and documentation are available
from <https://github.com/skyphoenix-it/skyphoenix-edgehub-linux>.
