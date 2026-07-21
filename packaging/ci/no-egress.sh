#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The verifiable no-egress attestation.
#
# Turns "the hub has no telemetry" from a claim into a re-runnable measurement.
# It launches the REAL hub binary in a network namespace and records every
# outbound attempt, then asserts the set of hosts it reached is exactly the set
# expected for that configuration:
#
#   no-egress.sh default                       -> asserts ZERO egress
#   no-egress.sh seeded                        -> asserts ZERO egress (post-wizard default layout)
#   no-egress.sh weather api.open-meteo.com    -> asserts egress ONLY to that host, and that it happened
#   no-egress.sh url:<URL> [hosts...]          -> negative control / arbitrary widget
#
# HOW IT OBSERVES - two independent channels, because either alone has a hole:
#
#   1. strace -f -e trace=connect  - ground truth. Records every connect(2) the
#      process tree makes, whether or not it resolves, routes, or completes.
#      This is the channel that catches egress to a HARD-CODED IP, which never
#      asks DNS and so would leave no trace in channel 2.
#   2. A loopback DNS + TCP sink (egress_sink.py) - attribution. connect(2) to
#      127.0.0.1 does not say WHICH host was wanted; the DNS QNAME does.
#
# WHY A NAMESPACE AND A SINK, not just `unshare -n`: under a bare `unshare -n`
# a phone-home fails at DNS resolution, before connect(2) - so there is nothing
# to observe and the test passes for the wrong reason. The namespace is the
# containment (nothing can truly leave); the sink is what makes the attempt
# observable. Neither is the assertion on its own.
#
# The namespace is entered with --map-root-user, so this needs NO real
# privilege: it works unprivileged wherever unprivileged user namespaces are
# enabled, and under sudo where they are not (Ubuntu 24.04's AppArmor restricts
# them, which is why CI runs it under sudo).
#
# Exit: 0 pass, 1 fail (assertion or setup), 77 skip (no hub binary).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# ── inner: runs INSIDE the new network + mount namespace ─────────────────────
if [ "${1:-}" = "__inner" ]; then
    shift
    RUNDIR="$1"; MODE="$2"; URL="$3"; HUB="$4"; STRACE="$5"; SECS="$6"
    LOGS="$RUNDIR/logs"

    ip link set lo up || { echo "FAIL: cannot bring up lo in the namespace"; exit 1; }

    # Point the resolver at the sink. Both files matter: resolv.conf alone is not
    # enough because glibc consults nsswitch.conf first, and a host whose
    # `hosts:` line routes to systemd-resolved would answer over a UNIX socket -
    # which a network namespace does NOT block. That would resolve real public
    # IPs, bypass the sink, and lose the hostname attribution entirely.
    printf 'nameserver 127.0.0.1\noptions timeout:1 attempts:1\n' > "$RUNDIR/resolv.conf"
    printf 'hosts: files dns\n' > "$RUNDIR/nsswitch.conf"
    mount --bind "$RUNDIR/resolv.conf" /etc/resolv.conf || { echo "FAIL: bind-mount resolv.conf"; exit 1; }
    mount --bind "$RUNDIR/nsswitch.conf" /etc/nsswitch.conf || { echo "FAIL: bind-mount nsswitch.conf"; exit 1; }

    # /etc/hosts would short-circuit the sink for any name listed there.
    : > "$RUNDIR/hosts"
    printf '127.0.0.1 localhost\n' > "$RUNDIR/hosts"
    mount --bind "$RUNDIR/hosts" /etc/hosts || { echo "FAIL: bind-mount hosts"; exit 1; }

    mkdir -p "$LOGS"
    python3 "$(dirname "$0")/egress_sink.py" "$LOGS" > "$RUNDIR/sink.out" 2>&1 &
    SINK=$!
    for _ in $(seq 1 50); do
        grep -q "SINK READY" "$RUNDIR/sink.out" 2>/dev/null && break
        sleep 0.1
    done
    if ! grep -q "SINK READY" "$RUNDIR/sink.out" 2>/dev/null; then
        echo "FAIL: sink did not start"; cat "$RUNDIR/sink.out"; exit 1
    fi
    echo "--- sink listening on 127.0.0.1 (dns/53, tcp/80, tcp/443)"

    export XDG_CONFIG_HOME="$RUNDIR/config"
    export XDG_RUNTIME_DIR="$RUNDIR/run"
    export QT_QPA_PLATFORM=offscreen
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    python3 "$(dirname "$0")/egress_seed_config.py" "$XDG_CONFIG_HOME/xeneon-edge-hub" "$MODE" "$URL" || exit 1

    echo "--- running hub for ${SECS}s under strace"
    # SIGKILL, not TERM: the hub's graceful shutdown can hang on sensor/socket
    # teardown (see tests/runtime/README.md). Nothing here depends on a clean
    # exit - the evidence is already on disk.
    timeout -s KILL "$SECS" \
        "$STRACE" -f -qq -e trace=connect -o "$LOGS/strace.log" \
        "$HUB" > "$RUNDIR/hub.out" 2>&1
    # 137 = timeout had to SIGKILL it, i.e. it was ALIVE for the whole window.
    # Recorded because a hub that died on launch also emits zero egress, and the
    # zero-egress assertion cannot tell "sent nothing" from "never ran" - that is
    # the vacuous green this job exists to prevent.
    echo "$?" > "$RUNDIR/rc"
    kill -9 "$SINK" 2>/dev/null
    wait "$SINK" 2>/dev/null
    echo "--- hub stopped"
    exit 0
