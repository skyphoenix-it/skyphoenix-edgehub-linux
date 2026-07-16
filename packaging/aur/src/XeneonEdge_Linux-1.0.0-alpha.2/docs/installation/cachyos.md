# Installation Guide — CachyOS / Arch Linux

**Work in progress** — This guide will be completed in Phase 5 (Hardening).

## Quick Install

### From AUR (once published)

```bash
yay -S xeneon-edge-hub
```

### From Release Package

```bash
# Download the latest release
wget https://github.com/your-org/xeneon-edge-linux-hub/releases/latest/download/xeneon-edge-hub-0.1.0-1-x86_64.pkg.tar.zst

# Install
sudo pacman -U xeneon-edge-hub-0.1.0-1-x86_64.pkg.tar.zst
```

## Prerequisites

The package will automatically pull these dependencies:
- `qt6-base`
- `qt6-declarative`
- `qt6-wayland`
- `qt6-tools`
- `glibc`

## Post-Install

1. Launch from application menu: "Xeneon Edge Linux Hub"
2. Or from terminal: `xeneon-edge-hub`
3. Follow the first-run wizard to select your display.

## Uninstall

```bash
sudo pacman -R xeneon-edge-hub
```

Configuration files in `~/.config/xeneon-edge-hub/` are preserved. Remove them manually if desired:

```bash
rm -rf ~/.config/xeneon-edge-hub/
rm -rf ~/.local/share/xeneon-edge-hub/
```

## Troubleshooting

See [Troubleshooting Guide](../troubleshooting/common-issues.md).

