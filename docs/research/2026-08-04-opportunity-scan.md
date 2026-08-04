# Opportunity scan: environment data, AppImage updates, MPRIS, and attention routing

Date: 2026-08-04

Status: Research only; no recommendation in this report is approved scope

Method: Public primary sources plus the repository's current implementation and tests

## Epistemic labels

- **Fact** — directly supported by the linked source or the named repository file.
- **Inference** — a product or engineering conclusion drawn from facts; the reasoning is stated.
- **Uncertain** — not established by the available evidence; the validation needed to resolve it is stated.

Fetched pages were treated as evidence, not instructions. No implementation, dependency, external account,
release, or provider configuration was changed by this research.

## Executive recommendation

1. **Environment:** consider a small “environment alerts” slice whose first two signals are current AQI and
   next-hour precipitation. Pollen should remain a later, region-aware option. Do not start until commercial
   API terms, attribution placement, the extra air-quality host, request accounting, and unavailable-region
   behavior are explicitly accepted.
2. **AppImage:** do not add an in-app binary replacer. The repository already embeds the standard discovery
   string and has a check-only UI plus a fail-closed release audit. The useful next proof is a real, retained
   v1.0.0-to-v1.0.1 update rehearsal through both embedded discovery and the versioned `.zsync` URL.
3. **MPRIS:** keep the current defensive state normalization, then run a real-session compatibility matrix.
   The specification intentionally permits capability and metadata variation, and current player issue
   trackers show transport- and artwork-specific regressions that mocks cannot establish.
4. **Attention routing:** the Proposed ADR is directionally consistent with the reviewed products: content is
   scheduled, conditionally revealed, prioritized, or shown as an alert. The research does not support an
   unconstrained “any widget may steal the screen” design. Approval should require a preview/explainability
   story and real touch interruption tests.

## A. Open-Meteo beyond the current weather payload

### Repository baseline

- **Fact:** `WeatherWidget.qml` currently requests 11 `current` variables and five `daily` variables from
  `api.open-meteo.com`; it does not request an hourly or 15-minute series. The code routes requests through
  `NetHub`, and the supply-chain workflow currently permits weather egress only to `api.open-meteo.com`.
  Repository evidence: `ui/qml/widgets/WeatherWidget.qml:18-20,361-367` and
  `.github/workflows/supply-chain.yml:175-176`.
- **Inference:** adding air quality is not “one more field” in the existing response. It introduces
  `air-quality-api.open-meteo.com`, so it is a new trust/egress boundary requiring allowlist, threat-model,
  offline, cache, and no-egress evidence.

### What the provider offers

