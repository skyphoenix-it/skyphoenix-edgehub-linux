# Release media validation, 2026-07-21

## Result

**PASS.** The beta.1 marketing video and launch stills show real output from the
exact signed portable candidate. The physical display baseline was restored and
verified after capture. The normal Hub configuration was not overwritten during
cleanup because its timestamp and content had changed outside the isolated
capture state.

## Candidate identity

| Item | Verified value |
|---|---|
| Tag | `v1.0.0-beta.1` |
| Commit | `009f2892d2c9426dc19d2fa25c3ad86611820ae0` |
| Hub version | `1.0.0-beta.1` |
| Manager version | `1.0.0-beta.1` |
| Hub binary SHA-256 | `6663d80961fafa84a81f270fefe4b6668df4df85a8ff9ea4e9bc7c6169d80b86` |
| Manager binary SHA-256 | `66213bf7d535b52042df9119b303e308e8a15abcff5fe5036e21103727e32eac` |
| Portable payload SHA-256 | `39d812a31e1f6aa948f46604adb6744703379deceafadb83ae73488b57e23313` |

## Capture environment and controls

- KDE Plasma on Wayland, captured through Spectacle and compositor APIs.
- Physical Edge output: `DP-3`.
- Baseline: `720x2560` logical, right rotation, position `5120,2880`.
- Hub and Manager used isolated temporary `XDG_CONFIG_HOME` and runtime paths.
- The normal Hub configuration was backed up with SHA-256
  `05221f282de252f1568a5e59728a47cbc43cd08042b00c88c8d8fbfc205ffd8a`.
  It was later observed at SHA-256
  `efc68511175a2a75d0dff9c07819441e44c8a9811fbe2cbbc2fbacef99817daa`
  with an earlier external modification time. Cleanup preserved the newer live
  file instead of replacing it with the backup.
- Physical orientation was changed through KScreen, verified in landscape, and
  restored to the exact baseline in a `finally` path.
- Full-desktop capture frames were private temporary files. They were cropped
  immediately to the target application or output and then removed.
- A rejected Manager crop that included the desktop underneath was not used. Its
  four derived images and stale manifest were moved to the desktop Trash and are
  recoverable there.
- The capture helper refuses to operate without explicit marketing-capture and
  physical-display opt-ins, validates the candidate version, and proves that the
  Manager is frontmost before taking Manager frames.

## Behavior shown

Two guarded exact-candidate integration sequences passed:

1. Manager reflection: 8/8 checks. Screen state, light and matrix themes,
   portrait preview, landscape preview, and matched Hub landscape were visible.
2. Manager-to-Hub screen mirror: 8/8 checks. Real Manager input selected pages
   2, 0, 3, and 1; the physical Hub reported the same pages. Adding a fifth
   screen selected new page 4 on the Hub and the Hub remained alive.

Portrait and landscape Hub heroes were captured from the physical output. The
landscape frame uses KScreen rotation with Hub orientation set to `auto`, which
avoids double rotation and demonstrates the shipped reflow behavior.

## Published media

The feature tour is an edited sequence of verified real product captures, not a
continuous raw screen recording. Slow zooms, fades, captions, and an end card are
editorial additions. No synthetic UI, pointer simulation, fake product state,
or fabricated performance data is presented as live behavior.

| Asset | Value |
|---|---|
| Video | `edgehub-v1.0.0-beta.1-feature-tour.mp4` |
| Format | H.264 MP4, 1920x1080, 30 fps, AAC stereo at 48 kHz |
| Duration | 52 seconds |
| SHA-256 | `2b4a7228da7f437bdd0343074254fecd52f153e0affcd8197cd3b219cbec5d26` |
| Captions | `docs/marketing/release-kit/video-captions.vtt` |
| Asset hashes | `docs/marketing-site/assets/release/v1.0.0-beta.1/SHA256SUMS` |

The website hero, social landscape, social square, video thumbnail, native Hub
captures, and Manager captures are derived from those verified frames. Designed
campaign assets avoid third-party logos and include the independent-project
disclaimer where legal context is needed.

## Manager theme and accent expansion

The additional Manager gallery is exact-candidate rendering, but it is not
physical-hardware evidence. To guarantee that the Manager never opens on the
physical Edge, `scripts/capture_manager_themes.py` runs the signed beta.1 Manager
inside a private 1920x1080 Xvfb display. It restarts the Manager with an isolated
configuration for each frame and emits no pointer or keyboard input.

- 20/20 themes included in Free captured and labeled.
- 10/10 representative accent colours captured on a fixed Nord base.
- Exact Manager SHA-256:
  `66213bf7d535b52042df9119b303e308e8a15abcff5fe5036e21103727e32eac`.
- Exact tag commit:
  `009f2892d2c9426dc19d2fa25c3ad86611820ae0`.
