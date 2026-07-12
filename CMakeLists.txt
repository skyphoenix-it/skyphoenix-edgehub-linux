cmake_minimum_required(VERSION 3.22)
project(XeneonEdgeLinuxHub VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Default to an optimized Release build unless the user overrides it.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
    message(STATUS "No build type specified — defaulting to Release")
endif()

# Enable Link-Time Optimization for Release builds when supported.
include(CheckIPOSupported)
check_ipo_supported(RESULT IPO_SUPPORTED OUTPUT IPO_ERROR)

# Find Qt6
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick Qml DBus VirtualKeyboard Network Svg QuickControls2)

# --- Build Rust Core Library ---

# Detect cargo
find_program(CARGO_EXECUTABLE cargo REQUIRED)
message(STATUS "Found cargo: ${CARGO_EXECUTABLE}")

# Determine rust target dir
set(RUST_CORE_DIR "${CMAKE_SOURCE_DIR}/core")
set(RUST_TARGET_DIR "${RUST_CORE_DIR}/target")
set(RUST_BUILD_TYPE "$<IF:$<CONFIG:Debug>,debug,release>")

if(CMAKE_BUILD_TYPE MATCHES "Debug")
    set(CARGO_BUILD_FLAG "")
    set(RUST_LIB_DIR "${RUST_TARGET_DIR}/debug")
else()
    set(CARGO_BUILD_FLAG "--release")
    set(RUST_LIB_DIR "${RUST_TARGET_DIR}/release")
endif()

set(RUST_LIB "${RUST_LIB_DIR}/libxeneon_core.a")

# Track Rust sources so the static library is rebuilt whenever they change.
# Without this, add_custom_command has no source dependencies and would link a
# stale libxeneon_core.a after edits to the Rust core.
file(GLOB_RECURSE RUST_SOURCES CONFIGURE_DEPENDS "${RUST_CORE_DIR}/src/*.rs")

# Custom command to build the rust library
add_custom_command(
    OUTPUT ${RUST_LIB}
    COMMAND ${CARGO_EXECUTABLE} build ${CARGO_BUILD_FLAG} --manifest-path "${RUST_CORE_DIR}/Cargo.toml"
    WORKING_DIRECTORY "${RUST_CORE_DIR}"
    DEPENDS ${RUST_SOURCES} "${RUST_CORE_DIR}/Cargo.toml"
    COMMENT "Building Rust core library..."
    USES_TERMINAL
)

add_custom_target(rust_core ALL DEPENDS ${RUST_LIB})

# --- Build C++ Application ---
add_executable(xeneon-edge-hub
    app/src/main.cpp
    app/src/mpris_bridge.cpp
    app/src/control_server.cpp
    app/src/orientation_sensor.cpp
    ${CMAKE_SOURCE_DIR}/ui/qml.qrc
    ${CMAKE_SOURCE_DIR}/assets/icons.qrc
    ${CMAKE_SOURCE_DIR}/assets/wallpapers.qrc
)

# Link against the Rust static library
target_link_libraries(xeneon-edge-hub PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Network
    Qt6::Svg
    Qt6::QuickControls2
    Qt6::VirtualKeyboard
    ${RUST_LIB}
    pthread
    dl
)

# Include directories
target_include_directories(xeneon-edge-hub PRIVATE
    "${CMAKE_SOURCE_DIR}/core"
)

# Add dependency on Rust build
add_dependencies(xeneon-edge-hub rust_core)

# QML import path
target_compile_definitions(xeneon-edge-hub PRIVATE
    QT_DISABLE_DEPRECATED_BEFORE=0x060500
)

# Release optimizations: LTO + aggressive optimization + stripped symbols.
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    if(IPO_SUPPORTED)
        set_target_properties(xeneon-edge-hub PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
        message(STATUS "LTO enabled for xeneon-edge-hub")
    else()
        message(STATUS "LTO not supported: ${IPO_ERROR}")
    endif()
    target_compile_options(xeneon-edge-hub PRIVATE -O3)
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    # Strip symbols from the final Release binary to reduce size.
    target_link_options(xeneon-edge-hub PRIVATE -s)
endif()

# --- Companion: Xeneon Edge Manager ---
# Standalone desktop app to manage the hub (layout, appearance, images, display).
# Reuses the Rust core + shared QML store/registry; talks to a running hub over a
# local socket for live updates.
add_executable(xeneon-edge-manager
    manager/src/main.cpp
    ${CMAKE_SOURCE_DIR}/manager/manager.qrc
    ${CMAKE_SOURCE_DIR}/assets/icons.qrc
    ${CMAKE_SOURCE_DIR}/assets/wallpapers.qrc
)

target_link_libraries(xeneon-edge-manager PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::Network
    Qt6::Svg
    Qt6::QuickControls2
    ${RUST_LIB}
    pthread
    dl
)

target_include_directories(xeneon-edge-manager PRIVATE
    "${CMAKE_SOURCE_DIR}/core"
)

add_dependencies(xeneon-edge-manager rust_core)

target_compile_definitions(xeneon-edge-manager PRIVATE
    QT_DISABLE_DEPRECATED_BEFORE=0x060500
)

if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    if(IPO_SUPPORTED)
        set_target_properties(xeneon-edge-manager PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
    endif()
    target_compile_options(xeneon-edge-manager PRIVATE -O3)
endif()

# Install
install(TARGETS xeneon-edge-hub xeneon-edge-manager DESTINATION bin)
install(FILES assets/xeneon-edge-hub.desktop DESTINATION share/applications OPTIONAL)
# udev rule for Edge orientation-sensor access (installed under /usr by default;
# override with -DUDEV_RULES_DIR=/etc/udev/rules.d for a system install).
set(UDEV_RULES_DIR "${CMAKE_INSTALL_PREFIX}/lib/udev/rules.d" CACHE PATH "udev rules directory")
install(FILES packaging/udev/99-xeneon-edge.rules DESTINATION "${UDEV_RULES_DIR}" OPTIONAL)

