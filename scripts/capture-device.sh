#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# capture-device.sh - capture the REAL Xeneon Edge panel for marketing.
#
# Runs on YOUR machine with the hub live on the Edge. Unlike the headless
# gen_screenshots.py (which renders the app offscreen), this grabs the actual
# panel - exactly what's on screen, real fonts, real compositor.
#
#   ./scripts/capture-device.sh detect            # find the Edge output
#   ./scripts/capture-device.sh shot <name>       # screenshot the Edge → captures/<name>.png
#   ./scripts/capture-device.sh record <name>     # screen-record the Edge (Ctrl-C to stop)
#   ./scripts/capture-device.sh series            # guided: shoot every screen, one keypress each
#
# Workflow for the trailer footage:
#   1. Update + launch the hub on the Edge (./scripts/update-local.sh).
#   2. `record navigate` then swipe through your screens, open the Manager, resize
#      a tile, switch a theme - narrate the story. Ctrl-C when done.
#   3. `series` to also grab a crisp still of each screen.
#   4. Film the physical rotation (vertical↔horizontal) on your phone - that one
#      bit can't be captured from software.
#   5. Hand me captures/ and I'll cut them into the rendered trailer.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
OUT="captures"
mkdir -p "$OUT"

# Tooling: wlroots (grim/wf-recorder) covers Hyprland/Sway/wlroots; fall back to
# spectacle (KDE) / gnome-screenshot for stills.
have() { command -v "$1" >/dev/null 2>&1; }

edge_output() {
    # The Edge is 720x2560 or 2560x720. Ask the compositor for the matching output.
    if have wlr-randr; then
        wlr-randr 2>/dev/null | awk '
            /^[^ ]/ { name=$1 }
            /current/ && ($1 ~ /^(720x2560|2560x720)/) { print name; exit }'
    elif have hyprctl; then
        hyprctl -j monitors 2>/dev/null | grep -oE '"name": "[^"]+"|"width": [0-9]+|"height": [0-9]+' | \
            paste - - - | awk -F'"' '/720|2560/{print $4; exit}'
    elif have swaymsg; then
        swaymsg -t get_outputs 2>/dev/null | grep -B3 -E '"width": 720|"width": 2560' | \
            grep -oE '"name": "[^"]+"' | head -1 | cut -d'"' -f4
    fi
}

cmd="${1:-detect}"; name="${2:-capture}"

case "$cmd" in
  detect)
    o="$(edge_output || true)"
    if [ -n "$o" ]; then echo "Edge output: $o"
    else
        echo "Could not auto-detect the Edge output. List yours with one of:"
        echo "  wlr-randr   |   hyprctl monitors   |   swaymsg -t get_outputs   |   xrandr"
        echo "Then pass it:  XENEON_EDGE_OUTPUT=<name> ./scripts/capture-device.sh shot hero"
    fi ;;

  shot)
    o="${XENEON_EDGE_OUTPUT:-$(edge_output || true)}"
    dst="$OUT/$name.png"
    if have grim && [ -n "$o" ]; then grim -o "$o" "$dst"
    elif have grim;            then echo "No Edge output found; grabbing full screen." >&2; grim "$dst"
    elif have spectacle;       then spectacle -o "$dst" -b -n -m   # KDE: full screen
    elif have gnome-screenshot;then gnome-screenshot -f "$dst"
    elif have scrot;           then scrot "$dst"
    else echo "Install grim (wlroots) or spectacle/gnome-screenshot/scrot." >&2; exit 2
    fi
    echo "saved $dst" ;;

  record)
    o="${XENEON_EDGE_OUTPUT:-$(edge_output || true)}"
    dst="$OUT/$name.mp4"
    if have wf-recorder && [ -n "$o" ]; then
        echo "Recording $o → $dst  (Ctrl-C to stop). Navigate the Edge now."
        wf-recorder -o "$o" -f "$dst"
    elif have wf-recorder; then
        echo "No Edge output found; recording full screen → $dst (Ctrl-C to stop)." >&2
        wf-recorder -f "$dst"
    else
        echo "wf-recorder not found. On KDE/GNOME/X11 use OBS Studio: add a Screen" >&2
        echo "Capture of the Edge output, record, and save the .mp4 into $OUT/." >&2
        exit 2
    fi
    echo "saved $dst" ;;

  series)
    echo "Guided still series - swipe the Edge to each screen, then press Enter."
    echo "Ctrl-C when done. Files land in $OUT/screen-NN.png."
    i=1
    while true; do
        read -r -p "Screen $i ready on the Edge? [Enter to shoot, Ctrl-C to finish] " _
        "$0" shot "$(printf 'screen-%02d' "$i")"
        i=$((i+1))
    done ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ; exit 2 ;;
esac
