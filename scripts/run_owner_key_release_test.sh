#!/usr/bin/env bash
# Release-only proof that an owner-issued key unlocks Pro against the shipped
# issuer. Unlike an ordinary captured Cargo run, this requires exactly one named
# test to execute visibly; zero tests or a hidden SKIP are failures.
set -uo pipefail

OWNER_TEST="license::tests::owners_real_pro_key_unlocks_pro_against_the_shipped_issuer_key"
OWNER_TEST_LICENSE_KEY="${XENEON_TEST_LICENSE_KEY:-}"
if [ "${XENEON_OWNER_KEY_FD:-}" = "3" ]; then
    IFS= read -r OWNER_TEST_LICENSE_KEY <&3 || OWNER_TEST_LICENSE_KEY=""
    exec 3<&-
fi
unset XENEON_TEST_LICENSE_KEY
unset XENEON_OWNER_KEY_FD

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

case "$OWNER_TEST_LICENSE_KEY" in
    *[![:space:]]*) ;;
    *)
        echo "ERROR: XENEON_TEST_LICENSE_KEY must contain a real owner-issued Pro key." >&2
        exit 2
        ;;
esac

owner_log="$(mktemp "${TMPDIR:-/tmp}/xe-owner-key-test.XXXXXX")" || exit 1
trap 'rm -f "$owner_log"' EXIT

XENEON_TEST_LICENSE_KEY="$OWNER_TEST_LICENSE_KEY" \
    cargo test --manifest-path "$PROJECT_DIR/core/Cargo.toml" --locked --lib \
    "$OWNER_TEST" -- --exact --nocapture 2>&1 | tee "$owner_log"
pipeline_status=("${PIPESTATUS[@]}")
OWNER_TEST_LICENSE_KEY=""

cargo_rc="${pipeline_status[0]:-1}"
tee_rc="${pipeline_status[1]:-1}"
if [ "$cargo_rc" -ne 0 ]; then
    echo "ERROR: owner-issued Pro key test failed (cargo rc=$cargo_rc)." >&2
    exit "$cargo_rc"
fi
if [ "$tee_rc" -ne 0 ]; then
    echo "ERROR: could not capture owner-issued Pro key test evidence (tee rc=$tee_rc)." >&2
    exit "$tee_rc"
fi
if grep -Eq '(^|[^[:alnum:]_])(SKIP|SKIPPED)([^[:alnum:]_]|$)' "$owner_log"; then
    echo "ERROR: owner-issued Pro key test reported a skip." >&2
    exit 1
fi
if [ "$(grep -Fxc 'running 1 test' "$owner_log")" -ne 1 ]; then
    echo "ERROR: owner-issued Pro key attestation did not execute exactly one test." >&2
    exit 1
fi
if ! grep -Fqx "test $OWNER_TEST ... ok" "$owner_log"; then
    echo "ERROR: owner-issued Pro key attestation produced no explicit passing result." >&2
    exit 1
fi

echo "OWNER KEY ATTESTATION: PASS (exactly one shipped-issuer test executed)"
