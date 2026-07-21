# Press kit

> **Internal draft.** Fill the release fact sheet from the signed artifacts and
> evidence page, not from plans or CI workflow names.

## Short description

EdgeHub is a native Linux dashboard for the Corsair Xeneon Edge. It provides
touch-first widget pages and a companion desktop Manager for editing the running
panel.

## 80-word boilerplate

EdgeHub is an independent Linux application by SKYPhoenix IT for the Corsair
Xeneon Edge. A Rust core handles configuration and metrics while Qt 6/QML powers
the touch-first Hub and companion desktop Manager. The current product catalog
contains 30 first-party widgets and 19 preset screens, with portrait and
landscape layouts. Configuration stays in local TOML, no account is required,
and the application has no telemetry implementation. EdgeHub source is licensed
under MIT OR Apache-2.0.

## Release fact sheet

| Field | Verified release value |
|---|---|
| Product | EdgeHub |
| Publisher | SKYPhoenix IT |
| Version | [VERSION] |
| Release date | [RELEASE_DATE] |
| Verified platforms | [VERIFIED_PLATFORM_SUMMARY] |
| Published artifacts | [SUPPORTED_PACKAGES] |
| Source licence | MIT OR Apache-2.0 |
| Price/store | [VERIFIED_COMMERCIAL_TERMS_OR_NOT_AVAILABLE] |
| Download | [DOWNLOAD_URL] |
| Release evidence | [RELEASE_EVIDENCE_URL] |
| Support | [SUPPORT_URL] |
| Contact | [CONTACT] |

## Product facts

- 30 first-party widgets across System, Time, Focus, Media, Data, and Info.
- 19 preset screens.
- Multi-page portrait and landscape layouts.
- A separate desktop Manager with live local-socket synchronization.
- 29 themes, 29 accents, 10 animated backgrounds plus Gradient, and 18 bundled
  wallpapers in the current catalog.
- Local TOML configuration.
- No account requirement and no telemetry implementation.
- Central egress gate for configured network-capable features.
- Free contains every functional feature; Pro currently changes only access to
  nine optional themes.

## FAQ

### Is EdgeHub made by Corsair?

No. EdgeHub is an independent product by SKYPhoenix IT. It is not affiliated
with, sponsored by or endorsed by Corsair. The Corsair and Xeneon Edge names are
used only to describe hardware compatibility.

### Is it Electron or a browser dashboard?

No. The current implementation uses a Rust core and native Qt 6/QML
applications for the Hub and Manager.

### Does it require an account?

No account is required by the application.

### Does it send telemetry?

The application has no telemetry implementation. User-configured network
widgets and the opt-in update check are separate network-capable features and
pass through the application's central egress gate.

### What is paid?

The current code's Pro entitlement adds nine optional colour themes. All
widgets, presets, layout tools, backgrounds, wallpapers, accessibility features,
and the Manager remain in Free. Do not describe a price or purchase route unless
the final fact sheet contains verified commercial terms.

### Does it auto-update?

Answer only from the final artifact evidence. The source contains update-check
and AppImage metadata work, but the project does not claim a working published
delta-update flow until a real release-to-release round trip is verified.

### Which Linux distributions and desktops are supported?

Use only `[VERIFIED_PLATFORM_SUMMARY]`. Do not substitute the intended test
matrix or package recipes for completed release evidence.

## Credits

- Product and publisher: SKYPhoenix IT.
- Technology: Rust, C++17, Qt 6, QML, CMake.
- Third-party licences and bundled asset notices: link `[THIRD_PARTY_NOTICES_URL]`.
- Contributors: [CONTRIBUTOR_CREDITS].

## Media asset rule

Only distribute the exact-candidate captures approved in
[`asset-plan.md`](asset-plan.md). Do not present development screenshots,
generated concepts, or third-party hardware branding as release evidence.
