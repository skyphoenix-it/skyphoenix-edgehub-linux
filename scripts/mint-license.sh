#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# mint-license.sh — issue a Xeneon Edge Pro licence key.
#
# Thin wrapper over the issuer tool (tools/license-tool). The SECRET signing seed
# is NEVER passed on the command line (it would land in your shell history and
# `ps`); it is read from the environment or a file:
#
#   export XENEON_LICENSE_SEED="$(cat ~/.secrets/xeneon-license-seed)"   # or
#   XENEON_LICENSE_SEED_FILE=~/.secrets/xeneon-license-seed \
#     ./scripts/mint-license.sh --to "Ada Lovelace <ada@x.io>" --id XE-0007
#
# First time only — create the keypair, paste the PUBLIC key into
# core/src/license.rs, and store the PRIVATE seed in your password manager:
#
#   cargo run -q --manifest-path tools/license-tool/Cargo.toml -- keygen
#
# Options (passed through to `mint`): --to <name/email>  --id <id>
#   [--tier pro]  [--expires <unix-seconds|never>]   (default: pro, never)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SEED="${XENEON_LICENSE_SEED:-}"
if [ -z "$SEED" ] && [ -n "${XENEON_LICENSE_SEED_FILE:-}" ]; then
    SEED="$(tr -d '[:space:]' < "$XENEON_LICENSE_SEED_FILE")"
fi
if [ -z "$SEED" ]; then
    echo "error: no signing seed. Set XENEON_LICENSE_SEED or XENEON_LICENSE_SEED_FILE." >&2
    echo "       (Run 'cargo run --manifest-path tools/license-tool/Cargo.toml -- keygen'" >&2
    echo "        once to create it, if you have not.)" >&2
    exit 2
fi

# Put the seed on a private inherited descriptor, then remove both shell variables
# before Cargo (and the compiler/tool process tree) starts.  The CLI reads the
# descriptor through stdin; the secret is therefore absent from argv, `ps`, and
# the child environment.  A here-string adds one newline, which the CLI trims.
exec 3<<<"$SEED"
unset SEED XENEON_LICENSE_SEED
exec cargo run -q --manifest-path tools/license-tool/Cargo.toml -- \
    mint --seed-stdin "$@" <&3