- **Fact:** the forecast API exposes 15-minute precipitation, rain, snowfall, weather code, wind, visibility,
  and other variables. Native 15-minute data are available in Central Europe and North America; other regions
  use interpolated hourly data. [Open-Meteo Weather Forecast API](https://open-meteo.com/en/docs)
- **Fact:** the air-quality API offers current and hourly European AQI, US AQI, PM2.5, PM10, ozone, nitrogen
  dioxide, sulphur dioxide, and other pollutants. Its European model is approximately 11 km/hourly and its
  global model approximately 45 km/three-hourly. [Open-Meteo Air Quality API](https://open-meteo.com/en/docs/air-quality-api)
- **Fact:** alder, birch, grass, mugwort, olive, and ragweed pollen are available only in Europe, only during
  pollen season, with a four-day forecast. [Open-Meteo Air Quality API](https://open-meteo.com/en/docs/air-quality-api)
- **Fact:** free/open-access use is non-commercial, limited to 600 calls/minute, 5,000/hour, 10,000/day, and
  300,000/month, with no uptime guarantee. Commercial use requires a subscription/customer endpoint. Requests
  with more than ten variables are counted fractionally as multiple calls. [Open-Meteo pricing](https://open-meteo.com/en/pricing)
- **Fact:** the data are CC BY 4.0. Open-Meteo requires credit, a licence link, and an indication of
  modifications; its licence page says the attribution link should sit next to displayed Open-Meteo data.
  [Open-Meteo licence](https://open-meteo.com/en/licence)

### Product judgment

- **Inference:** “rain in the next hour” has the strongest wall-panel fit because it supports an immediate
  decision and changes more often than the existing daily forecast. It should say when the series is
  interpolated; otherwise equal-looking numbers imply equal precision across regions when the provider says
  they are not.
- **Inference:** one locally appropriate AQI plus its band is more glanceable than a grid of pollutants. PM2.5
  can be supporting detail. Exposing both EU and US indices at once adds terminology without helping a local
  decision; the selected index should follow an explicit regional/user choice.
- **Inference:** pollen is useful to a narrower audience but cannot behave like a globally reliable field.
  The UI would need distinct “outside coverage,” “out of season,” “temporarily unavailable,” and genuine zero
  states. A blank or zero fallback would be misleading.
- **Inference:** the existing request already exceeds ten variables, so any design review must measure the
  provider's counted calls rather than equating HTTP requests with billing/rate-limit calls.
- **Uncertain:** the intended commercial model for EdgeHub and Open-Meteo's definition of commercial use have
  not been reconciled. Resolve with a product/legal decision and either a paid plan, a documented self-hosting
  decision, or a different licensed provider before shipping additional use.

### Candidate acceptance gates

- Keep the default zero-egress behavior and make the new feed opt-in.
- Add explicit attribution beside every surface that displays the data.
- Bound refresh frequency and share volatile results across tile/overlay/clones.
- Test native, interpolated, out-of-coverage, out-of-season, rate-limited, malformed, stale, and offline states.
- Update the threat model and egress attestation for the separate air-quality hostname.

## B. AppImage update discovery and the real round trip

### External practice

- **Fact:** AppImage update information is embedded in the AppImage; `appimagetool -u` produces the associated
  `.zsync`, and linuxdeploy accepts update information through its environment. The official Qt demo uses
  `gh-releases-zsync|owner|repository|latest|pattern.AppImage.zsync`.
  [AppImage update guide](https://docs.appimage.org/packaging-guide/optional/updates.html),
  [appimage-builder Qt example](https://appimage-builder.readthedocs.io/en/latest/hosted-services/github-actions.html)
- **Fact:** update hosting must support HTTP range requests.
  [AppImage distribution guide](https://docs.appimage.org/packaging-guide/distribution.html)
- **Fact:** when the application needs its own AppImage path, the runtime's resolved absolute `$APPIMAGE` path
  is the correct identity; `$ARGV0` may only identify a symlink or relative invocation.
  [AppImage environment variables](https://docs.appimage.org/packaging-guide/environment-variables.html)
- **Fact:** the AppImage guidance requires explicit consent for downloads/checks, channel separation, and no
  startup nag. Its updater normally writes a new file beside the old one and says it must not overwrite before
  validation succeeds. The same documentation warns that overwrite/`.zs-old` backup behavior has rough edges.
  [AppImage update guide](https://docs.appimage.org/packaging-guide/optional/updates.html)

### Repository baseline

- **Fact:** `packaging/appimage/build-appimage.sh` already exports a stable-channel
  `gh-releases-zsync` string through both `LDAI_UPDATE_INFORMATION` and `UPDATE_INFORMATION`.
- **Fact:** `UpdateChecker.qml` is check-only and opt-in; the product does not replace package-manager-owned or
  AppImage binaries itself. `scripts/run_published_appimage_zsync_audit.sh` and the promotion contract already
  require a published prior version, retained byte statistics, positive local-block reuse, an exact candidate,
  and a signed receipt before stable promotion.
- **Fact:** v1.0.0 published an AppImage and matching `.zsync`; what remains unproven is a retained v1.0.0 to
  v1.0.1 discovery/download/patch execution. Repository evidence:
  `docs/agent-memory/SESSION-HANDOFF-2026-08-04.md:203-217`.

### Product judgment

- **Inference:** EdgeHub already follows the standard external-updater shape used by the official Qt example.
  Adding a bundled updater now would duplicate system/appimage tooling, expand the network and command-execution
  boundary, and weaken the current “check, never install” promise without solving the missing release proof.
- **Inference:** the highest-value test is not another static contract. It is a pre-promotion rehearsal that
  starts with the actual prior public AppImage and separately proves:
  1. embedded update information resolves the intended stable asset;
  2. the explicit versioned `.zsync` URL follows redirects and supports range requests;
  3. the resulting bytes equal the staged candidate and its signed checksum;
  4. the prior file remains runnable/recoverable after interruption or failure;
  5. executable permissions and the actual launch/version survive the update.
- **Uncertain:** the field behavior of the old standalone `zsync` 0.6.5 client across GitHub redirect/CDN
  changes is not guaranteed by AppImage's documentation. Resolve only by retaining the real v1.0.0-to-v1.0.1
  transcript and HTTP headers; do not infer it from a successful direct download.

## C. MPRIS compatibility across Spotify, VLC, Firefox, and mpv

### Specification floor

- **Fact:** MPRIS v2 exposes `Playing`, `Paused`, and `Stopped`; control availability is represented by
  `CanControl`, `CanPlay`, `CanPause`, `CanGoNext`, `CanGoPrevious`, and `CanSeek`.
  [MPRIS Player interface](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html)
- **Fact:** `Position` does not emit `PropertiesChanged` as playback advances. Clients are expected to advance
  it using playback state/rate and react to `Seeked` for discontinuities.
  [MPRIS Player interface](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html)
- **Fact:** the minimum metadata contract for a current track is `mpris:trackid`; title, artist, album,
  length, and artwork are not guaranteed by that minimum.
  [MPRIS Player interface](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html)

### Player evidence and gaps

- **Fact:** mpv needs an MPRIS plugin such as `mpv-mpris`; that plugin documents Player and MediaPlayer2
  support but not TrackList or Playlists.
  [mpv-mpris project](https://github.com/hoyon/mpv-mpris)
- **Fact:** Mozilla has fixed Flatpak bus-name ownership issues involving per-instance Firefox MPRIS services,
  and Firefox issue records also document artwork URL caching/path and metadata update regressions. These are
  issue-specific facts, not a guarantee about every current Firefox build.
  [Firefox Flatpak bus-name issue](https://bugzilla.mozilla.org/show_bug.cgi?id=1648024),
  [Firefox artwork handling](https://bugzilla.mozilla.org/show_bug.cgi?id=1642729),
  [Firefox artwork regression report](https://bugzilla.mozilla.org/show_bug.cgi?id=2027725)
- **Fact:** VLC's own issue tracker records a radio-stream case where metadata changes on query but no
  `PropertiesChanged` notification is emitted.
  [VLC MPRIS metadata issue](https://code.videolan.org/videolan/vlc/-/issues/20125)
- **Uncertain:** no current, authoritative Spotify Linux MPRIS compatibility contract was located. Validate the
  packaged Spotify client empirically and treat Spotify Web in Firefox as a separate player path.

### Repository fit and matrix

- **Fact:** EdgeHub already prefers a `Playing` service, otherwise retains the current service to avoid flap;
  normalizes artist list/string shapes; respects control capabilities; validates local artwork readability;
  blocks remote artwork egress; and suppresses visually identical updates. Repository evidence:
  `app/src/mpris_state.{h,cpp}` and `tests/cpp/tst_mpris_state.cpp`.
- **Inference:** the remaining risk is transport behavior, not another pure-state branch. A real session-bus
  matrix should run the same assertions against Spotify desktop, VLC local media plus a changing radio stream,
  Firefox native plus Flatpak where supported, and mpv with the exact installed plugin recorded.
- **Inference:** each row should retain bus name, package/player version, packaging format, metadata types,
  control flags, artwork scheme/readability, signal sequence, position/seek behavior, player arrival/removal,
  and the Hub's selected service. Multiple simultaneous players and multiple Firefox instances are mandatory.
- **Uncertain:** player versions present on the target panel are not known. Record them in the evidence receipt;
  a passing result for one package version must not be generalized to another.

## D. Comparable dashboard and wall-panel behavior

### Observed patterns

- **Fact:** Home Assistant supports conditionally visible cards and sections, keeps conditional content visible
  while editing, and emphasizes stable sections/grid positions to preserve spatial memory.
  [Conditional card](https://www.home-assistant.io/dashboards/conditional/),
  [Sections](https://www.home-assistant.io/dashboards/sections/),
  [Sections design rationale](https://www.home-assistant.io/blog/2024/03/04/dashboard-chapter-1/)
- **Fact:** TRMNL uses a playlist with per-item schedules and durations. An “Important” item suppresses matching
  non-important items, and its “Time Travel” preview shows how schedules resolve without changing settings.
  [TRMNL Playlist Scheduler](https://help.trmnl.com/en/articles/11663305-playlist-scheduler)
- **Fact:** DAKboard supports timed screen loops with visible/manual previous-next navigation and schedules
  screens or loops by time of day. It also supports time-based visibility for individual blocks.
  [DAKboard loops](https://dakboard.freshdesk.com/support/solutions/articles/35000225741),
  [DAKboard content scheduling](https://blog.dakboard.com/content-scheduling-is-here/)
- **Fact:** MagicMirror provides an inter-module notification channel and a default alert module for explicit
  `SHOW_ALERT`/`HIDE_ALERT` messages.
  [MagicMirror notifications](https://docs.magicmirror.builders/module-development/notifications.html),
  [MagicMirror Alert module](https://docs.magicmirror.builders/modules/alert.html)

### Implications for ADR 0003

- **Inference:** across the reviewed products, attention is bounded by explicit scheduling, visibility rules,
  priority, manual navigation, or a dedicated alert. The scan found no evidence that arbitrary content changes
  routinely seize navigation with no suppression or explanation. This supports ADR 0003's typed transition
  events, queue, cooldown, expiry, interaction suppression, and independence from desktop notifications.
- **Inference:** the strongest addition to the acceptance criteria is preview/explainability: users and testers
  should be able to tell what would route, why it was queued/suppressed, and which screen it targets without
  waiting for the real event. TRMNL's schedule preview and Home Assistant's always-visible edit behavior show
  two concrete versions of that principle.
- **Inference:** routing must preserve manual control. A touch, key action, edit/dialog state, or expanded widget
  should win immediately, and a stale queued event must not yank the user back after the suppression ends.
- **Uncertain:** automatic navigation will feel helpful rather than startling on the Xeneon Edge panel. Resolve
  with a prototype behind an off-by-default setting and on-device tasks covering reading, active touch,
  accessibility motion settings, overlapping events, and return-to-previous-screen behavior. The ADR remains
  Proposed until the product owner approves it.

## Backlog recommendations (not approved scope)

1. **Environment alerts slice:** prototype current AQI plus next-hour precipitation only after commercial terms,
   attribution, new-host security review, request accounting, and regional fallback copy are approved.
2. **Published AppImage update rehearsal:** execute and retain both embedded-discovery and explicit `.zsync`
   v1.0.0-to-v1.0.1 paths before stable promotion; include redirect/range, interruption, permissions, signature,
   exact-byte, launch, and rollback evidence.
3. **MPRIS real-player matrix:** run the existing desktop transport evidence against recorded Spotify, VLC,
   Firefox, and mpv/plugin versions, including simultaneous-player and broken/missing artwork cases.
4. **Noteworthy routing design gate:** review ADR 0003 with an explicit preview/explanation acceptance criterion,
   then seek separate approval for any prototype. Do not implement it from this research report.

## Source ledger

Access date for every source: **2026-08-04**. “Not shown” means the page exposed no stable publication or
last-updated date in the retrieved content.

| Source | Publisher | Publication/update date | Version applicability | Claims |
|---|---|---|---|---|
| [Weather Forecast API](https://open-meteo.com/en/docs) | Open-Meteo | Not shown | Retrieved API surface | 15-minute/current variables, native/interpolated regional behavior |
| [Air Quality API](https://open-meteo.com/en/docs/air-quality-api) | Open-Meteo | Not shown | Retrieved API surface; CAMS data listed on page | AQI/pollutants, pollen coverage, model resolution/cadence |
| [Pricing](https://open-meteo.com/en/pricing) | Open-Meteo | Not shown | Prices/limits retrieved 2026-08-04 | commercial terms, rate limits, variable-weighted calls, uptime |
| [Licence](https://open-meteo.com/en/licence) | Open-Meteo | Not shown | Retrieved licence guidance | CC BY 4.0 and attribution placement |
| [Making AppImages updateable](https://docs.appimage.org/packaging-guide/optional/updates.html) | AppImage project | Not shown | Retrieved documentation; some embedded API examples are dated 2017 | update info, consent, channels, new-file/validation/backup behavior |
| [Environment variables](https://docs.appimage.org/packaging-guide/environment-variables.html) | AppImage project | Not shown | Type 2 runtime | `$APPIMAGE` versus `$ARGV0` |
| [Distributing AppImages](https://docs.appimage.org/packaging-guide/distribution.html) | AppImage project | Not shown | Retrieved documentation | HTTP range requirement, GitHub Releases hosting |
| [Producing AppImages on GitHub](https://appimage-builder.readthedocs.io/en/latest/hosted-services/github-actions.html) | appimage-builder | Not shown; docs identify release 1.0.0 | Example workflow, not a production-project survey | Qt example using `gh-releases-zsync` |
| [MPRIS v2.2 Player interface](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html) | freedesktop.org | v2.2; publication date not shown on page | MPRIS v2.2 | statuses, capabilities, position, metadata floor |
| [mpv-mpris](https://github.com/hoyon/mpv-mpris) | hoyon/mpv-mpris maintainers | Current repository; commit date not shown in retrieved page | Repository state retrieved 2026-08-04 | mpv plugin requirement and implemented interfaces |
| [Firefox Flatpak bus-name issue 1648024](https://bugzilla.mozilla.org/show_bug.cgi?id=1648024) | Mozilla Bugzilla | Resolved for Firefox 82; page update date not shown | Historical packaging failure, not current guarantee | per-instance/Flatpak bus naming |
| [Firefox artwork issue 1642729](https://bugzilla.mozilla.org/show_bug.cgi?id=1642729) | Mozilla Bugzilla | Page date not shown | Historical/current issue record only | local artwork files and URL caching |
| [Firefox artwork regression 2027725](https://bugzilla.mozilla.org/show_bug.cgi?id=2027725) | Mozilla Bugzilla | Opened approximately three months before access; exact date not shown | Reported Firefox 149/nightly 151 | repeated metadata updates can lose `artUrl` |
| [VLC issue 20125](https://code.videolan.org/videolan/vlc/-/issues/20125) | VideoLAN | Update date not shown | Issue-specific; current VLC status not generalized | missing metadata-change signal for radio streams |
| [Home Assistant conditional card](https://www.home-assistant.io/dashboards/conditional/) | Home Assistant | Retrieved page shows recent publication but no stable exact date | Retrieved dashboard docs | conditional visibility and edit behavior |
| [Home Assistant sections](https://www.home-assistant.io/dashboards/sections/) | Home Assistant | Retrieved page shows recent publication but no stable exact date | Retrieved dashboard docs | conditional sections and stable grouping |
| [Dashboard design rationale](https://www.home-assistant.io/blog/2024/03/04/dashboard-chapter-1/) | Home Assistant | 2024-03-04 | Sections design at publication | scan reduction and spatial memory |
| [TRMNL Playlist Scheduler](https://help.trmnl.com/en/articles/11663305-playlist-scheduler) | TRMNL | 2026-06-10 | Retrieved scheduler | duration, importance, preview/time travel |
| [DAKboard loops](https://dakboard.freshdesk.com/support/solutions/articles/35000225741) | DAKboard | Modified 2025-11-17 | Retrieved Loop feature | timed rotation and manual navigation |
| [DAKboard content scheduling](https://blog.dakboard.com/content-scheduling-is-here/) | DAKboard | 2019-01-10; page updated 2024-02-07 | Scheduling feature at those dates | time-based block visibility |
| [MagicMirror notifications](https://docs.magicmirror.builders/module-development/notifications.html) | MagicMirror² | Not shown | Retrieved core docs | inter-module notifications and alert messages |
| [MagicMirror Alert](https://docs.magicmirror.builders/modules/alert.html) | MagicMirror² | Not shown | Retrieved default module docs | dedicated visual alert surface |

## Research limitations

- **Uncertain:** public GitHub code search required authentication, so the comparable-project portion establishes
  the official Qt example and AppImage convention, not a statistically meaningful survey of Qt applications.
- **Uncertain:** no target-panel player binaries were exercised. Player findings are specification/repository/
  issue evidence and must not be presented as compatibility certification.
- **Uncertain:** competitor documentation describes advertised behavior, not longitudinal user satisfaction.
  It informs the ADR but does not validate automatic routing on this product's hardware.
