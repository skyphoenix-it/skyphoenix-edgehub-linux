#!/usr/bin/env bash
# Injection-free CPack release-identity and fail-closed tooling contract.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMAKE_BIN="${CMAKE_BIN:-$(command -v cmake || true)}"
[ -n "$CMAKE_BIN" ] && [ -x "$CMAKE_BIN" ] || {
  echo "FAIL: cmake is required for the CPack contract" >&2
  exit 1
}

AUDIT_ROOT="$(mktemp -d /tmp/xeneon-cpack-contract.XXXXXX)"
cleanup() {
  case "$AUDIT_ROOT" in
    /tmp/xeneon-cpack-contract.*) rm -rf -- "$AUDIT_ROOT" ;;
    *) echo "REFUSING unsafe cleanup path: $AUDIT_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

VERSION="9.8.7-beta.6"
NATIVE_VERSION="9.8.7~beta.6"
BUILD="$AUDIT_ROOT/build"
PREFLIGHT="$REPO/packaging/cpack/generator-preflight.cmake"

echo "==> CPack release identity + generator preflight"
"$CMAKE_BIN" -S "$REPO" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DXENEON_BUILD_TESTS=OFF \
  -DXENEON_COVERAGE=OFF \
  -DXENEON_QA_HOOKS=OFF \
  -DXENEON_VERSION_OVERRIDE="$VERSION" >/dev/null

CONFIG="$BUILD/CPackConfig.cmake"
grep -Fq "set(CPACK_PACKAGE_VERSION \"$VERSION\")" "$CONFIG"
grep -Fq "set(CPACK_PACKAGE_VERSION_MAJOR \"9\")" "$CONFIG"
grep -Fq "set(CPACK_PACKAGE_VERSION_MINOR \"8\")" "$CONFIG"
grep -Fq "set(CPACK_PACKAGE_VERSION_PATCH \"7\")" "$CONFIG"
grep -Fq "set(CPACK_PACKAGE_FILE_NAME \"xeneon-edge-hub_${VERSION}_" "$CONFIG"
grep -Fq "set(CPACK_XENEON_NATIVE_PACKAGE_VERSION \"$NATIVE_VERSION\")" "$CONFIG"
grep -Fq "set(CPACK_PROJECT_CONFIG_FILE \"$BUILD/xeneon-cpack-generator-preflight.cmake\")" "$CONFIG"
cmp "$PREFLIGHT" "$BUILD/xeneon-cpack-generator-preflight.cmake"
echo "  ok  explicit version binds CPack metadata + archive filename"
echo "  ok  DEB/RPM prerelease order uses $NATIVE_VERSION"

for generator in DEB RPM; do
  case "$generator" in
    DEB)
      tool_args=(
        -DXENEON_CPACK_DPKG="$CMAKE_BIN"
        -DXENEON_CPACK_DPKG_SHLIBDEPS="$CMAKE_BIN")
      missing_args=(
        -DXENEON_CPACK_DPKG=/definitely/missing/dpkg
        -DXENEON_CPACK_DPKG_SHLIBDEPS=/definitely/missing/dpkg-shlibdeps)
      expected="Xeneon CPack DEB version: $NATIVE_VERSION"
      ;;
    RPM)
      tool_args=(-DXENEON_CPACK_RPMBUILD="$CMAKE_BIN")
      missing_args=(-DXENEON_CPACK_RPMBUILD=/definitely/missing/rpmbuild)
      expected="Xeneon CPack RPM version: $NATIVE_VERSION"
      ;;
  esac

  positive="$AUDIT_ROOT/${generator,,}-positive.log"
  "$CMAKE_BIN" \
    -DCPACK_GENERATOR="$generator" \
    -DCPACK_PACKAGE_VERSION="$VERSION" \
    -DCPACK_XENEON_NATIVE_PACKAGE_VERSION="$NATIVE_VERSION" \
    "${tool_args[@]}" -P "$PREFLIGHT" >"$positive" 2>&1
  grep -Fq "$expected" "$positive"

  negative="$AUDIT_ROOT/${generator,,}-negative.log"
  if "$CMAKE_BIN" \
      -DCPACK_GENERATOR="$generator" \
      -DCPACK_PACKAGE_VERSION="$VERSION" \
      -DCPACK_XENEON_NATIVE_PACKAGE_VERSION="$NATIVE_VERSION" \
      "${missing_args[@]}" -P "$PREFLIGHT" >"$negative" 2>&1; then
    echo "FAIL: $generator preflight accepted missing native tooling" >&2
    cat "$negative" >&2
    exit 1
  fi
  grep -Fq "packaging requires" "$negative"
  echo "  ok  $generator accepts present tools and rejects missing tools"
done

echo "RESULT: SUCCESS"
