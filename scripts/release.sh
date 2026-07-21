#!/usr/bin/env bash
#
# EdgeHub release helper — run this on the maintainer's own machine, by hand.
#
# WHY THIS IS A LOCAL SCRIPT AND NOT A CI WORKFLOW:
#   The release key's passphrase belongs to the maintainer and is never delegated
#   — not to a CI secret, not to an environment variable, not to this script. gpg
#   prompts a human; the human answers. Automating that away would move the trust
#   root off the maintainer's machine, which is the one property a signature is
#   supposed to prove. If you ever find yourself wanting to pass a passphrase to
#   this script, the answer is no.
#
# WHY IT ABORTS INSTEAD OF DEGRADING TO UNSIGNED:
#   An unsigned release that looks signed is worse than an honest unsigned one.
#   Every path that cannot sign exits non-zero *before* any artifact is written,
#   so a half-failed run can never leave publishable-looking output behind.
#
# Usage (the three release-test inputs must be provided in the environment):
#   scripts/release.sh --version v1.0.0-beta.1            # test + build + sign + print
#   scripts/release.sh --version v1.0.0-beta.1 --publish  # ... and run gh
#   scripts/release.sh --version v1.0.0-beta.1 --extra path/to/foo.pkg.tar.zst
#
# Required by the mandatory strict test gate:
#   XENEON_HW_INPUT=1, XENEON_HW_INPUT_DESKTOP=1, XENEON_TEST_LICENSE_KEY=<key>
#
# AppImage + zsync (E10): pass the AppImage from packaging/appimage/
# build-appimage.sh as an --extra. A matching .zsync control file is then
# generated next to it (requires `zsyncmake`, checked in preflight), pointing
# at this release's download URL, so AppImage users delta-update instead of
# re-downloading ~46 MB. The .zsync lands in dist/ BEFORE SHA256SUMS is
# written, so it is checksummed and covered by the signature like everything
# else. Native packages (AUR/deb/rpm/Flatpak) update through their package
# manager — no zsync for those; see docs/DISTRIBUTION.md "Updates".
#
set -euo pipefail

# Capture the owner-issued entitlement before the first child process and remove
# it from the exported environment. It reaches the strict gate only through a
# short-lived inherited descriptor, never the build/sign/publish process tree.
RELEASE_OWNER_TEST_LICENSE_KEY="${XENEON_TEST_LICENSE_KEY:-}"
unset XENEON_TEST_LICENSE_KEY

# The EdgeHub release key (SKYPhoenix IT <simon.kreitmayer@skyphoenix-it.com>).
# Full 40-hex fingerprint, not the short id: short ids are forgeable by
# construction, so anything that decides trust must pin the full fingerprint.
# Expires 2028-07-14 — see docs/DISTRIBUTION.md for the rotation policy.
readonly RELEASE_KEY="2F0CAD36DC1D46F3347B7EF293CDC77EACF98990"
readonly RELEASE_REPO="skyphoenix-it/XeneonEdge_Linux"

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIST_DIR="${REPO_DIR}/dist"
# Named to match the existing cmake-build-*/ rule in .gitignore, and kept out of
# the dev build/ dir so a release build never inherits a stale dev cache (notably
# -DXENEON_QA_HOOKS=ON, which scripts/build.sh sets and releases must not ship).
readonly BUILD_DIR="${REPO_DIR}/cmake-build-release"
readonly RELEASE_SOURCE_DIR="${REPO_DIR}/cmake-build-release-source"
readonly STRICT_RELEASE_GATE="${REPO_DIR}/scripts/run_release_tests.sh"

# shellcheck source=lib/release_sequence.sh
. "${REPO_DIR}/scripts/lib/release_sequence.sh"
xeneon_release_sequence_init

VERSION=""
PUBLISH=0
EXTRA_ARTIFACTS=()

die() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# Immutable-byte ledger for every unsigned payload that will enter SHA256SUMS.
# It catches an accidental/racing replacement after build/copy/validation but
# before the manifest is written.  The signed manifest then provides the second
# check over those same final paths.
FINAL_ARTIFACT_PATHS=()
FINAL_ARTIFACT_HASHES=()
record_final_artifact() {
    local artifact="$1" digest_line digest
    [ -f "$artifact" ] || die "cannot record missing release artifact: $artifact"
    digest_line="$(sha256sum -- "$artifact")" \
        || die "could not hash release artifact: $artifact"
    digest="${digest_line%% *}"
    FINAL_ARTIFACT_PATHS+=("$artifact")
    FINAL_ARTIFACT_HASHES+=("$digest")
}

