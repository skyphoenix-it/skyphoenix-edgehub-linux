# C++ (QtTest) test suite for the hub + manager.
#
# Each test is a standalone executable that links the REAL libxeneon_core.a (the
# same static lib the products link — no fake) and the specific extracted logic
# TUs it exercises. Tests run offscreen with a per-test temp XDG_CONFIG_HOME /
# XDG_RUNTIME_DIR so the Rust config round-trips are hermetic, and tests/cpp/
# hermetic.h makes every test REFUSE to start unless it is actually in one of
# those sandboxes (a raw `./tests/cpp/<test>` run once ate a developer's real
# config — see that header).
#
# WARNING — the IPC socket is NOT hermetic, despite the per-test XDG_RUNTIME_DIR.
# ControlServer/ManagerBackend name the socket "xeneon-edge-hub-ctl" (a bare name,
# no '/'), and Qt resolves a bare QLocalServer name via QDir::tempPath() — i.e.
# /tmp — IGNORING XDG_RUNTIME_DIR. So control_server, manager_backend_sync and
# rx_cap all bind, and removeServer(), the REAL /tmp/xeneon-edge-hub-ctl. Running
# them while a hub is live UNLINKS that hub's socket: the hub keeps its listening
# fd and logs nothing, but no client can ever reach it again until it restarts.
# Fixing this needs the socket to resolve to an absolute path under
# XDG_RUNTIME_DIR on BOTH sides (app/src/control_server.cpp + the Manager's
# client in manager/src/manager_backend.h) — an IPC-contract change, not done here.

set(APP_SRC "${CMAKE_SOURCE_DIR}/app/src")
set(MGR_SRC "${CMAKE_SOURCE_DIR}/manager/src")

