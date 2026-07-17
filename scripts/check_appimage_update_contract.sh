#!/usr/bin/env bash
# check_appimage_update_contract.sh — guard the AppImage delta-update contract.
#
# WHY THIS EXISTS
#   The AppImage zsync update path spans four files that must agree, and nothing
#   linked them. An audit found every one of them independently broken while all
#   the surrounding tests stayed green, because no test crossed the file
#   boundaries:
#
#     packaging/appimage/build-appimage.sh  names the artifact + sets its version
#     .github/workflows/distro.yml          builds it (and controls git's tags)
#     scripts/release.sh                    zsyncmake's it against a download URL
#     ui/qml/widgets/UpdateChecker.qml      tells the user an update exists
#
#   A full end-to-end proof (build an AppImage, zsyncmake it, serve it, delta-
#   update a real seed, assert byte-identical output) is NOT what this script is.
#   That lives in the appimage-smoke job in distro.yml, because it needs a real
#   AppImage and `zsync`, and neither exists on a typical dev box. This script is
#   the offline half: the cross-file invariants that a unit test cannot see and
#   that CI would only catch after a 20-minute build.
#
# WHAT WOULD MAKE THIS SCRIPT WORTHLESS
#   Being unable to fail. Every check below is proven to fail against a mutated
#   input — see the negative controls in the same commit. Two rules follow:
#     1. NEVER `exit 0` because a tool/file is missing. Absence is a FAIL here,
#        not a skip: a check that quietly passes when its subject is gone is
#        worse than no check, and this repo has been bitten by exactly that.
#     2. NEVER grep a shell file line-wise for a command that may be wrapped
#        across a backslash-newline. A previous lint here was born inert doing
#        precisely that: it grepped for a pattern that was line-wrapped in the
#        target, matched nothing, and passed happily. Continuations are folded
#        (see _fold) before anything is matched.
set -uo pipefail

# XENEON_CONTRACT_REPO points the checks at a mutated copy of the tree. It exists
# so the negative controls can prove each check FAILS when its invariant is
# violated — a lint nobody has watched fail is a lint nobody knows works.
REPO="${XENEON_CONTRACT_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_SH="$REPO/packaging/appimage/build-appimage.sh"
RELEASE_SH="$REPO/scripts/release.sh"
DISTRO_YML="$REPO/.github/workflows/distro.yml"
CHECKER_QML="$REPO/ui/qml/widgets/UpdateChecker.qml"

# The one repo slug the whole update path must agree on.
readonly SLUG="skyphoenix-it/XeneonEdge_Linux"

fails=0
pass() { printf '  \033[1;32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }

# Fold backslash-newline continuations so a wrapped command matches as one line.
_fold() { sed -e ':a' -e '/\\$/{N;s/\\\n//;ta' -e '}' "$1"; }

# A missing subject is a failure, never a skip (rule 1 above).
for f in "$BUILD_SH" "$RELEASE_SH" "$DISTRO_YML" "$CHECKER_QML"; do
    [ -f "$f" ] || { fail "missing subject: ${f#$REPO/}"; }
done
[ "$fails" -eq 0 ] || { printf '\nRESULT: FAILURE (%d)\n' "$fails"; exit 1; }

echo "==> AppImage update contract"

# ─────────────────────────────────────────────────────────────────────────────
# 1. The artifact must be named for the RELEASE version, not project(VERSION),
#    which CMakeLists.txt freezes at 0.1.0 across every commit. Naming it from
#    the frozen field shipped "xeneon-edge-hub-0.1.0-x86_64.AppImage" for every
#    release forever — two different releases, one filename.
#    Executed, not grepped: --print-name runs the real derivation.
# ─────────────────────────────────────────────────────────────────────────────
frozen="$(grep -Po 'project\(.*VERSION \K[0-9.]+' "$REPO/CMakeLists.txt" | head -1)"
name="$(XENEON_VERSION=v9.9.9-test bash "$BUILD_SH" --print-name 2>/dev/null)"
if [ "$name" = "xeneon-edge-hub-9.9.9-test-x86_64.AppImage" ]; then
    pass "artifact name tracks the release version (--print-name: $name)"
else
    fail "build-appimage.sh --print-name gave '$name', expected 'xeneon-edge-hub-9.9.9-test-x86_64.AppImage'"
    fail "  (a name built from the frozen project() version '$frozen' is the bug this catches)"
fi

# The leading v must be stripped, matching the pkgver style of every other
# artifact (release.sh does ${VERSION#v}); "v1.0.0" and "1.0.0" must not both
# appear across the release's filenames.
case "$name" in
    *-v9.9.9*) fail "artifact name keeps the leading 'v' — inconsistent with release.sh's pkgver style" ;;
    *)         pass "leading 'v' is stripped from the artifact version" ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# 2. The binary's own version must be forced to match the filename. cmake
