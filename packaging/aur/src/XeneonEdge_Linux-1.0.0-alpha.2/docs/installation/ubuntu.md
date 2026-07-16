# Installation Guide — Ubuntu 24.04 LTS

**Work in progress** — This guide will be completed in Phase 5 (Hardening).

## Quick Install

### From Release .deb

```bash
# Download the latest release
wget https://github.com/your-org/xeneon-edge-linux-hub/releases/latest/download/xeneon-edge-hub_0.1.0_amd64.deb

# Install
sudo apt install ./xeneon-edge-hub_0.1.0_amd64.deb
```

## Prerequisites

The package will automatically pull these dependencies:
- `qt6-base-dev` (runtime libraries)
- `qt6-qml6`
- `qt6-wayland`
- `libc6`

## Post-Install

1. Launch from application menu: "Xeneon Edge Linux Hub"
2. Or from terminal: `xeneon-edge-hub`
3. Follow the first-run wizard to select your display.

## Uninstall

```bash
sudo apt remove xeneon-edge-hub
```

Configuration files in `~/.config/xeneon-edge-hub/` are preserved. Remove them manually if desired:

```bash
rm -rf ~/.config/xeneon-edge-hub/
rm -rf ~/.local/share/xeneon-edge-hub/
```

## System Requirements

- Ubuntu 24.04 LTS or newer
- Qt 6.5+ (provided by Ubuntu repositories)
- A secondary display (Corsair Xeneon Edge or similar)

## Troubleshooting

See [Troubleshooting Guide](../troubleshooting/common-issues.md).