verify_final_artifacts() {
    local i artifact digest_line digest
    [ "${#FINAL_ARTIFACT_PATHS[@]}" -gt 0 ] \
        || die "final artifact ledger is empty"
    for i in "${!FINAL_ARTIFACT_PATHS[@]}"; do
        artifact="${FINAL_ARTIFACT_PATHS[$i]}"
        [ -f "$artifact" ] || die "release artifact disappeared before signing: $artifact"
        digest_line="$(sha256sum -- "$artifact")" \
            || die "could not re-hash release artifact: $artifact"
        digest="${digest_line%% *}"
        [ "$digest" = "${FINAL_ARTIFACT_HASHES[$i]}" ] \
            || die "release artifact changed after validation: $artifact"
    done
}

validate_appimage_payload() {
    local appimage="$1" pkgver="$2" update_info extract_root
    local hub_version manager_version

    update_info="$(timeout 30 "$appimage" --appimage-updateinformation 2>/dev/null)" \
        || die "could not read embedded AppImage update information from $(basename "$appimage")"
    [ "$update_info" = "$EXPECTED_APPIMAGE_UPDATE_INFO" ] \
        || die "AppImage update-information mismatch. Expected '$EXPECTED_APPIMAGE_UPDATE_INFO', got '$update_info'"

    extract_root="$(mktemp -d -t xeneon-release-appimage-XXXXXX)" \
        || die "could not create AppImage validation directory"
    cleanup_release_appimage() { rm -rf -- "$extract_root"; }
    trap cleanup_release_appimage EXIT INT TERM
    ( cd "$extract_root" && timeout 120 "$appimage" --appimage-extract >/dev/null ) \
        || die "the exact dist AppImage could not be extracted"
    [ -x "$extract_root/squashfs-root/usr/bin/xeneon-edge-hub" ] \
        || die "AppImage is missing executable usr/bin/xeneon-edge-hub"
    [ -x "$extract_root/squashfs-root/usr/bin/xeneon-edge-manager" ] \
        || die "AppImage is missing executable usr/bin/xeneon-edge-manager"
    hub_version="$("$extract_root/squashfs-root/usr/bin/xeneon-edge-hub" --version)"
    manager_version="$("$extract_root/squashfs-root/usr/bin/xeneon-edge-manager" --version)"
    [ "$hub_version" = "Xeneon Edge Linux Hub $pkgver" ] \
        || die "AppImage Hub version mismatch: $hub_version"
    [ "$manager_version" = "Xeneon Edge Manager $pkgver" ] \
        || die "AppImage Manager version mismatch: $manager_version"
    timeout 180 bash "$RELEASE_SOURCE_DIR/packaging/ci/smoke-appimage.sh" \
        "$appimage" "$RELEASE_SOURCE_DIR" \
        || die "the exact dist AppImage failed its runtime/QML smoke test"
    cleanup_release_appimage
    trap - EXIT INT TERM
    note "AppImage name, update metadata, both versions, runtime, and QML modules verified"
}

verify_release_tag_identity() {
    local tag_name="$1" verify_status
    if ! verify_status="$(git -C "$REPO_DIR" verify-tag --raw "$tag_name" 2>&1)"; then
        printf '%s\n' "$verify_status" >&2
        die "tag $tag_name is not a cryptographically valid signed tag. Recreate it with 'git tag -s' before releasing."
    fi

    # VALIDSIG contains the signing fingerprint and, for a signing subkey, the
    # primary-key fingerprint. Accept either only when it is the pinned release
    # identity; a valid signature by an unrelated key is not release provenance.
    printf '%s\n' "$verify_status" \
        | xeneon_gnupg_validsig_has_fingerprint "$RELEASE_KEY" \
        || die "tag $tag_name has a valid signature, but not from the pinned release key $RELEASE_KEY."
}