#    otherwise re-derives it from git describe; in a shallow checkout that is a
#    bare sha, which UpdateChecker.qml's SemVer parse rejects — so the AppImage
#    reports "no comparable version" and NEVER surfaces an update.
# ─────────────────────────────────────────────────────────────────────────────
folded_build="$(_fold "$BUILD_SH")"
if printf '%s' "$folded_build" | grep -q -- '-DXENEON_VERSION_OVERRIDE="\$VERSION"'; then
    pass "build passes -DXENEON_VERSION_OVERRIDE=\$VERSION (appVersion == filename)"
else
    fail "build-appimage.sh does not pass -DXENEON_VERSION_OVERRIDE=\"\$VERSION\" to cmake"
    fail "  (without it the binary reports a git-describe sha and can never detect an update)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. git describe needs tags. actions/checkout@v4 defaults to fetch-depth 1,
#    which fetches NONE, and `git describe --always` then silently degrades to a
#    sha instead of erroring. So the appimage job must pin fetch-depth: 0.
#    This is the check that would have caught the shipped bug.
# ─────────────────────────────────────────────────────────────────────────────
appimage_job="$(awk '/^  appimage:/{f=1} /^  appimage-smoke:/{f=0} f' "$DISTRO_YML")"
if [ -z "$appimage_job" ]; then
    fail "could not locate the 'appimage:' job in distro.yml (renamed? this check is now blind)"
elif printf '%s' "$appimage_job" | grep -q 'fetch-depth: 0'; then
    pass "distro.yml appimage job checks out with tags (fetch-depth: 0)"
else
    fail "distro.yml appimage job does not set fetch-depth: 0"
    fail "  (checkout@v4 fetches no tags by default; git describe --always then yields a bare sha)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. The .zsync must pin the VERSIONED download URL. releases/latest/ changes
#    meaning at every release, so a .zsync built against it indexes bytes that
#    will not be there tomorrow.
# ─────────────────────────────────────────────────────────────────────────────
folded_release="$(_fold "$RELEASE_SH")"
# Match any releases/ URL, not just releases/download/: anchoring on the correct
# shape would make the releases/latest branch below unreachable, and a lint branch
# that cannot be reached is a lint branch that does not exist. (Caught by the
# negative control, which failed here for the wrong reason until this was widened.)
zsync_url="$(printf '%s' "$folded_release" | grep -o 'https://github.com/[^"]*/releases/[^"]*' | head -1)"
if [ -z "$zsync_url" ]; then
    fail "release.sh has no GitHub releases URL for zsyncmake -u"
else
    case "$zsync_url" in
        *'/releases/latest/'*) fail "zsyncmake -u points at releases/latest — must pin the tag: $zsync_url" ;;
        *'${VERSION}'*|*'$VERSION'*) pass "zsyncmake -u pins the versioned download URL" ;;
        *) fail "zsyncmake -u URL does not interpolate the release tag: $zsync_url" ;;
    esac
    case "$zsync_url" in
        *"$SLUG"*) pass "zsyncmake -u targets $SLUG" ;;
        *) fail "zsyncmake -u targets the wrong repo (expected $SLUG): $zsync_url" ;;
    esac
    # The URL must name the AppImage it indexes, not a fixed/guessed filename.
    case "$zsync_url" in
        *'${appimage_name}'*) pass "zsyncmake -u names the actual artifact being published" ;;
        *) fail "zsyncmake -u does not interpolate the artifact filename: $zsync_url" ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. The in-app check and the release flow must talk about the same repo. A
#    rename that updated one and not the other would leave the hub polling a
#    repo that no longer publishes the artifact it points users at.
# ─────────────────────────────────────────────────────────────────────────────
if grep -q "api.github.com/repos/$SLUG/releases/latest" "$CHECKER_QML"; then
    pass "UpdateChecker polls $SLUG"
else
    fail "UpdateChecker.qml's releasesUrl does not match $SLUG — the check and the release flow disagree"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. release.sh must refuse to publish an AppImage without its .zsync. This is
#    the guard that keeps a "skipped" zsync from being discovered post-publish.
# ─────────────────────────────────────────────────────────────────────────────
if printf '%s' "$folded_release" | grep -q 'command -v zsyncmake'; then
    pass "release.sh preflights zsyncmake"
else
    fail "release.sh no longer preflights zsyncmake — an AppImage could publish without its .zsync"
fi

echo
if [ "$fails" -ne 0 ]; then
    printf 'RESULT: FAILURE (%d check(s) failed)\n' "$fails"
    exit 1
fi
printf 'RESULT: SUCCESS\n'
