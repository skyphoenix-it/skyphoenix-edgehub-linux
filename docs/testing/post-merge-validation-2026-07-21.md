# Post-merge validation — 2026-07-21

## Outcome

The release-candidate implementation and embargoed marketing kit were merged to
`master` and pushed. Two failures then appeared in the remote checks. Both were
reproduced, fixed in the repository, and covered by local regression checks
before the corrective push.

This report complements the [real-hardware validation report](hardware-validation-2026-07-21.md).

## Findings and fixes

### F-09 — A new release-kit link escaped the local documentation check

- Status: fixed and verified locally.
- Symptom: the remote Docs workflow rejected the release-kit index because its
  link to the root `RELEASE_NOTES.md` was one directory too shallow.
- Cause: the link was wrong, and `check_doc_links.sh` inspected only files
  already tracked by Git. The marketing files were untracked when the local
  pre-commit check ran, so the check did not see them; CI saw them after commit.
- Fix: correct the relative link and make the checker inspect both tracked and
  untracked, non-ignored Markdown files.
- Regression proof: a deliberately broken untracked Markdown fixture now makes
  the checker fail and identify that file. After removing the fixture, the real
  repository passes with 112 relative links across 97 Markdown files.

### F-10 — GitHub CodeQL could not parse the QML JavaScript helpers

- Status: fixed and verified locally.
- Symptom: the default CodeQL workflow's JavaScript/TypeScript analyzer reported
  that it detected JavaScript but saw no processable source. All other configured
  analyzers passed.
- Cause: the repository's only two JavaScript sources began with QML's
  non-standard `.pragma library` directive. The files otherwise contain ordinary
  pure helper functions and do not need shared mutable library state.
- Fix: remove the directive from `tests/ui/fixtures.js` and
  `tests/gui/GuiUtil.js`, leaving their QML API and behavior unchanged.
- Regression proof: both files pass `node --check`; the complete 93-file QML
  suite passes; the 16-file nested-KWin GUI suite passes 1,311/1,311 checks with
  no failures or skips.

## Safety and traceability

- Final pre-commit release-tree backup:
  `/home/simon/IdeaProjects/.codex-backups/XeneonEdge_Linux/20260721T172611Z`.
- Marketing pre-commit backup:
  `/home/simon/IdeaProjects/.codex-backups/XeneonEdge_Linux/20260721T173138Z-marketing`.
- The attempted read-modify-write audit of GitHub default CodeQL configuration
  was rejected by the API before any change. The remote configuration remained
  unchanged; the fix is entirely in repository source.
- No release tag or public release was created. The marketing kit remains under
  its documented publication hold.

## Publication status

Merge readiness is complete. Publication readiness remains **not ready** until
the strict release gate, owner-issued Pro-key preflight, literal 48-hour soak,
candidate package lifecycle checks, updater round trip, and the business/legal
launch approvals in the [launch checklist](../marketing/release-kit/launch-checklist.md)
are complete.