usage() {
    sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:-}"; shift 2 ;;
        --publish) PUBLISH=1; shift ;;
        --extra)   EXTRA_ARTIFACTS+=("${2:-}"); shift 2 ;;
        -h|--help) usage 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done

[ -n "$VERSION" ] || die "--version is required (e.g. --version v1.0.0-beta.1)"
xeneon_release_version_is_valid "$VERSION" \
    || die "version must be vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-{alpha,beta,rc}.N with no leading zeroes; got: $VERSION"

readonly PREFLIGHT_PKGVER="${VERSION#v}"
readonly PREFLIGHT_ARCH="$(uname -m)"
readonly EXPECTED_SRC_TARBALL="xeneon-edge-hub-${PREFLIGHT_PKGVER}.tar.gz"
readonly EXPECTED_BIN_TARBALL="xeneon-edge-hub_${PREFLIGHT_PKGVER}_${PREFLIGHT_ARCH}.tar.gz"
# build-appimage.sh currently has one supported architecture and embeds this
# spelling in its update-information wildcard.  Do not accept a merely
# executable *.AppImage with a different name: its generated .zsync would be
# invisible to AppImageUpdate.
readonly EXPECTED_APPIMAGE="xeneon-edge-hub-${PREFLIGHT_PKGVER}-x86_64.AppImage"
readonly EXPECTED_APPIMAGE_UPDATE_INFO="gh-releases-zsync|skyphoenix-it|XeneonEdge_Linux|latest|xeneon-edge-hub-*-x86_64.AppImage.zsync"

# ─────────────────────────────────────────────────────────────────────────────
# Preflight. Everything that can refuse must refuse HERE, before we build or
# write a single artifact — a 20-minute build that dies at the signing step and
# leaves an unsigned dist/ behind is the failure mode this ordering prevents.
# ─────────────────────────────────────────────────────────────────────────────
step "Preflight: source provenance"

command -v git >/dev/null 2>&1 \
    || die "git not found (required to verify the release source)"

# Release artifacts are functions of a signed tag, not of whatever happens to
# be in the checkout. Refuse staged, unstaged, and untracked changes so the
# build, release notes, and helper itself all come from the reviewed commit.
if ! worktree_status="$(git -C "$REPO_DIR" status --porcelain=v1 --untracked-files=all)"; then
    die "could not inspect the working tree. Refusing to release an unverified checkout."
fi
if [ -n "$worktree_status" ]; then
    printf '%s\n' "$worktree_status" >&2
    die "working tree is dirty. Commit or remove every staged, unstaged, and untracked change before releasing."
fi

# A local tag with the requested name is not enough: it must name this exact
# checkout and carry a cryptographically valid signature. Tag creation remains
# a separate, interactive maintainer action; this script only verifies it.
git -C "$REPO_DIR" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null \
    || die "tag $VERSION does not exist locally. Create it first:  git tag -s $VERSION -m '$VERSION'"

head_commit="$(git -C "$REPO_DIR" rev-parse --verify "HEAD^{commit}")" \
    || die "could not resolve HEAD to a commit"
tag_commit="$(git -C "$REPO_DIR" rev-parse --verify "refs/tags/${VERSION}^{commit}")" \
    || die "tag $VERSION does not resolve to a commit"
[ "$tag_commit" = "$head_commit" ] \
    || die "tag $VERSION resolves to $tag_commit, but HEAD is $head_commit. Check out the tagged commit before releasing."

verify_release_tag_identity "$VERSION"

