# EdgeHub roadmap

**Last updated:** 2026-07-21
**Public baseline:** `v1.0.0-alpha.2`
**Development status:** unreleased; no feature freeze or code freeze declared

The current branch is a release candidate work area, not a released beta. A
milestone changes only when its evidence is complete and an actual tag is
published.

## Current implementation

- Native Rust core with a hand-written C ABI and Qt 6/QML Hub and Manager.
- Multi-page, touch-first dashboards with display targeting, hot-plug handling,
  orientation support, local TOML state and Manager-to-Hub live updates.
- **30** first-party widgets registered in `ui/qml/WidgetCatalog.qml`.
- **19** ready-made screens registered in `ui/qml/PresetCatalog.qml`.
- **29** themes and **29** accents in `ui/qml/Theme.qml`.
- **10** animated backgrounds plus the static Gradient style in
  `ui/qml/BackgroundCatalog.qml`, and 18 bundled wallpapers.
- Rust, C++, QML, compositor-backed GUI, runtime, Manager and physical-hardware
  test layers, with release-gate and package-contract tooling.

These are implementation facts, not a statement that every release requirement
has passed.

## Gate to the next public milestone

- [ ] Resolve every P0/P1 and every release-blocking requirement finding.
- [ ] Complete the final Manager, Hub and integrated physical-Edge suites with
      zero failures and zero hidden skips.
- [ ] Run required Fedora/Ubuntu native-package jobs for the exact candidate.
- [ ] Exercise AppImage discovery and zsync update against published artifacts.
- [ ] Record reproducible idle/active CPU, RSS, startup and growth measurements.
- [ ] Complete the required 48–72-hour physical-hardware soak.
- [ ] Close the product-default, legal/trademark and payment/delivery decisions.
- [ ] Enter feature freeze only after all feature criteria above are complete.
- [ ] Fix release-blocking defects found during the freeze and re-run the gate.
- [ ] Enter code freeze only with a clean, reviewed, immutable candidate.
- [ ] Run the final strict suite from that candidate, then sign, publish and
      verify the release assets.

Until every item is complete, marketing copy must say **alpha/development
preview**, must not advertise unsupported distro/store availability, and must not
quote unverified performance numbers.

## After a verified 1.0

Potential, demand-driven work includes OBS/MangoHud/Prometheus/smart-home
integrations, a sandboxed widget SDK, marketplace governance and localization.
None has a committed delivery date.

See [the beta/release gate](docs/BETA_PLAN.md), [distribution status](docs/DISTRIBUTION.md)
and [the changelog](CHANGELOG.md).

---

*EdgeHub is an independent product of SKYPhoenix IT and is not affiliated with Corsair.*
