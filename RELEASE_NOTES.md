# Unreleased development hold

> **DO NOT PUBLISH THIS FILE AS RELEASE NOTES.** It is a fail-visible placeholder
> for the current development branch. There is no new beta, feature freeze, code
> freeze or release-ready candidate.

The latest public baseline remains `v1.0.0-alpha.2`. Work after that tag contains
substantial Hub, Manager, widget, packaging and test improvements, but source-tree
features and passing development tests are not a release certificate.

## Why publication is blocked

- The authoritative requirements audit still has an unresolved user-facing
  disconnect-notification/selection-guidance gap.
- The 2026-07-21 formal short profile **failed** its memory limits on the dirty
  development binary: idle peak RSS was 408.094 MiB against `<150 MiB`; the exact
  10-widget profile peaked at 472.820 MiB against `<250 MiB`. Startup and average
  CPU passed, but the aggregate result is still failure.
- The qualifying long-duration performance and physical-hardware stability runs
  are incomplete.
- Exact-candidate native package lifecycles and a published AppImage/zsync update
  round trip are incomplete. A recipe or workflow is not package availability.
- Legal/trademark review and any store, pricing, refund, support and key-delivery
  path are not complete.
- The worktree is not an immutable signed candidate and the strict release gate
  has not passed for one.

## Maintainer action

Before invoking `scripts/release.sh`, replace this entire hold with notes for the
exact signed tag. Describe only artifacts that are actually uploaded and verified;
do not claim AUR, DEB, RPM, AppImage, Flatpak, self-update, paid delivery or broad
platform support without the corresponding release evidence.

See [MVP scope and evidence status](docs/product/mvp-scope.md),
[the beta/release gate](docs/BETA_PLAN.md), and
[distribution status](docs/DISTRIBUTION.md).
