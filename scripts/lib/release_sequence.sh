#!/usr/bin/env bash
# Runtime state barrier between read-only release preflight and artifact mutation.

xeneon_release_sequence_init() {
    XENEON_RELEASE_GATE_PASSED=0
}

xeneon_release_sequence_mark_gate_passed() {
    [ "${XENEON_RELEASE_GATE_PASSED:-0}" -eq 0 ] || return 1
    XENEON_RELEASE_GATE_PASSED=1
}

xeneon_release_sequence_require_gate_passed() {
    [ "${XENEON_RELEASE_GATE_PASSED:-0}" -eq 1 ]
}

# Release identities deliberately use the one channel grammar understood by the
# package metadata and UpdateChecker: a normal SemVer, or an alpha/beta/rc with a
# numeric sequence.  Merely checking for a leading "v" allowed signed tags such
# as vgarbage to become package versions even though downstream updaters cannot
# order them.
xeneon_release_version_is_valid() {
    [[ "${1:-}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.(0|[1-9][0-9]*))?$ ]]
}

# Read `gpg --status-fd`/`git verify-tag --raw` output on stdin and accept it
# only when a VALIDSIG record names the exact, full pinned fingerprint. GnuPG
# reports both the signing-subkey fingerprint and (when applicable) its primary
# fingerprint, so checking every 40-hex field supports an offline signing
# subkey without weakening identity pinning.
xeneon_gnupg_validsig_has_fingerprint() {
    awk -v expected="${1:-}" '
        BEGIN {
            expected = toupper(expected)
            if (length(expected) != 40 || expected !~ /^[0-9A-F]+$/)
                exit 2
        }
        $1 == "[GNUPG:]" && $2 == "VALIDSIG" {
            for (i = 3; i <= NF; i++)
                if (length($i) == 40 && toupper($i) == expected)
                    found = 1
        }
        END { if (!found) exit 1 }
    '
}