fi

# ── outer ────────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

MODE_ARG="${1:-default}"; shift || true
EXPECTED_HOSTS=("$@")
SECS="${XENEON_EGRESS_SECS:-12}"

URL=""
MODE="$MODE_ARG"
case "$MODE_ARG" in
    url:*) MODE="url"; URL="${MODE_ARG#url:}" ;;
esac

HUB="${XENEON_HUB:-}"
if [ -z "$HUB" ]; then
    for c in "$ROOT/build/xeneon-edge-hub" "$(command -v xeneon-edge-hub 2>/dev/null)"; do
        [ -n "$c" ] && [ -x "$c" ] && { HUB="$c"; break; }
    done
fi
if [ -z "$HUB" ] || [ ! -x "$HUB" ]; then
    echo "SKIP: no hub binary (build it, or set XENEON_HUB)"; exit 77
fi

STRACE="${STRACE:-$(command -v strace 2>/dev/null)}"
if [ -z "$STRACE" ] || [ ! -x "$STRACE" ]; then
    # Refusing to run is the only honest option: without connect(2) tracing the
    # hard-coded-IP case is unobservable, and a silently weaker attestation is
    # worse than none - it would still print PASS.
    echo "FAIL: strace not found - it is the ground-truth channel, not an optional extra"; exit 1
fi

RUNDIR="$(mktemp -d)"
trap 'rm -rf "$RUNDIR"' EXIT
LOGS="$RUNDIR/logs"

