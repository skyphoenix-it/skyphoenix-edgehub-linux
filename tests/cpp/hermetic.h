#ifndef XENEON_TEST_HERMETIC_H
#define XENEON_TEST_HERMETIC_H

// Hermetic-environment gate for the C++ test suite.
//
// WHY THIS EXISTS (a real incident, not a hypothetical):
// these tests link the REAL core and drive the REAL IPC surface. Run under
// ctest they are harmless, because tests/cpp/CMakeLists.txt gives every test an
// ENVIRONMENT with a throwaway HOME/XDG_CONFIG_HOME/XDG_RUNTIME_DIR. Run
// DIRECTLY (`./tests/cpp/manager_backend_sync`) they inherit the developer's
// real environment, and then:
//   * ManagerBackend's ctor calls xeneon_config_load() and the suite later
//     saves defaults over the user's REAL ~/.config/xeneon-edge-hub/config.toml;
//   * ControlServer::start() / the FakeHub helpers call
//     QLocalServer::removeServer("xeneon-edge-hub-ctl"), which UNLINKS the
//     socket of the user's LIVE hub - the hub keeps its listening fd, so it
//     looks healthy while the Manager can never connect again.
// Both happened. The tests must therefore protect themselves rather than trust
// whoever launches them: an unsafe environment is a BUG IN THE INVOCATION, and
// the only safe response is to refuse to run at all.
//
// THE RULE (all of it must hold, or the process dies before main()):
//   1. HOME, XDG_CONFIG_HOME and XDG_RUNTIME_DIR are all set and non-empty.
//   2. Each one exists and, once fully resolved (realpath: symlinks, `..` and
//      all), lies inside one of the sandbox roots:
//        - XENEON_TEST_SANDBOX_ROOT: the build tree's own per-test tmp root,
//          baked in at compile time by add_qt_test() - i.e. the exact place the
//          build system creates the sandboxes ctest hands out;
//        - the system temp dir ($TMPDIR or /tmp), which is what a hand-rolled
//          `mktemp -d` sandbox uses (tests/runtime/ does exactly this).
//   3. As a backstop against a pathological temp root (e.g. TMPDIR pointed at
//      $HOME/.config, which would satisfy #2 while still being lethal), none of
//      the three may be the real home itself or live under the real
//      ~/.config - where "real home" is read from the PASSWD DATABASE via
//      getpwuid(getuid()), NOT from $HOME. $HOME is precisely the variable a
//      sandbox overrides, so trusting it here would defeat the check.
//
// WHY IT CANNOT PASS BY ACCIDENT: the check is positive containment, not a
// heuristic. A normal developer shell has XDG_CONFIG_HOME unset (rule 1 fails)
// or pointing at ~/.config (rules 2 and 3 fail), and XDG_RUNTIME_DIR at
// /run/user/$UID (rule 2 fails). There is no ambient configuration that lands
// all three inside the build tree's tmp root or a temp dir - you only get there
// by deliberately constructing a sandbox, which is the whole point.
//
// USAGE: `XENEON_REQUIRE_HERMETIC_ENV();` once at file scope in every tst_*.cpp.
// It installs a namespace-scope static whose ctor runs during dynamic
// initialisation - BEFORE main(), therefore before QTEST_*_MAIN builds the
// QCoreApplication and before any test object (or any ConfigHandle /
// ControlServer / ManagerBackend it owns) is constructed. That ordering is the
// requirement: QFAIL/QSKIP inside a test slot would already be too late, since
// the damage happens in constructors. Deliberately pure POSIX + <string> - no
// Qt - so it is safe to run this early, with no dependency on Qt's own static
// initialisation.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <climits>
#include <pwd.h>
#include <unistd.h>