# Publishing prerequisites are checked before the multi-day release gate.  A
# missing notes file, wrong GitHub identity, or pre-existing release must not be
# discovered only after the candidate has been tested, built, and signed.
if [ "$PUBLISH" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 \
        || die "--publish requested but gh is not installed"
    [ -s "${REPO_DIR}/RELEASE_NOTES.md" ] \
        || die "--publish requires a non-empty RELEASE_NOTES.md at the repo root"
    git -C "$REPO_DIR" cat-file -e "${tag_commit}:RELEASE_NOTES.md" 2>/dev/null \
        || die "RELEASE_NOTES.md is not part of the signed release commit $tag_commit"
    gh auth status --hostname github.com >/dev/null 2>&1 \
        || die "gh is not authenticated to github.com; refusing to run the release gate before publish can succeed"
    existing_release_tags="$(gh release list --repo "$RELEASE_REPO" --limit 1000 \
        --json tagName --jq '.[].tagName')" \
        || die "could not query releases for $RELEASE_REPO"
    if printf '%s\n' "$existing_release_tags" | grep -Fxq -- "$VERSION"; then
        die "GitHub release $RELEASE_REPO@$VERSION already exists; refusing to overwrite or duplicate it"
    fi
    note "publish target: $RELEASE_REPO (authenticated; tag is not already released)"
fi

step "Preflight: signing key"

command -v gpg >/dev/null 2>&1 \
    || die "gpg not found. The release key is mandatory; install gnupg. Refusing to build an unsigned release."

if ! gpg --list-secret-keys "$RELEASE_KEY" >/dev/null 2>&1; then
    die "$(cat <<EOF
release signing key not available in this keyring.

  Expected secret key: $RELEASE_KEY
  GNUPGHOME:           ${GNUPGHOME:-$HOME/.gnupg}

This script will NOT produce an unsigned release — an unsigned artifact that
looks official is worse than no artifact. Import the key (or unset GNUPGHOME)
and re-run. The public half lives at packaging/edgehub-signing.pub; the secret
half only ever exists on the maintainer's machine.
EOF
)"
fi

# A key can be present, listable, and still useless: expired, revoked, or with no
# signing-capable subkey. Check the capability the release actually needs rather
# than assuming presence == usable.
key_line="$(gpg --list-secret-keys --with-colons "$RELEASE_KEY" 2>/dev/null | awk -F: '$1=="sec"{print; exit}')"
[ -n "$key_line" ] || die "could not read secret key record for $RELEASE_KEY"

key_expiry="$(printf '%s' "$key_line" | cut -d: -f7)"
key_caps="$(printf '%s' "$key_line" | cut -d: -f12)"
key_validity="$(printf '%s' "$key_line" | cut -d: -f2)"

case "$key_validity" in
    r) die "release key $RELEASE_KEY is REVOKED. Refusing to sign." ;;
    e) die "release key $RELEASE_KEY is EXPIRED. Extend it (gpg --edit-key $RELEASE_KEY expire) or rotate — see docs/DISTRIBUTION.md. Refusing to sign." ;;
esac
case "$key_caps" in
    *s*|*S*) ;;
    *) die "release key $RELEASE_KEY has no signing capability (caps: ${key_caps:-none}). Refusing to sign." ;;
esac
if [ -n "$key_expiry" ] && [ "$key_expiry" -le "$(date +%s)" ] 2>/dev/null; then
    die "release key $RELEASE_KEY expired on $(date -d "@$key_expiry" +%F). Refusing to sign."
fi

note "key:     $RELEASE_KEY"
note "uid:     $(gpg --list-keys --with-colons "$RELEASE_KEY" | awk -F: '$1=="uid"{print $10; exit}')"
[ -n "$key_expiry" ] && note "expires: $(date -d "@$key_expiry" +%F)"

if [ "$PUBLISH" -eq 0 ] && ! command -v gh >/dev/null 2>&1; then
    note "WARNING: gh not found — the release command will be printed, not run."
fi