echo "═══ no-egress attestation: mode=$MODE${URL:+ url=$URL} ═══"
echo "hub:    $HUB"
echo "strace: $STRACE"
[ ${#EXPECTED_HOSTS[@]} -gt 0 ] && echo "expect: ${EXPECTED_HOSTS[*]}" || echo "expect: ZERO egress"

UNSHARE_ARGS=(--net --mount)
[ "$(id -u)" -ne 0 ] && UNSHARE_ARGS+=(--map-root-user)
if ! unshare "${UNSHARE_ARGS[@]}" -- bash "$SELF" __inner "$RUNDIR" "$MODE" "$URL" "$HUB" "$STRACE" "$SECS"; then
    echo "FAIL: could not run the hub inside the network namespace"
    exit 1
fi

# ── evidence ─────────────────────────────────────────────────────────────────
DNS_LOG="$LOGS/dns.log"; TCP_LOG="$LOGS/tcp.log"; STRACE_LOG="$LOGS/strace.log"
for f in "$DNS_LOG" "$TCP_LOG"; do
    [ -f "$f" ] || { echo "FAIL: missing evidence $f"; exit 1; }
done

# Non-loopback connect(2) = egress that never consulted the sink, i.e. a
# hard-coded IP. 127.0.0.0/8 and AF_UNIX are the app's own IPC and the sink.
NONLOOP="$(grep -oE 'sin6?_addr=inet(6)?_addr\("[^"]+"\)' "$STRACE_LOG" 2>/dev/null \
    | grep -oE '"[^"]+"' | tr -d '"' \
    | grep -vE '^127\.|^::1$|^0\.0\.0\.0$' | sort -u)"

HOSTS="$(sort -u "$DNS_LOG" 2>/dev/null | grep -v '^$')"
CONNS="$(wc -l < "$TCP_LOG" 2>/dev/null | tr -d ' ')"

echo
echo "── evidence ─────────────────────────────────────────"
echo "DNS lookups (hosts the hub wanted):"
[ -n "$HOSTS" ] && echo "$HOSTS" | sed 's/^/    /' || echo "    (none)"
echo "TCP connections to the sink: $CONNS"
[ "$CONNS" -gt 0 ] && sed 's/^/    /' "$TCP_LOG"
echo "connect(2) to non-loopback addresses:"
[ -n "$NONLOOP" ] && echo "$NONLOOP" | sed 's/^/    /' || echo "    (none)"
echo "─────────────────────────────────────────────────────"
echo

RC=0

# Liveness gate, before any egress assertion: every conclusion below assumes the
# hub was actually running and had the chance to phone home.
HUB_RC="$(cat "$RUNDIR/rc" 2>/dev/null || echo "?")"
if [ "$HUB_RC" != "137" ]; then
    echo "✗ NOT LIVE: the hub exited early (rc=$HUB_RC) instead of running for ${SECS}s."
    echo "  Every assertion below would be vacuous - a dead hub sends nothing."
    echo "  ── hub output ──"
    sed 's/^/    /' "$RUNDIR/hub.out" 2>/dev/null | head -30
    echo "NO-EGRESS ATTESTATION FAIL"
    exit 1
fi
echo "✓ liveness: hub ran the full ${SECS}s (SIGKILLed by the timer, rc=137)"

# A hard-coded IP is a violation in EVERY mode: an allowlist is expressed in
# hostnames, so an address the sink never named cannot have been allowlisted.
if [ -n "$NONLOOP" ]; then
    echo "✗ EGRESS TO A NON-LOOPBACK ADDRESS - bypassed DNS entirely (hard-coded IP?):"
    echo "$NONLOOP" | sed 's/^/    /'
    RC=1
fi

if [ ${#EXPECTED_HOSTS[@]} -eq 0 ]; then
    # ── ZERO-egress assertion ──
    if [ -n "$HOSTS" ]; then
        echo "✗ EXPECTED ZERO EGRESS, but the hub tried to reach:"
        echo "$HOSTS" | sed 's/^/    /'
        RC=1
    fi
    if [ "$CONNS" -ne 0 ]; then
        echo "✗ EXPECTED ZERO EGRESS, but $CONNS TCP connection(s) were made"
        RC=1
    fi
    [ "$RC" -eq 0 ] && echo "✓ ZERO egress: no DNS lookup, no TCP connection, no raw-IP connect."
else
    # ── allowlist assertion ──
    # The run must actually have reached the network. Without this, a hub that
    # failed to start would produce an empty log and "pass" the allowlist - the
    # exact vacuous green this whole job exists to prevent.
    if [ -z "$HOSTS" ]; then
        echo "✗ VACUOUS: expected egress to ${EXPECTED_HOSTS[*]} but the hub made NO request at all."
        echo "  (the widget did not fire - this run proves nothing; check hub.out)"
        RC=1
    fi
    for h in $HOSTS; do
        ok=0
        for e in "${EXPECTED_HOSTS[@]}"; do [ "$h" = "$e" ] && ok=1; done
        if [ "$ok" -ne 1 ]; then
            echo "✗ UNEXPECTED HOST: $h  (allowed: ${EXPECTED_HOSTS[*]})"
            RC=1
        fi
    done
    [ "$RC" -eq 0 ] && echo "✓ Egress confined to the expected host(s): ${EXPECTED_HOSTS[*]}"
fi

echo
[ "$RC" -eq 0 ] && echo "NO-EGRESS ATTESTATION PASS" || echo "NO-EGRESS ATTESTATION FAIL"
exit "$RC"
