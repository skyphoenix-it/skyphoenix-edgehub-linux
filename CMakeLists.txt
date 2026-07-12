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
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick Qml DBus VirtualKeyboard)

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
    ${CMAKE_SOURCE_DIR}/ui/qml.qrc
)

# Link against the Rust static library
target_link_libraries(xeneon-edge-hub PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
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

# Install
install(TARGETS xeneon-edge-hub DESTINATION bin)
install(FILES assets/xeneon-edge-hub.desktop DESTINATION share/applications OPTIONAL)