step "Preflight: prerequisites"
for tool in cmake cargo cmp gzip sha256sum tar git timeout uname; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found (required to build the release artifacts)"
done
HAVE_APPIMAGE=0
APPIMAGE_COUNT=0
EXTRA_BASENAMES=()
for extra in "${EXTRA_ARTIFACTS[@]}"; do
    [ -f "$extra" ] || die "--extra artifact not found: $extra"
    extra_name="$(basename -- "$extra")"
    [ -n "$extra_name" ] || die "--extra produced an empty basename: $extra"
    case "$extra_name" in
        *$'\n'*|*$'\r'*) die "--extra basenames may not contain line breaks" ;;
    esac
    for seen_name in "${EXTRA_BASENAMES[@]}"; do
        [ "$extra_name" != "$seen_name" ] \
            || die "duplicate --extra basename '$extra_name' would overwrite an earlier artifact"
    done
    EXTRA_BASENAMES+=("$extra_name")

    # These names are created by this release from the verified tag.  An extra
    # with the same basename used to overwrite the already smoke-tested source
    # or binary tarball and then get checksummed/signed as if it were that output.
    case "$extra_name" in
        "$EXPECTED_SRC_TARBALL"|"$EXPECTED_BIN_TARBALL"|SHA256SUMS|SHA256SUMS.asc|"${EXPECTED_SRC_TARBALL}.sig"|*.zsync)
            die "--extra basename '$extra_name' is reserved for a release-generated artifact"
            ;;
    esac

    case "$extra_name" in
        *.AppImage)
            HAVE_APPIMAGE=1
            APPIMAGE_COUNT=$((APPIMAGE_COUNT + 1))
            [ "$extra_name" = "$EXPECTED_APPIMAGE" ] \
                || die "AppImage must be named $EXPECTED_APPIMAGE so embedded update discovery can find its .zsync (got $extra_name)"
            [ -x "$extra" ] \
                || die "AppImage is not executable: $extra"
            ;;
    esac
done
[ "$APPIMAGE_COUNT" -le 1 ] \
    || die "exactly one AppImage is supported; multiple updater targets are ambiguous"
# zsync is part of the AppImage update contract (docs/DISTRIBUTION.md): an
# AppImage published without its .zsync silently breaks delta updates for
# everyone on the previous release. So it fails HERE, before the build —
# not "skipped" and discovered after publishing.
if [ "$HAVE_APPIMAGE" -eq 1 ]; then
    command -v zsyncmake >/dev/null 2>&1 \
        || die "zsyncmake not found but an .AppImage was passed via --extra.
Install it (Arch/CachyOS: 'zsync' [AUR]; Debian/Ubuntu: 'zsync'; Fedora: 'zsync')
or drop the AppImage from this release. Refusing to publish an AppImage without
its .zsync — that breaks delta updates for existing users."
fi

# The other half of the same contract, and the one that actually bit: publishing
# a release with NO AppImage at all. Every release so far shipped tarballs only,
# because attaching the AppImage is a manual --extra and nobody remembered — so
# `X-AppImage-UpdateInformation` points at "latest", finds no AppImage asset, and
# every AppImage user silently never sees an update. That is indistinguishable
# from "there are no updates", which is why it went unnoticed through two
# releases. Make it an explicit DECISION rather than an omission.
if [ "$HAVE_APPIMAGE" -eq 0 ] && [ "${ALLOW_NO_APPIMAGE:-0}" != "1" ]; then
    die "no .AppImage passed via --extra.

Publishing without one means AppImage users get NO update from this release —
their embedded update-information resolves to a release with no AppImage asset,
which looks exactly like 'you are up to date'. Two releases have already shipped
this way.

Either:
  • build it and attach it:
        packaging/appimage/build-appimage.sh
        scripts/release.sh --version <tag> --extra <path>.AppImage …
    (the AppImage build needs a CI-era toolchain — linuxdeploy's bundled strip
     cannot read .relr.dyn on a modern host — so in practice take the artifact
     from the distro.yml 'appimage' job)
  • or acknowledge the gap deliberately:
        ALLOW_NO_APPIMAGE=1 scripts/release.sh …
    and say so in the release notes, so AppImage users are not left guessing."
fi
note "all present"

# The signed tag and clean checkout above define the candidate. Test that exact
# candidate before release.sh removes dist/, configures the shipping build, signs
# anything, or talks to GitHub. There is intentionally no skip flag: a release
# which cannot exercise the real Edge, Manager, compositor, owner licence key,
# no-egress attestation, and coverage gates is not a releasable candidate.
step "Preflight: mandatory strict release test gate"
[ -f "$STRICT_RELEASE_GATE" ] \
    || die "strict release test gate is missing: $STRICT_RELEASE_GATE"
export XENEON_OWNER_KEY_FD=3
bash "$STRICT_RELEASE_GATE" 3<<<"$RELEASE_OWNER_TEST_LICENSE_KEY" \
    || die "strict release test gate failed. No release artifact was created, signed, or published."
unset XENEON_OWNER_KEY_FD
RELEASE_OWNER_TEST_LICENSE_KEY=""
xeneon_release_sequence_mark_gate_passed \
    || die "strict release gate state could not be sealed"
