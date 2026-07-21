# Flatpak

`com.skyphoenix_it.XeneonEdgeHub.yml` is a **starter** manifest (KDE runtime, which
ships Qt 6). It is not yet build-tested. Local test build once the open items below
are handled:

```sh
flatpak install flathub org.kde.Sdk//6.7 org.kde.Platform//6.7 \
    org.freedesktop.Sdk.Extension.rust-stable//24.08
flatpak-builder --user --install --force-clean build-flatpak \
    packaging/flatpak/com.skyphoenix_it.XeneonEdgeHub.yml
```

## Open items before this is Flathub-ready

1. **Rust offline build.** Flathub builds have no network, so cargo crates must be
   vendored: run `flatpak-cargo-generator core/Cargo.lock -o cargo-sources.json`,
   commit it here, and add it to the module `sources`. (For a quick local test you
   can instead add `build-args: ['--share=network']` to the module.)
2. **Orientation sensor.** Reading the Edge's hidraw node needs device access
   (`--device=all` for now) *and* the host udev rule - a Flatpak can't ship a udev
   rule, so auto-rotate still requires the manual host step. Consider narrowing the
   device permission.
3. **System metrics.** CPU/GPU/temp readings come from `/proc` and `/sys`. `/proc`
   is available in the sandbox but some `/sys` paths (GPU, hwmon) are not - those
   metrics degrade. Decide whether to request broader `--filesystem` access or
   accept the degradation.
4. **Manager ↔ hub IPC.** The two apps talk over a `QLocalServer` socket. Across
   separate Flatpak sandboxes they don't share `/tmp` / `XDG_RUNTIME_DIR`, so the
   live-sync won't connect out of the box. Options: ship both in one Flatpak, use a
   shared `--filesystem`, or a portal. Editing config on disk still works.
5. **Screenshots + a stable app-id.** Flathub requires screenshots in the metainfo
   and a component-id matching a domain/repo you control (the current
   `com.skyphoenix_it.*` uses an underscore for the hyphenated domain - confirm this
   is what you want before submitting).
