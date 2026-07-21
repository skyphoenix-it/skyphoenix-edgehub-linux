# Ubuntu installation

## Supported native release

The native `.deb` target is supported on **Ubuntu 26.04 LTS or newer**, where
the distribution supplies Qt 6.5 or newer. The package lifecycle is tested in a
clean Ubuntu 26.04 container: build, dependency resolution, install, real QML
startup, desktop metadata and AppStream validation.

Ubuntu 24.04 ships Qt 6.4.2, which is below the application's Qt 6.5 floor.
Do not install the native `.deb` there. Use an AppImage built with Qt 6.5 or
newer when one is attached to a release, or provide a newer Qt separately.

## Install a release DEB

When the release page includes an Ubuntu package, download the `.deb`,
`SHA256SUMS` and `SHA256SUMS.asc`, verify them as described in the repository
README, then install the local file:

```sh
sudo apt install ./xeneon-edge-hub_VERSION_amd64.deb
```

Only use a DEB produced by the Ubuntu packaging job. The repository deliberately
refuses local `cpack -G DEB` when `dpkg` and `dpkg-shlibdeps` are unavailable,
because CPack would otherwise emit an invalid package while reporting success.

## Build on Ubuntu 26.04

```sh
sudo apt update
sudo apt install ca-certificates git cmake g++ make file dpkg-dev rustc cargo \
  libgl1-mesa-dev qt6-base-dev qt6-declarative-dev qt6-svg-dev \
  qt6-virtualkeyboard-dev

git clone https://github.com/skyphoenix-it/skyphoenix-edgehub-linux.git
cd skyphoenix-edgehub-linux
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
```

To create the distro package on that supported host:

```sh
cd build
cpack -G DEB
```

The generated package combines dependencies derived by `dpkg-shlibdeps` with
explicit `qml6-module-*` dependencies. The explicit list is required because QML
plugins are loaded dynamically and therefore cannot be discovered from ELF
linkage alone.

## Launch

- Dashboard: `xeneon-edge-hub`
- Companion configuration app: `xeneon-edge-manager`

Both applications also install desktop-menu launchers. The first dashboard
start opens display selection when no target has been configured.

## Upgrade and uninstall

Install a newer local package with the same `apt install ./…deb` command. Restart
any running Hub or Manager process afterward so it uses the upgraded binary.

```sh
sudo apt remove xeneon-edge-hub
```

Package removal intentionally preserves
`~/.config/xeneon-edge-hub/config.toml`. Remove that directory manually only if
you explicitly want to discard the dashboard layout and settings.

See [common issues](../troubleshooting/common-issues.md) for display and
orientation troubleshooting.