readonly XENEON_RELEASE_GATE_PASSED

# The gate is deliberately comprehensive and long-running. Revalidate source
# provenance afterwards so a test (or concurrent edit/tag move) cannot make the
# shipping build differ from the clean, signed commit that actually passed.
if ! post_gate_status="$(git -C "$REPO_DIR" status --porcelain=v1 --untracked-files=all)"; then
    die "could not re-inspect the working tree after the strict release test gate"
fi
if [ -n "$post_gate_status" ]; then
    printf '%s\n' "$post_gate_status" >&2
    die "the working tree changed during the strict release test gate. Refusing to build untested release bytes."
fi
post_gate_head="$(git -C "$REPO_DIR" rev-parse --verify "HEAD^{commit}")" \
    || die "could not re-resolve HEAD after the strict release test gate"
post_gate_tag="$(git -C "$REPO_DIR" rev-parse --verify "refs/tags/${VERSION}^{commit}")" \
    || die "could not re-resolve tag $VERSION after the strict release test gate"
[ "$post_gate_head" = "$head_commit" ] \
    || die "HEAD moved during the strict release test gate. Refusing to build a different commit."
[ "$post_gate_tag" = "$tag_commit" ] && [ "$post_gate_tag" = "$post_gate_head" ] \
    || die "tag $VERSION moved or no longer matches HEAD after the strict release test gate."
verify_release_tag_identity "$VERSION"
note "strict release gate passed; signed source provenance revalidated"

# ─────────────────────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────────────────────
xeneon_release_sequence_require_gate_passed \
    || die "internal release-order violation: artifact mutation attempted before the strict gate"
rm -rf "$DIST_DIR" "$BUILD_DIR" "$RELEASE_SOURCE_DIR"
mkdir -p "$DIST_DIR" "$RELEASE_SOURCE_DIR"

pkgver="${VERSION#v}"

step "Building source tarball from tag $VERSION"
# Produced from the tag rather than the working tree so the bytes are a function
# of the tag alone. gzip -n drops the timestamp, which would otherwise make two
# builds of the same tag hash differently for no semantic reason.
src_tarball="xeneon-edge-hub-${pkgver}.tar.gz"
git -C "$REPO_DIR" archive --format=tar --prefix="XeneonEdge_Linux-${pkgver}/" "$tag_commit" \
    | gzip -n -9 > "${DIST_DIR}/${src_tarball}"
note "$src_tarball ($(du -h "${DIST_DIR}/${src_tarball}" | cut -f1))"
record_final_artifact "${DIST_DIR}/${src_tarball}"

step "Materializing the verified source snapshot"
tar -xzf "${DIST_DIR}/${src_tarball}" -C "$RELEASE_SOURCE_DIR" --strip-components=1

step "Building binaries (Release)"
# QA hooks stay OFF for anything shipped: scripts/build.sh turns them on for dev
# (screenshot capture / auto-open), and they have no business in a release.
cmake -B "$BUILD_DIR" -S "$RELEASE_SOURCE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DXENEON_VERSION_OVERRIDE="$pkgver" \
    -DXENEON_QA_HOOKS=OFF \
    -Wno-dev
cmake --build "$BUILD_DIR" -j"$(nproc)"

step "Packaging portable tarball (cpack -G TGZ)"
# CMake binds both fields to XENEON_VERSION_OVERRIDE. Repeat them here at the
# release boundary as a fail-obvious invariant: the one expected artifact name
# below must agree with the tag even if general CPack defaults are later changed.
bin_tarball="xeneon-edge-hub_${pkgver}_$(uname -m).tar.gz"
( cd "$BUILD_DIR" && cpack -G TGZ \
    -D CPACK_PACKAGE_VERSION="$pkgver" \
    -D CPACK_PACKAGE_FILE_NAME="${bin_tarball%.tar.gz}" )

# Copy the one file we expect by name, never a *.tar.gz glob of the build dir: a
# stale tarball from an earlier run (different version, different flags) would
# otherwise be swept into dist/, hashed, signed, and published as though it were
# part of this release. Verified: this is exactly what the glob did.
[ -f "${BUILD_DIR}/${bin_tarball}" ] \
    || die "cpack did not produce ${bin_tarball}. Refusing to guess which tarball it meant."