namespace xeneon {
namespace test {

// Fully resolve `p`. Returns "" when it does not exist or cannot be resolved -
// callers treat that as "not sandboxed", so a missing dir fails closed.
inline std::string realPathOf(const std::string& p) {
    if (p.empty())
        return std::string();
    char buf[PATH_MAX];
    if (::realpath(p.c_str(), buf) == nullptr)
        return std::string();
    return std::string(buf);
}

inline std::string envOf(const char* name) {
    const char* v = ::getenv(name);
    return (v && *v) ? std::string(v) : std::string();
}

// True when `child` is `root` itself or lives beneath it. Both must already be
// realpath()-resolved, otherwise this is a string game an attacker/typo wins.
inline bool isWithin(const std::string& child, const std::string& root) {
    if (child.empty() || root.empty())
        return false;
    if (child == root)
        return true;
    std::string prefix = root;
    if (prefix.back() != '/')
        prefix.push_back('/');
    return child.compare(0, prefix.size(), prefix) == 0;
}

// The invoking user's REAL home, from the passwd database rather than $HOME -
// see the rule-3 note above.
inline std::string realHomeFromPasswd() {
    if (const struct passwd* pw = ::getpwuid(::getuid()))
        if (pw->pw_dir && *pw->pw_dir)
            return realPathOf(std::string(pw->pw_dir));
    return std::string();
}

inline std::vector<std::string> sandboxRoots() {
    std::vector<std::string> roots;
#ifdef XENEON_TEST_SANDBOX_ROOT
    // The build tree's tests/cpp/tmp - where add_qt_test() creates the per-test
    // sandbox that ctest points the environment at.
    const std::string baked = realPathOf(XENEON_TEST_SANDBOX_ROOT);
    if (!baked.empty())
        roots.push_back(baked);
#endif
    const std::string tmp = envOf("TMPDIR");
    const std::string tempRoot = realPathOf(tmp.empty() ? std::string("/tmp") : tmp);
    if (!tempRoot.empty())
        roots.push_back(tempRoot);
    return roots;
}

// Returns "" when the environment is demonstrably sandboxed, else a human
// diagnosis of the first rule that failed.
inline std::string hermeticFailureReason() {
    const std::vector<std::string> roots = sandboxRoots();
    if (roots.empty())
        return "no usable sandbox root (neither the baked build-tree tmp root "
               "nor the system temp dir could be resolved)";

    const char* kVars[] = {"HOME", "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR"};
    const std::string realHome = realHomeFromPasswd();
    const std::string realConfig = realHome.empty() ? std::string() : realHome + "/.config";

    for (const char* var : kVars) {
        const std::string raw = envOf(var);
        if (raw.empty())
            return std::string(var) + " is not set (a sandbox must set it explicitly)";

        const std::string resolved = realPathOf(raw);
        if (resolved.empty())
            return std::string(var) + "=" + raw + " does not exist / cannot be resolved";

        bool contained = false;
        for (const std::string& root : roots)
            if (isWithin(resolved, root))
                contained = true;
        if (!contained)
            return std::string(var) + "=" + resolved +
                   " is outside every sandbox root (build-tree tmp or system temp dir)";

        // Backstop: containment alone would be satisfied by a temp root that
        // has been aimed at the user's real config.
        if (!realHome.empty() && resolved == realHome)
            return std::string(var) + "=" + resolved + " IS the real home directory";
        if (!realConfig.empty() && isWithin(resolved, realConfig))
            return std::string(var) + "=" + resolved + " is inside the real config dir " + realConfig;
    }
    return std::string();
}

// Refuse to run outside a sandbox.
//
// _Exit (not abort/exit): terminate NOW, with no core dump to litter the
// developer's session and no atexit handlers or static destructors - anything
// that runs on the way out is more code touching the very environment we just
// judged unsafe. 99 distinguishes "refused to run" from any QtTest failure
// count (QtTest reports the number of failed slots, capped at 127).
[[noreturn]] inline void abortUnlessHermeticImpl(const std::string& reason) {
    std::fprintf(stderr,
        "\n"
        "=====================================================================\n"
        " REFUSING TO RUN: this test's environment is not sandboxed.\n"
        "\n"
        " Reason: %s\n"
        "\n"
        " These tests link the real core and drive the real IPC socket. With a\n"
        " real environment they would overwrite ~/.config/xeneon-edge-hub/\n"
        " config.toml and unlink a running hub's control socket.\n"
        "\n"
        " Run them via ctest, which supplies a hermetic environment per test:\n"
        "     ctest --test-dir build --output-on-failure\n"
        "     ./scripts/run_cpp_tests.sh\n"
        "\n"
        " To run one binary by hand, build a sandbox first:\n"
        "     d=$(mktemp -d); mkdir -p \"$d/config\" \"$d/run\"\n"
        "     HOME=$d XDG_CONFIG_HOME=$d/config XDG_RUNTIME_DIR=$d/run \\\n"
        "         QT_QPA_PLATFORM=offscreen ./build/tests/cpp/<test>\n"
        "=====================================================================\n",
        reason.c_str());
    std::fflush(stderr);
    std::_Exit(99);
}

inline void abortUnlessHermetic() {
    const std::string reason = hermeticFailureReason();
    if (!reason.empty())
        abortUnlessHermeticImpl(reason);
}

// Ctor runs during dynamic initialisation, i.e. before main() - see USAGE.
struct HermeticGate {
    HermeticGate() { abortUnlessHermetic(); }
};

}  // namespace test
}  // namespace xeneon

// Place once at file scope in a tst_*.cpp.
#define XENEON_REQUIRE_HERMETIC_ENV() \
    static const ::xeneon::test::HermeticGate xeneon_hermetic_gate_

#endif  // XENEON_TEST_HERMETIC_H
