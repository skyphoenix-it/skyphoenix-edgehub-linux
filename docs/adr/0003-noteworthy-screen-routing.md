# ADR-0003: Route noteworthy widget events without stealing active touch context

**Status:** Proposed
**Date:** 2026-08-04
**Decision Maker:** Product owner
**Consulted:** Software architect, security/privacy reviewer, UI/UX reviewer

---

## Context

Idle page cycling lets otherwise unseen screens take turns, but it cannot know
when one screen has become more useful than the others. A timer expiring, a
scheduled event becoming imminent, or a monitored value crossing an explicitly
configured threshold can make a different screen worth showing now.

Routing attention is a cross-module concern. Individual widgets know when their
own state changes; the dashboard owns page selection and interaction state; and
the notification bridge owns desktop delivery. Letting widgets navigate the
dashboard directly would duplicate suppression rules and permit one noisy
widget to repeatedly take control of the display. Treating every warning-looking
snapshot as an event would also create alerts on startup and on ordinary metric
refreshes.

This decision defines the contract before implementation. It does not add a
configuration schema or ship the noteworthy-screen feature.

## Decision drivers

1. A touched or actively read screen must not move out from under the user.
2. Only explicit, actionable transitions may request attention.
3. A noisy source must not create an unbounded queue or navigation loop.
4. Existing widget, auto-cycle, and desktop-notification behavior must continue
   when the router is disabled or unavailable.
5. Medication reminders must remain generic and must not infer adherence or
   claim that a dose was missed.
6. The design must be testable without time-of-day, network, or desktop-service
   dependencies.

## Decision

Introduce a dashboard-owned attention router with a narrow event contract. A
widget or first-party adapter may publish an immutable `AttentionEvent` only
when an explicit state transition occurs:

| Field | Purpose |
|---|---|
| `id` | Unique event identity for acknowledgement and diagnostics |
| `sourceId` | Registered first-party widget instance or adapter |
| `screenId` | Destination screen resolved from the current layout |
| `severity` | `normal`, `high`, or `critical`, bounded by source policy |
| `occurredAt` | Monotonic ordering timestamp; never used as proof of freshness alone |
| `dedupeKey` | Stable key for coalescing repeated transitions |
| `action` | Optional registered in-app action identifier, never executable text |

The lifecycle is `pending -> visible -> acknowledged | expired`. Events are
volatile in the first implementation. After restart, widgets may publish a new
event only if their own authoritative state reports a new qualifying transition;
the router does not persist or reconstruct a history of alerts.

### Source policy

- Sources publish transitions, not periodically sampled warning snapshots.
- Each source has a documented maximum severity and expiry policy.
- Medication sources may publish a generic scheduled reminder. They may not
  infer or display “missed”, “overdue”, or adherence claims from lack of input.
- External strings are length-bounded and rendered as plain text. Events cannot
  contain URLs, commands, QML, or arbitrary callback objects.
- Desktop priority notification delivery remains an independent output. The
  existing ordinary `send()` fallback is retained for compatible bridges.

### Routing and suppression

The router may navigate only while the dashboard is eligible for automatic
movement. Eligibility reuses the auto-cycle interaction model and additionally
requires that no settings surface, editor, dialog, or expanded widget is active.
Any pointer, touch, hover, key, or focus interaction starts a grace period. An
event received during suppression remains pending until it expires or the
dashboard becomes eligible.

The router must:

- never navigate away from the source screen when it is already visible;
- never interrupt an active gesture, edit, dialog, or expanded widget;
- deduplicate by source and `dedupeKey` within a source-specific cooldown;
- keep a fixed-size queue, coalesce replaceable events, and prefer the newest
  event at the highest severity;
- enforce a minimum dwell after automatic navigation to prevent ping-pong;
- expire stale events and expose manual dismissal/acknowledgement;
- resolve `screenId` against the current layout immediately before navigation;
  events for deleted or empty screens expire without action.

Severity changes ordering, not the touch-safety rules. Even a `critical` event
does not steal the screen during active interaction. Desktop notification may
still provide the urgent channel.

### Failure behavior and observability

The router fails open for the existing dashboard: if it is disabled, unavailable,
or rejects a malformed event, widgets render normally, desktop notifications
continue, and idle page cycling keeps its current behavior. A stale action or
destination is discarded rather than guessed.

Diagnostics record fixed, non-content fields only: source type, severity,
decision (`shown`, `suppressed`, `deduplicated`, `expired`, `invalid`), and
coarse latency. Titles, task text, calendar content, medication labels, and
other personal content are never logged.

## Alternatives

### Let each widget navigate directly

Rejected. It duplicates interaction guards, creates conflicting timers, and
gives every widget authority over the global display.

### Derive importance from current widget warning state

Rejected. Startup hydration and repeated polling would look like new events,
creating false or repeated navigation.

### Always interrupt for critical events

Rejected. Severity is source-defined and cannot safely override a user who is
touching, editing, or reading the display. Priority desktop notifications are
the non-navigation escalation path.

### Persist the attention queue

Deferred. Persistence adds a schema, expiry across wall-clock changes, privacy
exposure, and migration/rollback work before the interaction model is proven.

## Consequences

- Widget adapters gain a small event-emission contract but no navigation API.
- The dashboard becomes the sole owner of event ordering, suppression, and page
  movement.
- First implementation can remain configuration-compatible and reversible.
- Events may be lost across process restart; this is accepted for the initial
  volatile design.
- A later persistence proposal requires a separate ADR and threat-model update.

## Validation and rollback

Before changing this ADR to Accepted and enabling the feature, tests must prove:

1. each source emits once for a qualifying transition and never for hydration,
   unchanged polling data, or a reversed transition;
2. touch, hover, keyboard focus, editing, dialogs, and expanded widgets suppress
   navigation through the full grace period;
3. deduplication, bounded queue capacity, cooldown, expiry, and minimum dwell
   prevent storms and page ping-pong;
4. layout deletion/reorder and Manager live-push cannot route to a stale screen;
5. priority ordering is deterministic and does not bypass suppression;
6. disabling or faulting the router preserves manual navigation, idle cycling,
   widget rendering, and both notification paths;
7. logs contain no event body or other personal widget content;
8. landscape and portrait touch flows pass the UI/UX review checklist with
   visual-regression evidence.

Each new guard requires a negative control that is demonstrated to fail when
the corresponding guard is removed.

Rollback is a feature-level disable that disconnects source publication from
the router and restores the current dashboard selection policy. Because the
initial design adds no persisted state, rollback needs no migration.

## Non-goals

- Automatically completing tasks, acknowledging reminders, or taking widget
  actions on the user's behalf.
- Inferring medical adherence or prioritizing one person's medication.
- Replacing desktop notifications.
- Ranking arbitrary third-party widget content.
- Implementing the feature in this decision-only change.