cp -v "${BUILD_DIR}/${bin_tarball}" "$DIST_DIR/"

step "Smoke-testing the exact QA-off portable payload"
# The comprehensive gate necessarily uses QA hooks and (for coverage) an
# instrumented binary. Before signing, launch the exact uninstrumented bytes
# CPack just produced. This catches a shipping-only flag/dependency failure and
# also proves both embedded version strings agree with the signed tag.
smoke_root="$(mktemp -d -t xeneon-release-smoke-XXXXXX)"
cleanup_release_smoke() { rm -rf -- "$smoke_root"; }
trap cleanup_release_smoke EXIT INT TERM
tar -xzf "${DIST_DIR}/${bin_tarball}" -C "$smoke_root"
[ -x "$smoke_root/usr/bin/xeneon-edge-hub" ] \
    || die "portable payload is missing executable usr/bin/xeneon-edge-hub"
[ -x "$smoke_root/usr/bin/xeneon-edge-manager" ] \
    || die "portable payload is missing executable usr/bin/xeneon-edge-manager"
hub_version="$("$smoke_root/usr/bin/xeneon-edge-hub" --version)"
manager_version="$("$smoke_root/usr/bin/xeneon-edge-manager" --version)"
[ "$hub_version" = "Xeneon Edge Linux Hub $pkgver" ] \
    || die "Hub payload version mismatch: $hub_version"
[ "$manager_version" = "Xeneon Edge Manager $pkgver" ] \
    || die "Manager payload version mismatch: $manager_version"
PATH="$smoke_root/usr/bin:$PATH" SRC_ROOT="$RELEASE_SOURCE_DIR" \
    bash "$RELEASE_SOURCE_DIR/packaging/ci/smoke.sh" \
    || die "the exact QA-off portable payload failed its runtime/QML smoke test"
cleanup_release_smoke
trap - EXIT INT TERM
note "QA-off payload launched and reports $pkgver in both binaries"
record_final_artifact "${DIST_DIR}/${bin_tarball}"

for extra in "${EXTRA_ARTIFACTS[@]}"; do
    extra_name="$(basename -- "$extra")"
    extra_target="${DIST_DIR}/${extra_name}"
    step "Adding extra artifact: $extra_name"
    [ ! -e "$extra_target" ] \
        || die "refusing to overwrite an existing release artifact: $extra_name"
    cp -v --no-clobber -- "$extra" "$extra_target"
    [ -f "$extra_target" ] && cmp -s -- "$extra" "$extra_target" \
        || die "extra artifact copy was skipped, partial, or changed: $extra_name"
    case "$extra_name" in
        *.AppImage) validate_appimage_payload "$extra_target" "$pkgver" ;;
    esac
    record_final_artifact "$extra_target"
done

# ─────────────────────────────────────────────────────────────────────────────
# AppImage zsync control files (E10). Generated from the dist/ copy so the
# checksums in the .zsync describe the exact bytes being published, and BEFORE
# SHA256SUMS so the .zsync itself is checksummed and signed with everything
# else. -u pins the VERSIONED download URL (never releases/latest/): a .zsync
# must name the bytes it indexes, and "latest" changes meaning at every release.
# ─────────────────────────────────────────────────────────────────────────────
for extra in "${EXTRA_ARTIFACTS[@]}"; do
    case "$extra" in
        *.AppImage)
            appimage_name="$(basename "$extra")"
            step "Generating zsync for $appimage_name"
            ( cd "$DIST_DIR" && zsyncmake \
                -u "https://github.com/${RELEASE_REPO}/releases/download/${VERSION}/${appimage_name}" \
                -o "${appimage_name}.zsync" \
                "$appimage_name" ) \
                || die "zsyncmake failed for $appimage_name. Refusing to ship an AppImage without its .zsync."
            [ -s "${DIST_DIR}/${appimage_name}.zsync" ] \
                || die "zsyncmake exited 0 but ${appimage_name}.zsync is missing/empty. Refusing to continue."
            note "${appimage_name}.zsync ($(du -h "${DIST_DIR}/${appimage_name}.zsync" | cut -f1))"
            record_final_artifact "${DIST_DIR}/${appimage_name}.zsync"
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Checksums + signatures
# ─────────────────────────────────────────────────────────────────────────────
step "Revalidating every final artifact byte"
verify_final_artifacts
note "${#FINAL_ARTIFACT_PATHS[@]} artifact(s) unchanged since build/copy validation"