- Theme reel: H.264, 1920x1080, 30 fps, AAC stereo at 48 kHz, 45 seconds.
- Theme reel SHA-256:
  `c627ac868be7d21d299ca03d5f7d06e25f07a64dd3b36c538017bd9028ebc9f2`.
- Theme sheet SHA-256:
  `e0efd7a08dda8f93c2c3c96ff99f6bc1254b41d902f38ac7f9df0ad989696424`.
- Accent sheet SHA-256:
  `883662204eccdd1463a1979f02d5d1c26b2a2da5af44af9bf8cbc08510bc73c5`.

The first physical-display gallery attempt was stopped because the Manager was
not proven on a desktop monitor. Its rejected crop was moved to the desktop
Trash. No physical-display Manager frame from that attempt is published.

Both videos use audio produced locally by
`scripts/render_original_soundtrack.sh`. The soundtrack contains no external
recording or sample. Its construction and reuse grant are documented in
`docs/marketing/release-kit/original-soundtrack.md`.

## Live product behavior film continuity revision

The primary 70.7-second product film uses the exact signed beta.1 Hub and
Manager binaries listed above. The applications ran on two private Xvfb
displays with isolated configuration and runtime directories. The Hub used a
portrait-native 720x2560 surface, transposed into its front-facing 2560x720 view
where required for the edit. This keeps the Manager preview and side-by-side Hub
in matching orientations.

The synchronized take records real Manager input for page selection, screen
creation, widget insertion, a two-column layout change, Aurora theme selection,
Manager dark mode, purple accent selection, the Device panel, and the automatic
update preference. A second synchronized take uses real Manager mouse input to
select portrait orientation, open the portrait Manager preview, select
landscape orientation, and open the landscape Manager preview. The running Hub
responds over the real local control socket in both takes. No physical display
or physical input was used for either take.

The rounded display bezel and desktop monitor are unbranded SVG presentation
frames. The Hub frame is a front view without a stand or foot. The camera moves
and the 1.5-second eased landscape-to-portrait turn are editorial animation.
Every pixel inside the Hub and Manager apertures comes from the synchronized
application recordings.

The opening camera push and Manager reveal are spatially supersampled at
7680x4320 before final 1080p output. This removes the whole-pixel stepping that
made the bezel appear to shake in the first render and keeps the pullback on one
continuous camera path. Tracking the left bezel across the opening reduced
frame-to-frame velocity deviation from 0.8543 to 0.2441 pixels and acceleration
RMS from 1.3720 to 0.4010 pixels. Marketing headlines use alpha crossfades
instead of hard cuts.

| Item | SHA-256 or verified value |
|---|---|
| Landscape Hub recording | `d8e68f3d4aa0573622ef4d2a6363e0225bc61527bfbdb209f942cdbdba17dafc` |
| Manager recording | `20200480096062607fe2383c9ed063a84ce478a404aa2c5822937161abb63c66` |
| Capture manifest | `68634392160802cd309b74e9e223b5a0f3c1a76311fe8a2ce65f2ae9e310d1fc` |
| Portrait Hub recording | `c48ca70f678c8e9e70c4849680a4f89c1026d7780cef88c3cbd6d196be891fdc` |
| Portrait manifest | `421517c5cfb43acfa0552039a2efbca152f74db3c70a5e2b16b47d05ab9fee57` |
| Orientation Hub recording | `2f6f5d7d039c9f8a16f410823ec93a9b510346923af721ba1a7fe7ec1730a65e` |
| Orientation Manager recording | `0474a4c6f498b000d31597424a02c8e66d4b9f15820ef2bddf0c5cda1a0200d9` |
| Orientation manifest | `32c8f2619d4f5cd9dc3ad4f98a0e9856749ec7a10063d2ec1ebcd002382c9966` |
| Final MP4 | `97922adc6b5408d280a5cedcc5574708f9f68ed2d09b80829ee0c5a4cbbbbf4e` |
| Thumbnail | `6611de07f9fde51156b6e599f48cce87c3f1cbaca6e4cde301fe621011ca9356` |
| Format | H.264 1920x1080 at 30 fps, AAC stereo at 48 kHz |
| Duration | 70.700 seconds |

The film is reproduced by `scripts/capture_live_behavior.py`,
`scripts/capture_live_portrait.py`, `scripts/capture_live_orientation.py`, and
`scripts/render_product_film.sh`. Its music is generated locally by
`scripts/render_original_soundtrack.sh` with no third-party recording or
sample. The closing tested-platform line is limited to the verified release
environment: CachyOS, based on Arch Linux, with KDE Plasma on Wayland. The film
uses the project's own product icon and SKYPhoenix IT mark, and no third-party
distro logo.

## Reproduction

Use `scripts/capture_release_media.py` to perform a guarded physical-candidate
capture and `scripts/render_release_video.sh` to render the final tour. Use
`scripts/capture_manager_themes.py` and
`scripts/render_manager_theme_showcase.sh` for the virtual Manager gallery. The
capture helpers must never be used to bypass the repository's synthetic-input
activity guard.
