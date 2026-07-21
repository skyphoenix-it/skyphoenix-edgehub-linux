# Email templates

## Release email

**Subject:** EdgeHub [VERSION] is available for the Xeneon Edge on Linux

**Preview text:** A native touch dashboard, 30 widgets, and live editing from
EdgeHub Manager.

Hello,

EdgeHub [VERSION] is now available for [VERIFIED_PLATFORM_SUMMARY].

EdgeHub turns the Corsair Xeneon Edge into swipeable, touch-first dashboard
pages. Choose from 30 first-party widgets and 19 preset screens, then arrange the
panel directly or edit it live from the companion desktop Manager.

Highlights:

- portrait and landscape layouts;
- live Manager-to-Hub editing, screen selection, resizing, and reorder;
- local configuration, no account, and no telemetry implementation;
- all widgets, presets, layout features, backgrounds, wallpapers, and the full
  Manager in Free;
- nine optional Pro colour themes.

Download [VERSION]: [DOWNLOAD_URL]

Read the release evidence and checksums: [RELEASE_EVIDENCE_URL]

Thank you to everyone who tested the real hardware, reported edge cases, and
helped make the release gates fail visibly.

— SKYPhoenix IT

EdgeHub is independent and is not affiliated with, sponsored by or endorsed by
Corsair.

## Contributor/tester thank-you

**Subject:** Thank you for helping test EdgeHub [VERSION]

Hello,

EdgeHub [VERSION] has been published, and your testing helped close the gap
between “the UI opens” and “the real Hub, Manager, touch panel, reconnect path,
and release artifacts work together.”

The final evidence is here: [RELEASE_EVIDENCE_URL]

If you have the release installed, the most useful follow-up feedback is:

- [REQUESTED_FEEDBACK_SCOPE]
- exact distro, desktop, session type, and display orientation;
- logs and reproduction steps with personal data removed.

Thank you,

SKYPhoenix IT

## Hold/update email (safe before release)

**Subject:** EdgeHub release update: integration green, publication gate still open

Hello,

The current EdgeHub development branch has completed its real Xeneon Edge and
Manager/Hub integration pass. It is not published as a new release yet.

The remaining release work is tracked at [PROJECT_STATUS_URL], including the
strict immutable-candidate gate, native package lifecycle, performance limits,
long hardware soak, published update round trip, and legal/business review.

We will send release links only after those checks are complete.
