# Marketing launch checklist

The checklist is fail-closed: an unchecked blocking item means the launch copy
remains internal.

**Accepted-risk decision (2026-07-21):** the release owner waived the 48-hour
soak and formal performance limits for beta.1. No stability-duration or
performance-number claim is permitted. Only signed source and portable x86-64
tarballs are advertised.

## 1. Release identity and evidence - blocking

- [ ] The signed tag exists and identifies the exact commit under test.
- [ ] `scripts/run_release_tests.sh` passed with no failure, skip, ignored test,
      expected failure, or compatibility exception.
- [x] The 48-hour soak is explicitly waived; no long-soak claim is present.
- [x] Performance numbers are omitted; no formal performance claim is present.
- [ ] The real owner-issued Pro key passed against the shipped issuer key.
- [ ] Coverage met the strict Rust, C++, merged, and QML gates.
- [ ] Real Edge, Manager/Hub, display lifecycle, touch, reconnect, and suspend
      evidence belongs to the exact candidate.
- [ ] Release notes no longer contain the development hold.

## 2. Artifacts and install lifecycle - blocking

- [ ] Every advertised artifact is uploaded and its SHA-256/signature verifies.
- [ ] Each advertised package completed clean install, upgrade, uninstall, and
      reinstall on its named platform.
- [ ] Both binaries report `v1.0.0-beta.1` from the published payload.
- [x] AppImage is not advertised for beta.1.
- [x] zsync/delta update is not advertised for beta.1.
- [ ] Download links were tested from a clean consumer environment.
- [ ] Rollback/recovery instructions are documented.

## 3. Product and business claims - blocking

- [ ] Catalog counts were regenerated from the exact candidate.
- [ ] Supported distro/desktop/session wording matches completed evidence.
- [ ] Default theme, font, and motion choices are approved.
- [ ] Inspired theme names and palettes passed legal/trademark review.
- [ ] If Pro is sold, provider, product, price, tax, delivery, key recovery,
      refund, privacy, and support paths are live and tested.
- [x] Pro is not sold and every selected draft says keys are unavailable.
- [ ] Required Corsair independence disclaimer was approved.

## 4. Copy review - blocking

- [ ] `rg -n '\[[A-Z][A-Z0-9_ -]*\]' docs/marketing/release-kit` returns no
      unresolved publication placeholder in selected assets.
- [ ] No draft claims broad platform support, auto-update, stability duration,
      price, refund, support SLA, or performance without linked evidence.
- [ ] Free-vs-Pro copy matches the shipped gate exactly.
- [ ] Links, anchors, dates, version strings, and contact routes were checked.
- [ ] Spelling, capitalization, product naming, and legal wording are consistent.
- [ ] Release announcement, website, store, email, and social copy agree.

## 5. Visual review - blocking

- [ ] All launch visuals were recaptured from the exact candidate.
- [ ] Version, commit, binary hashes, platform, and config are recorded for each.
- [ ] No secret, licence key, private URL, hostname, note, task, or personal data
      is visible.
- [ ] Captures show real behavior and are not synthetic UI mockups.
- [ ] Alt text, captions, transcript, contrast, and reduced-motion needs are met.
- [ ] No Corsair logo or trade dress is used in designed campaign assets.

## 6. Channel execution

- [ ] GitHub release and checksums are public.
- [ ] Documentation and evidence pages are deployed.
- [ ] Primary download link resolves before announcements are sent.
- [ ] Website hero and release page are updated.
- [ ] Email is scheduled only after the download verification.
- [ ] Social/community posts use channel-appropriate copy and one primary CTA.
- [ ] Maintainer is available for the first support window.
- [ ] Known issues and response templates are ready.

## 7. Post-launch

- [ ] Verify downloads, signatures, and install instructions again after publish.
- [ ] Monitor crash/issues without collecting telemetry.
- [ ] Record recurring support questions for documentation fixes.
- [ ] Publish corrections visibly if a claim or artifact is wrong.
- [ ] Archive final copy, captures, evidence, and checksums with the release tag.
