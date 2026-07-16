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
# Usage:
#   scripts/release.sh --version v1.0.0-beta.1            # build + sign + print
#   scripts/release.sh --version v1.0.0-beta.1 --publish  # ... and run gh
#   scripts/release.sh --version v1.0.0-beta.1 --extra path/to/foo.pkg.tar.zst
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

# The EdgeHub release key (SKYPhoenix IT <simon.kreitmayer@skyphoenix-it.com>).
# Full 40-hex fingerprint, not the short id: short ids are forgeable by
# construction, so anything that decides trust must pin the full fingerprint.
# Expires 2028-07-14 — see docs/DISTRIBUTION.md for the rotation policy.
readonly RELEASE_KEY="2F0CAD36DC1D46F3347B7EF293CDC77EACF98990"

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIST_DIR="${REPO_DIR}/dist"
# Named to match the existing cmake-build-*/ rule in .gitignore, and kept out of
# the dev build/ dir so a release build never inherits a stale dev cache (notably
# -DXENEON_QA_HOOKS=ON, which scripts/build.sh sets and releases must not ship).
readonly BUILD_DIR="${REPO_DIR}/cmake-build-release"

VERSION=""
PUBLISH=0
EXTRA_ARTIFACTS=()

die() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
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
case "$VERSION" in
    v*) ;;
    *)  die "version must start with 'v' (e.g. v1.0.0-beta.1), got: $VERSION" ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# Preflight. Everything that can refuse must refuse HERE, before we build or
# write a single artifact — a 20-minute build that dies at the signing step and
# leaves an unsigned dist/ behind is the failure mode this ordering prevents.
# ─────────────────────────────────────────────────────────────────────────────
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

step "Preflight: tag $VERSION"
# git archive must resolve the tag, not HEAD: the tarball users verify has to be
# exactly the tree the tag names, or the signature attests to something nobody
# can reproduce. Tagging stays the maintainer's job (and `git tag -s` is itself
# an interactive, signed act) — this script never creates or moves a tag.
git -C "$REPO_DIR" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null \
    || die "tag $VERSION does not exist locally. Create it first:  git tag -s $VERSION -m '$VERSION'"

command -v gh >/dev/null 2>&1 || note "WARNING: gh not found — the release command will be printed, not run."

step "Preflight: prerequisites"
for tool in cmake cargo sha256sum git; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found (required to build the release artifacts)"
done
HAVE_APPIMAGE=0
for extra in ${EXTRA_ARTIFACTS+"${EXTRA_ARTIFACTS[@]}"}; do
    [ -f "$extra" ] || die "--extra artifact not found: $extra"
    case "$extra" in *.AppImage) HAVE_APPIMAGE=1 ;; esac
done
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
note "all present"

# ─────────────────────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────────────────────
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

pkgver="${VERSION#v}"

step "Building source tarball from tag $VERSION"
# Produced from the tag rather than the working tree so the bytes are a function
# of the tag alone. gzip -n drops the timestamp, which would otherwise make two
# builds of the same tag hash differently for no semantic reason.
src_tarball="xeneon-edge-hub-${pkgver}.tar.gz"
git -C "$REPO_DIR" archive --format=tar --prefix="XeneonEdge_Linux-${pkgver}/" "$VERSION" \
    | gzip -n -9 > "${DIST_DIR}/${src_tarball}"
note "$src_tarball ($(du -h "${DIST_DIR}/${src_tarball}" | cut -f1))"

step "Building binaries (Release)"
# QA hooks stay OFF for anything shipped: scripts/build.sh turns them on for dev
# (screenshot capture / auto-open), and they have no business in a release.
cmake -B "$BUILD_DIR" -S "$REPO_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DXENEON_VERSION_OVERRIDE="$pkgver" \
    -Wno-dev
cmake --build "$BUILD_DIR" -j"$(nproc)"

step "Packaging portable tarball (cpack -G TGZ)"
# Both overrides are required, and neither is redundant. CMakeLists.txt derives
# CPACK_PACKAGE_VERSION and CPACK_PACKAGE_FILE_NAME from PROJECT_VERSION (0.1.0),
# which is deliberately frozen across commits and is NOT the release version —
# without these, a v1.0.0-beta.1 release ships a file called
# "xeneon-edge-hub_0.1.0_x86_64.tar.gz". FILE_NAME is interpolated at configure
# time, so overriding VERSION alone does not rename anything.
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

for extra in ${EXTRA_ARTIFACTS+"${EXTRA_ARTIFACTS[@]}"}; do
    step "Adding extra artifact: $(basename "$extra")"
    cp -v "$extra" "$DIST_DIR/"
done

# ─────────────────────────────────────────────────────────────────────────────
# AppImage zsync control files (E10). Generated from the dist/ copy so the
# checksums in the .zsync describe the exact bytes being published, and BEFORE
# SHA256SUMS so the .zsync itself is checksummed and signed with everything
# else. -u pins the VERSIONED download URL (never releases/latest/): a .zsync
# must name the bytes it indexes, and "latest" changes meaning at every release.
# ─────────────────────────────────────────────────────────────────────────────
for extra in ${EXTRA_ARTIFACTS+"${EXTRA_ARTIFACTS[@]}"}; do
    case "$extra" in
        *.AppImage)
            appimage_name="$(basename "$extra")"
            step "Generating zsync for $appimage_name"
            ( cd "$DIST_DIR" && zsyncmake \
                -u "https://github.com/skyphoenix-it/XeneonEdge_Linux/releases/download/${VERSION}/${appimage_name}" \
                -o "${appimage_name}.zsync" \
                "$appimage_name" ) \
                || die "zsyncmake failed for $appimage_name. Refusing to ship an AppImage without its .zsync."
            [ -s "${DIST_DIR}/${appimage_name}.zsync" ] \
                || die "zsyncmake exited 0 but ${appimage_name}.zsync is missing/empty. Refusing to continue."
            note "${appimage_name}.zsync ($(du -h "${DIST_DIR}/${appimage_name}.zsync" | cut -f1))"
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Checksums + signatures
# ─────────────────────────────────────────────────────────────────────────────
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
while IFS= read -r f; do release_files+=("dist/$(basename "$f")"); done < <(find "$DIST_DIR" -maxdepth 1 -type f | sort)

prerelease_flag=""
case "$VERSION" in
    *-alpha*|*-beta*|*-rc*) prerelease_flag=" --prerelease" ;;
esac

gh_cmd="gh release create $VERSION${prerelease_flag} \\
    --title 'EdgeHub $VERSION' \\
    --notes-file RELEASE_NOTES.md \\
    ${release_files[*]}"

step "Release command"
printf '%s\n' "$gh_cmd"

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
    command -v gh >/dev/null 2>&1 || die "--publish requested but gh is not installed"
    [ -f "${REPO_DIR}/RELEASE_NOTES.md" ] || die "--publish requires RELEASE_NOTES.md at the repo root"
    step "Publishing to GitHub"
    ( cd "$REPO_DIR" && eval "$gh_cmd" )
else
    printf '\n\033[1;33mDry run:\033[0m nothing was published. Re-run with --publish, or paste the command above.\n'
fi