step "Generating SHA256SUMS"
( cd "$DIST_DIR" && sha256sum ./* | sed 's| \./| |' > SHA256SUMS )
cat "${DIST_DIR}/SHA256SUMS"

step "Signing (gpg will prompt you for the passphrase — this is intentional)"
note "Signing SHA256SUMS and ${src_tarball}."
note "If gpg does not prompt, your agent has the passphrase cached from earlier."
echo

# No --batch and no --pinentry-mode loopback: both exist to feed a passphrase in
# from somewhere other than the human, which is the one thing this must not do.
# If there is no TTY to prompt on, that is a hard failure, not a reason to skip.
gpg --local-user "$RELEASE_KEY" --armor --detach-sign --output "${DIST_DIR}/SHA256SUMS.asc" "${DIST_DIR}/SHA256SUMS" \
    || die "signing SHA256SUMS failed. No release artifacts are usable; dist/ is unsigned and must not be published."

# Binary .sig (not .asc) for the tarball: makepkg's validpgpkeys check in
# packaging/aur/PKGBUILD consumes this one.
gpg --local-user "$RELEASE_KEY" --detach-sign --output "${DIST_DIR}/${src_tarball}.sig" "${DIST_DIR}/${src_tarball}" \
    || die "signing $src_tarball failed. The AUR package cannot verify without it; refusing to continue."

step "Verifying our own signatures"
# A signature the maintainer never checked is a signature nobody has checked.
# Verify here so a broken signature fails the release rather than the user.
gpg --verify "${DIST_DIR}/SHA256SUMS.asc" "${DIST_DIR}/SHA256SUMS" \
    || die "SHA256SUMS.asc does NOT verify. Refusing to publish."
gpg --verify "${DIST_DIR}/${src_tarball}.sig" "${DIST_DIR}/${src_tarball}" \
    || die "${src_tarball}.sig does NOT verify. Refusing to publish."
( cd "$DIST_DIR" && sha256sum -c SHA256SUMS ) \
    || die "SHA256SUMS does not match dist/. Refusing to publish."

# ─────────────────────────────────────────────────────────────────────────────
# Publish
# ─────────────────────────────────────────────────────────────────────────────
step "Artifacts ready in dist/"
ls -1 "$DIST_DIR"

release_files=()
while IFS= read -r -d '' f; do
    release_files+=("dist/$(basename "$f")")
done < <(find "$DIST_DIR" -maxdepth 1 -type f -print0 | sort -z)

release_command=(gh release create "$VERSION" --repo "$RELEASE_REPO")
case "$VERSION" in
    *-alpha*|*-beta*|*-rc*) release_command+=(--prerelease) ;;
esac
release_command+=(--title "EdgeHub $VERSION" --notes-file RELEASE_NOTES.md)
release_command+=("${release_files[@]}")

step "Release command"
printf '    '
printf '%q ' "${release_command[@]}"
printf '\n'

cat <<EOF

Reminders (the parts a script must not do for you):
  1. Write RELEASE_NOTES.md first — state that artifacts are signed by
     $RELEASE_KEY and point at README "Verifying your download".
  2. After publishing, refresh packaging/aur/ for the new pkgver and push to AUR:
       cd packaging/aur && updpkgsums && makepkg --printsrcinfo > .SRCINFO
     makepkg will verify ${src_tarball}.sig against validpgpkeys.
  3. If an AppImage is in this release, its .zsync is in dist/ and is uploaded
     by the command above (it lists every dist/ file). Upload BOTH — the
     .zsync without its AppImage (or vice versa) breaks delta updates.
EOF

if [ "$PUBLISH" -eq 1 ]; then
    step "Publishing to GitHub"
    ( cd "$REPO_DIR" && "${release_command[@]}" )
else
    printf '\n\033[1;33mDry run:\033[0m nothing was published. Re-run with --publish, or paste the command above.\n'
fi
