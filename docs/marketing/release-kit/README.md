# EdgeHub release campaign kit

**Status:** internal pre-publication material

**Working target:** the next release after `v1.0.0-alpha.2` (currently expected
to be `v1.0.0-beta.1`, but no beta tag exists yet)

**Publication rule:** do not publish any file in this directory until the exact
signed candidate passes the strict release gate and every placeholder is
replaced with verified release data.

This kit turns the repository's approved claim register into reusable launch
material without pretending that the current development branch is already a
release. It deliberately contains no price, store, broad-platform,
self-update, performance, or long-soak promise.

## Contents

- [`campaign-brief.md`](campaign-brief.md) — positioning, audience, message
  hierarchy, tone, and approved proof points.
- [`release-announcement.md`](release-announcement.md) — long-form release post
  for the project site or GitHub release discussion.
- [`social-copy.md`](social-copy.md) — short and long social variants, plus
  community-specific drafts.
- [`email.md`](email.md) — launch and contributor email templates.
- [`press-kit.md`](press-kit.md) — factual boilerplate, FAQ, credits, and media
  notes.
- [`demo-script.md`](demo-script.md) — a 60-second product demo shot list using
  real hardware and the exact candidate.
- [`asset-plan.md`](asset-plan.md) — approved existing visual references,
  required recaptures, crop guidance, and alt text.
- [`launch-checklist.md`](launch-checklist.md) — fail-closed review and channel
  checklist.

## Required replacements

Search this directory for square-bracket placeholders before publication:

```sh
rg -n '\[[A-Z][A-Z0-9_ -]*\]' docs/marketing/release-kit
```

At minimum, the final pass must replace `[VERSION]`, `[RELEASE_DATE]`,
`[DOWNLOAD_URL]`, `[RELEASE_URL]`, `[SUPPORTED_PACKAGES]`, `[SUPPORT_URL]`, and
`[CONTACT]`.

## Claim sources

The source of truth is:

- [`../../MARKETING.md`](../../MARKETING.md) for allowed and prohibited claims;
- [`../../BETA_PLAN.md`](../../BETA_PLAN.md) for release blockers;
- [`../../../RELEASE_NOTES.md`](../../../RELEASE_NOTES.md) for the publication hold;
- [`../free-vs-pro.md`](../free-vs-pro.md) for entitlement details;
- [`../../testing/release-gate.md`](../../testing/release-gate.md) for the final
  verification process.

If the code, evidence, or business terms change, update the claim register first
and regenerate the affected copy from it.
