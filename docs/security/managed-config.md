# Managed / org-policy configuration (E9)

A read-only policy file layered over the user's `config.toml`. It lets an
organization pin the hub's security-relevant surfaces machine-wide: force a
layout preset, hold the network kill switch on, pin the egress host allowlist,
and disable widget types (including the command/egress primitives) org-wide.

Without a policy file the hub behaves **byte-for-byte** as an unmanaged
install - the default-config no-egress attestation run is unaffected.

## The file

```
/etc/xeneon-edge-hub/policy.toml
```

Owned by root, writable by root only. That filesystem fact - not application
logic - is what makes the policy user-tamper-proof: the hub runs as the user
and only ever *reads* this file.

```toml
# All fields except policy_version are optional.
policy_version = 1                      # REQUIRED. This build understands 1.

# Lock the dashboard layout to a preset id (see ui/qml/PresetCatalog.qml,
# e.g. "remote-work", "minimal", "productivity"). While locked, the user's own
# saved layout is never overwritten, session edits to the layout do not
# persist, and a companion-Manager push over IPC is refused.
force_preset = "remote-work"

# Pin NetHub's kill switch ON: no remote egress at all, from any widget.
# Local file:/qrc:/relative reads still work - they are not egress.
net_offline = false

# Pin NetHub's host allowlist. Non-empty = only these hosts may be reached;
# user config cannot widen the list. NOTE: an EMPTY list means "no pin"
# (NetHub's vocabulary: empty = allow any host). To forbid all hosts, use
# net_offline = true instead - it dominates the allowlist.
allowed_hosts = ["api.internal.example", "metrics.internal.example"]

# Pin the user-widget loader flag off (E3): only first-party, shipped widgets.
disable_user_widgets = true

# Widget types hidden from the add-picker and never rendered. A stored tile of
# a disabled type shows the neutral "unavailable" card instead of the widget.
disable_widget_types = ["httpjson", "kpi"]
```

Unknown keys are **rejected** (the whole file then fails closed, see below):
with lenient parsing, a misspelled `allowed_host = [...]` would silently load
as a policy with *no* allowlist - strictly weaker than the org wrote.

## Fail-closed semantics

| File state | Result |
|---|---|
| No file | No policy. Unmanaged behaviour, byte-for-byte. |
| Valid file, `policy_version = 1` | The policy applies as written. |
| Exists but unreadable / unparseable / unknown key / other `policy_version` | **Fail closed**: `net_offline = true`, `disable_user_widgets = true`. |
| Cannot even determine existence (e.g. unreadable policy directory) | **Fail closed**, same interpretation. |

Rationale: an org that installed a policy file *intended* the machine to be
managed. Silently ignoring a corrupt policy would turn a typo into an
unmanaged workstation, so the unusable-file case applies the most restrictive
interpretation of the dangerous fields. The remaining fields stay at their
defaults deliberately:

- `force_preset` → none: we cannot guess a preset id, and layout is a
  usability surface, not a security one.
- `allowed_hosts` → empty: with the kill switch pinned on there is no egress
  for a list to constrain. (Empty is only safe *because* `net_offline`
  dominates it.)
- `disable_widget_types` → empty: we cannot guess type names, and every
  shipped widget's egress already routes through the NetHub gate, which the
  pinned kill switch closes.

The failure is loud: the reason is logged and surfaced as
`source: "fail-closed"` with a `reason` on the policy object (Diagnostics can
show it), so a mis-deployed policy is noticed and fixed rather than silently
"working".

## What each field enforces, and where

- **`net_offline`** - `Dashboard.qml` pins the app-global `NetHub.offline`
  property: when the policy sets it, the binding returns `true` regardless of
  the user's own appearance flag. Every widget's egress goes through
  `NetHub.request()` (an egress lint in CI forbids raw `XMLHttpRequest`
  anywhere else), so the pin closes all remote traffic. This is the change
  that turns `NetHub.allowHosts`/`offline` from *advisory* (previously set
  only by config the user can edit) into *enforceable* - and therefore turns
  the no-egress attestation from "proves behaviour on this run" into "proves
  configured policy".
- **`allowed_hosts`** - `Dashboard.qml` binds `NetHub.allowHosts` to the
  policy list. No user-config path assigns that property, so the binding is
  the pin.
- **`force_preset`** - `DashboardStore.lockToPreset()` seeds the layout from
  the preset and, while locked: every disk write is suppressed (the user's own
  layout under `~/.config` survives untouched - removing the policy restores
  it), and `applyExternal()` (the companion Manager's IPC push) is refused.
  Session-local edits are possible but evaporate on restart. An unknown preset
  id degrades to a locked default layout, never to an unlocked one.
- **`disable_widget_types`** - the add-picker filters these types out (hidden,
  not greyed), the tile loader never instantiates them (stored tiles render
  the neutral "unavailable" card), and the expanded overlay refuses them.
- **`disable_user_widgets`** - exposed on the policy object
  (`disableUserWidgets`) for the E3 user-widget loader to consume; the loader
  itself is owned by that epic.

The Dashboard also shows one always-visible line in the bottom bar while a
policy is active: **"Managed by your organization."**

## Threat model - what is and is NOT guaranteed

**In scope:** a managed workstation where the organization controls the
session - installs the (unmodified, packaged) hub, owns `/etc`, and provisions
the login environment. Under that model, the shipped hub honours the pins
above, and the attestation counters in Diagnostics reflect a policy the user
cannot edit away in `config.toml`.

**Out of scope (stated plainly):**

- **The environment override.** `XENEON_POLICY_PATH` redirects the policy
  path. It exists **for tests only**, so the suite never touches the real
  `/etc`. A user who controls their own environment can point it at a
  permissive file (or at nothing) and bypass the policy entirely. A real
  deployment therefore relies on `/etc` being root-owned **and** on the org
  controlling the session environment (display-manager/systemd-provisioned
  sessions do not inherit arbitrary user variables into autostarted apps -
  but a user-launched shell does). If your deployment cannot control the
  session environment, this policy is a guardrail, not a boundary.
- **A hostile local user with tooling.** Anyone who can `LD_PRELOAD`, patch
  the binary, build their own hub from source, or simply run a different
  program can make any network request they like. This feature is managed
  configuration, not DRM and not an OS-level egress firewall. Orgs that need
  a hard boundary should pair the policy with network-level controls; the
  policy then keeps the *hub* honest and the firewall keeps the *machine*
  honest.
- **Per-request allowlists inside the gate.** `NetHub.request()` accepts a
  per-request `opts.allow` list which takes precedence over the pinned global
  list. No shipped widget passes it (verified; the egress lint keeps all
  egress inside NetHub), but a future widget could - treat `opts.allow` as
  forbidden in managed contexts until NetHub intersects it with the policy
  list rather than replacing it.
- **Live re-read.** The policy is read once at startup (it is root-owned and
  static per launch). Changing the file takes effect on the next hub start.

## Test seam

Rust, C++ and QML tests drive the loader exclusively through
`XENEON_POLICY_PATH` pointed at temp files - nothing in the test suite reads
or writes the real `/etc`. See `core/src/policy.rs` (unit tests),
`tests/cpp/tst_policy.cpp` (ConfigBridge + FFI) and
`tests/ui/tst_policy_qml.qml` (Dashboard enforcement).
