# Memory index

- [Dashboard architecture](dashboard-architecture.md) — registry + store + widget contract + persistence for the rebuilt QML dashboard
- [Product decisions](product-decisions.md) — Simon's scope/data-source/dependency decisions for the hub rebuild
- [Companion app & testing](companion-and-testing.md) — xeneon-edge-manager, hub control-socket IPC, and the QML GUI test harness
- [Feedback: run location](feedback-run-location.md) — say explicitly whether Simon runs a command in his terminal or in-chat with `!`
- [Packaging](packaging.md) — icons/desktop/metainfo + AUR/CPack/AppImage/Flatpak, what's build-tested, the app-id + udev-relative-path gotchas
- [CI setup](ci-setup.md) — GitHub Actions jobs + coverage gates, and the Qt-6.7-vs-dev-6.11 / gcovr-EXCL / font-metric gotchas that only fail in CI
- [Runtime E2E testing](runtime-e2e-testing.md) — drive the real hub binary headless + assert persisted config.toml (tests/runtime/); nested-TOML / literal-ui_state / SIGKILL / self-pkill-144 gotchas
- [v1.0 release plan](v1-release-plan.md) — the approved v1.0 "Platform" plan: presets + primitive widgets + calm/a11y + enterprise + release train
- [v1.0 marketing direction](v1-marketing-direction.md) — Apple-caliber launch material (videos + real screenshots), applied at beta/RC/GA
- [MANDATE: GUI test suite](MANDATE-gui-testsuite.md) — READ FIRST after a crash: owner request for a full Manager+Hub GUI suite, safety rules, phase checklist
- [TODO: GUI test suite](TODO-gui-testsuite.md) — the plan + first measured baseline (1356 pass / 210 fail), triage rules, gaps G1-G8, safety work