# add_qt_test(<name>
#     SOURCES  <extra .cpp/.h compiled into the test, beyond tst_<name>.cpp>
#     LINK     <extra Qt6::* / libraries to link>)
# Always links Qt6::Test + the real Rust core, enables AUTOMOC, registers a ctest
# with the offscreen/temp-dir ENVIRONMENT, and (under XENEON_COVERAGE) instruments
# the test exe + the logic it pulls in.
function(add_qt_test name)
    cmake_parse_arguments(T "" "" "SOURCES;LINK" ${ARGN})

    add_executable(${name} tst_${name}.cpp ${T_SOURCES})
    set_target_properties(${name} PROPERTIES AUTOMOC ON)
    target_include_directories(${name} PRIVATE
        "${CMAKE_SOURCE_DIR}/core" "${APP_SRC}" "${MGR_SRC}")
    target_link_libraries(${name} PRIVATE
        Qt6::Test Qt6::Core ${T_LINK} ${RUST_LIB} pthread dl)
    add_dependencies(${name} rust_core)

    # Tell hermetic.h where the build system puts its sandboxes, so a test run
    # outside one can refuse to start. See tests/cpp/hermetic.h.
    target_compile_definitions(${name} PRIVATE
        XENEON_TEST_SANDBOX_ROOT="${CMAKE_CURRENT_BINARY_DIR}/tmp")

    if(XENEON_COVERAGE)
        target_compile_options(${name} PRIVATE --coverage -O0 -g)
        target_link_options(${name} PRIVATE --coverage)
    endif()

    # Per-test hermetic dirs (config round-trips + the IPC socket live here).
    set(_tmp "${CMAKE_CURRENT_BINARY_DIR}/tmp/${name}")
    file(MAKE_DIRECTORY "${_tmp}/config" "${_tmp}/run")

    add_test(NAME ${name} COMMAND ${name})
    set_tests_properties(${name} PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_CONFIG_HOME=${_tmp}/config;XDG_RUNTIME_DIR=${_tmp}/run;HOME=${_tmp}")
endfunction()

# ── Unit (pure logic) ──
add_qt_test(display_match   SOURCES "${APP_SRC}/display_match.cpp")
add_qt_test(metrics_json    SOURCES "${APP_SRC}/display_match.cpp")
add_qt_test(path_sanitize)
add_qt_test(orientation_byte SOURCES "${APP_SRC}/orientation_sensor.cpp")
add_qt_test(reconcile       SOURCES "${MGR_SRC}/reconcile.cpp")
add_qt_test(autostart       SOURCES "${APP_SRC}/autostart.cpp")
# Offline licence FFI. No extra sources: it calls the Rust core directly, which
# is the whole surface the app uses. Qt6::Test already brings QJson*.
add_qt_test(license)

# ── Unit (event loop) ──
# The Q_OBJECT header is listed as a source so AUTOMOC generates its moc.
add_qt_test(config_bridge   SOURCES "${APP_SRC}/config_bridge.h" "${APP_SRC}/autostart.cpp")
add_qt_test(metrics_worker  SOURCES "${APP_SRC}/metrics_worker.h" "${APP_SRC}/display_match.cpp" LINK Qt6::Gui)

# ── Integration (real QLocalSocket) ──
add_qt_test(control_server  SOURCES "${APP_SRC}/control_server.cpp" LINK Qt6::Network)
add_qt_test(manager_backend_sync SOURCES "${MGR_SRC}/manager_backend.h" "${MGR_SRC}/reconcile.cpp" LINK Qt6::Gui Qt6::Network)
add_qt_test(rx_cap          SOURCES "${MGR_SRC}/manager_backend.h" "${MGR_SRC}/reconcile.cpp" LINK Qt6::Gui Qt6::Network)
add_qt_test(single_instance)

# ── Headless negative (crafted FIFO / closed fd, no hardware) ──
add_qt_test(orientation_reopen SOURCES "${APP_SRC}/orientation_sensor.cpp")

# Real IANA zones for QML. The Q_OBJECT header is listed as a source so AUTOMOC
# generates its moc (otherwise: undefined reference to vtable).
add_qt_test(timezone_bridge SOURCES "${APP_SRC}/timezone_bridge.h" LINK Qt6::Gui)

# Distro identity / package count / system age, probed off-thread. Same rule as
# above: the Q_OBJECT header must be a SOURCE (it declares TWO QObjects — the
# bridge and its worker) or AUTOMOC never runs and both vtables go undefined.
add_qt_test(distro_bridge SOURCES "${APP_SRC}/distro_bridge.h" LINK Qt6::Gui)

# ── Smoke: launch the REAL binaries offscreen (main()/screen match/thread lifecycle;
#    doubles as the XENEON_GRAB UAF regression) ──
add_executable(smoke_hub tst_smoke_hub.cpp)
set_target_properties(smoke_hub PROPERTIES AUTOMOC ON)
target_link_libraries(smoke_hub PRIVATE Qt6::Test Qt6::Core Qt6::Gui)
# QA_HOOKS_BUILD tells the test whether the binary it launches can honor
# XENEON_GRAB at all; without the hook the hub never exits and the test would
# fail on a 30s timeout instead of reporting the real reason. See the QSKIP.
target_compile_definitions(smoke_hub PRIVATE
    HUB_BIN="$<TARGET_FILE:xeneon-edge-hub>"
    QA_HOOKS_BUILD=$<BOOL:${XENEON_QA_HOOKS}>
    XENEON_TEST_SANDBOX_ROOT="${CMAKE_CURRENT_BINARY_DIR}/tmp")
add_dependencies(smoke_hub xeneon-edge-hub)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_hub/config"
                    "${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_hub/run")
add_test(NAME smoke_hub COMMAND smoke_hub)
set_tests_properties(smoke_hub PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_hub/config;XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_hub/run;HOME=${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_hub"
    TIMEOUT 60)

add_executable(smoke_manager tst_smoke_manager.cpp)
set_target_properties(smoke_manager PROPERTIES AUTOMOC ON)
target_link_libraries(smoke_manager PRIVATE Qt6::Test Qt6::Core Qt6::Gui)
target_compile_definitions(smoke_manager PRIVATE
    MGR_BIN="$<TARGET_FILE:xeneon-edge-manager>"
    QA_HOOKS_BUILD=$<BOOL:${XENEON_QA_HOOKS}>
    XENEON_TEST_SANDBOX_ROOT="${CMAKE_CURRENT_BINARY_DIR}/tmp")
add_dependencies(smoke_manager xeneon-edge-manager)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_manager/config"
                    "${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_manager/run")
add_test(NAME smoke_manager COMMAND smoke_manager)
set_tests_properties(smoke_manager PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_manager/config;XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_manager/run;HOME=${CMAKE_CURRENT_BINARY_DIR}/tmp/smoke_manager"
    TIMEOUT 60)
