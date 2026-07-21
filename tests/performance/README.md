# Performance and soak evidence

This directory contains the Linux resource gate for the Xeneon Edge Hub. It
creates machine-readable JSON evidence and fails closed when a required metric,
sample, process, or observation is missing. The scripts do not contain a fast
or duration-scaled release mode.

No performance number is a release or marketing claim until its corresponding
JSON report exists for the release candidate and has `"qualified": true`.

## Release thresholds

| Profile | Real interval | Required load | Pass condition |
|---|---:|---:|---|
| Startup | one cold process launch | empty dashboard | first non-null Wayland buffer commit `< 2s` |
| Idle | 5 minutes after 30s warm-up | 0 widgets | average CPU `< 1%`, peak process-tree RSS `< 150MiB` |
| Active | 5 minutes after 30s warm-up | exactly 10 updating widgets | average CPU `< 5%`, peak process-tree RSS `< 250MiB` |
| Idle soak | 24 hours after 30s warm-up | 0 widgets | CPU `< 1%`, RSS `< 150MiB`, median-window RSS growth `< 10%` |
| Extended idle soak | 48 hours after 30s warm-up | 0 widgets | CPU `< 1%`, RSS `< 150MiB`, median-window RSS growth `< 10%` |

The active load is a fixed manifest: CPU, GPU, RAM, network, disk, sensors,
digital clock, analog clock, a running focus timer, and a running break timer.
It avoids network-backed widgets so a service outage cannot turn a performance
run into a different workload.

The sampler uses the Linux convention that 100% CPU is one fully occupied
logical core. It follows the Hub's complete descendant tree and sums RSS,
threads, file descriptors, sockets, and I/O counters. A descendant appearing or
disappearing during the qualifying interval invalidates the run instead of
hiding work. One-second samples record peaks and a least-squares RSS slope; the
CPU average uses cumulative kernel ticks, so scheduling delays do not discard
CPU time.

## Commands

Run the injection-free unit and contract suite (this does not launch a GUI):

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s tests/performance -p 'test_*.py' -v
```

Run the short real-Edge qualification (roughly 11 minutes including warm-up):

```bash
cmake -S . -B cmake-build-performance-local \
  -DCMAKE_BUILD_TYPE=Release -DXENEON_COVERAGE=OFF -DXENEON_QA_HOOKS=OFF
cmake --build cmake-build-performance-local

PYTHONDONTWRITEBYTECODE=1 python3 tests/performance/run_hub_profiles.py \
  --mode short \
  --hub cmake-build-performance-local/xeneon-edge-hub \
  --output-dir /tmp/xeneon-performance-short
```

The startup observer enables `WAYLAND_DEBUG=client` only for a fresh isolated
Hub process. It timestamps the first non-null `wl_buffer` attachment followed by
the matching `wl_surface.commit`. This is a conservative upper bound to rendered
pixels submitted to the compositor. Control-socket readiness is recorded only
as a diagnostic and never accepted as first-render evidence.

The short run includes RSS trend data for regression diagnosis, but it **does
not satisfy the 24-hour or 48-hour requirement**. Those modes wait the complete
wall-clock intervals:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/performance/run_hub_profiles.py \
  --mode idle-24h --hub cmake-build-performance-local/xeneon-edge-hub \
  --output-dir /tmp/xeneon-performance-idle-24h

PYTHONDONTWRITEBYTECODE=1 python3 tests/performance/run_hub_profiles.py \
  --mode idle-48h --hub cmake-build-performance-local/xeneon-edge-hub \
  --output-dir /tmp/xeneon-performance-idle-48h
```

The 48-hour report also evaluates the first real 24-hour prefix as an
independent checkpoint. A day-one leak cannot be hidden by RSS falling again on
day two. The strict release manifest runs the short profile and this literal
48-hour profile; either non-zero result blocks release.

Each output directory must be empty. This prevents a new summary from being
mistakenly combined with stale evidence. Preserve the directory with the other
release artifacts. The runner appends a JSONL sample trace as it works and
flushes a progress checkpoint every five minutes, so a crash still leaves
diagnostic evidence rather than an empty 48-hour run.

To profile an already-running process against the same immutable contracts:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/performance/resource_probe.py sample \
  --pid "$HUB_PID" --profile idle-5m --widgets 0 \
  --log /path/to/hub.log --output /tmp/hub-idle.json
```

## Scope and limitations

- The automated load runner targets the Hub because the published resource
  budgets are Hub requirements. The generic `/proc` sampler can record Manager
  diagnostics, but the repository does not define Manager CPU/RSS thresholds;
  applying the Hub thresholds to it would invent a release claim.
- Linux `/proc` has no portable per-process GPU counter or network-byte counter.
  Reports say those fields are unavailable, record socket descriptors, and rely
  on the separate NetHub/no-egress tests for network policy.
- Touch-to-photon latency and per-widget update latency are different
  requirements. Resource reports do not claim to measure either one.
- A passing 24-hour or 48-hour report proves only the measured idle scenario.
  Disconnect/reconnect and suspend/resume endurance scenarios remain separate
  stability tests.

The profile runner accepts only a CMake `Release` candidate with
`XENEON_COVERAGE=OFF` and `XENEON_QA_HOOKS=OFF`; it records the executable's
version and SHA-256. The strict release gate builds that candidate from scratch
in `cmake-build-release-performance` after coverage has been collected, because
instrumented code is not valid CPU/RSS evidence.
