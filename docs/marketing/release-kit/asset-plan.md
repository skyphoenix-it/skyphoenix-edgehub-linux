# Release asset plan

## Principle

Release visuals must show the exact candidate. Existing repository images are
useful composition references, but they are not automatically approved release
assets and must not be used as proof of platform or artifact readiness.

No new synthetic product UI is required. Real captures are both more credible
and easier to audit against the shipped build.

## Existing composition references

| Repository asset | Intended use after recapture/verification | Suggested alt text |
|---|---|---|
| [`hero-system.png`](../../marketing-site/assets/generated/hero-system.png) | Portrait Hub hero reference | “EdgeHub system dashboard in portrait orientation with live metric widgets.” |
| [`system-landscape.png`](../../marketing-site/assets/generated/system-landscape.png) | Landscape Hub hero reference | “EdgeHub system dashboard arranged across a wide landscape panel.” |
| [`manager-layout.png`](../../marketing-site/assets/generated/manager-layout.png) | Manager layout feature reference | “EdgeHub Manager editing a multi-widget dashboard layout.” |
| [`manager-appearance-pro.png`](../../marketing-site/assets/generated/manager-appearance-pro.png) | Appearance/Free-vs-Pro reference, only after terms are live | “EdgeHub Manager appearance controls with theme choices and a live panel preview.” |
| [`calm-focus.png`](../../marketing-site/assets/generated/calm-focus.png) | Productivity/focus campaign reference | “A calm EdgeHub focus dashboard with time and task widgets.” |
| [`health-aurora.png`](../../marketing-site/assets/generated/health-aurora.png) | Health/routine campaign reference | “An EdgeHub health dashboard with hydration and routine widgets.” |

## Required exact-candidate captures

1. Portrait Hub hero on the physical Edge.
2. Landscape Hub hero on the physical Edge.
3. Manager Layout with the same dashboard mirrored on the Hub.
4. Manager Appearance with a Free theme selected.
5. Touch navigation sequence showing a real page swipe.
6. Manager add, resize, and drag-reorder sequence with the Hub visible.
7. Optional Pro theme sheet only after store/licence delivery and legal review.

Every capture must record:

- tag and full commit;
- Hub and Manager `--version` output;
- SHA-256 of both binaries;
- capture date and platform/session;
- whether the frame is a screenshot, photograph, or video still;
- the temporary configuration used;
- confirmation that no licence key, private URL, token, hostname, or personal
  task/note text is visible.

## Deliverable matrix

| Asset | Canvas | Safe composition |
|---|---:|---|
| Website hero | 2400×1350 | Product on one side, clean negative space for HTML text; no baked-in headline |
| Social landscape | 1600×900 | Hub + Manager relationship, central safe area for channel crops |
| Social square | 1200×1200 | One verified screen, large margins, no tiny UI text relied upon |
| Social portrait | 1080×1350 | Physical Edge or portrait Hub capture, subject inside 4:5 safe area |
| Press screenshot | Native resolution | Uncropped exact-candidate capture with descriptive filename |
| Demo thumbnail | 1280×720 | Real panel and Manager; headline added in editable layout, not generated into UI |

## File naming

Use:

```text
edgehub-v1.0.0-beta.1-[surface]-[orientation]-[purpose]-[01].png
```

Examples:

```text
edgehub-1.0.0-beta.1-hub-landscape-hero-01.png
edgehub-1.0.0-beta.1-manager-landscape-layout-01.png
```

## Visual direction

- Lead with the product's real deep-neutral UI and cyan/blue accent range.
- Keep surrounding layouts calm and low-clutter.
- Do not imitate Corsair product packaging, logos, type, or trade dress.
- Do not render fake performance charts or results.
- Do not bake long copy into raster images; keep text in HTML or editable source.
- Preserve legibility of UI captures and avoid aggressive perspective warps.

## Accessibility

- Provide meaningful alt text; do not repeat the caption verbatim.
- Maintain at least 4.5:1 contrast for overlaid body text.
- Include captions/transcript for video.
- Avoid rapid cuts, flashes, and essential information conveyed by color alone.
- Export a reduced-motion version of any animated web hero.
