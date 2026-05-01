#
# RemGlkRs.cmake — build remglk-rs as a static archive via Cargo and expose
# it as the imported target `remglk_capi`.
#
# Inputs (cache vars, all optional):
#   REMGLK_RS_DIR       — path to the remglk-rs checkout
#                         (default: ${CMAKE_SOURCE_DIR}/../remglk-rs)
#   REMGLK_RS_PROFILE   — cargo profile (default: release)
#

set(REMGLK_RS_DIR "${CMAKE_SOURCE_DIR}/../remglk-rs"
    CACHE PATH "Path to the remglk-rs checkout")
set(REMGLK_RS_PROFILE "release"
    CACHE STRING "Cargo profile to build (release | dev)")

if(REMGLK_RS_PROFILE STREQUAL "dev")
    set(_remglk_rs_target_dir "${REMGLK_RS_DIR}/target/debug")
    set(_cargo_profile_arg "")
else()
    set(_remglk_rs_target_dir "${REMGLK_RS_DIR}/target/release")
    set(_cargo_profile_arg "--release")
endif()

set(_remglk_rs_archive
    "${_remglk_rs_target_dir}/${CMAKE_STATIC_LIBRARY_PREFIX}remglk_capi${CMAKE_STATIC_LIBRARY_SUFFIX}")

find_program(CARGO_EXECUTABLE cargo REQUIRED)

# Re-run cargo whenever any tracked source changes. We don't enumerate files;
# Cargo's own staleness check is authoritative. CMake just needs *some*
# dependency to know when to invoke the command.
file(GLOB_RECURSE _remglk_rs_sources
    CONFIGURE_DEPENDS
    "${REMGLK_RS_DIR}/remglk/src/*"
    "${REMGLK_RS_DIR}/remglk_capi/src/*"
    "${REMGLK_RS_DIR}/remglk/Cargo.toml"
    "${REMGLK_RS_DIR}/remglk_capi/Cargo.toml"
    "${REMGLK_RS_DIR}/remglk_capi/build.rs"
    "${REMGLK_RS_DIR}/Cargo.toml")

add_custom_command(
    OUTPUT "${_remglk_rs_archive}"
    COMMAND ${CARGO_EXECUTABLE} build ${_cargo_profile_arg} -p remglk_capi
    WORKING_DIRECTORY "${REMGLK_RS_DIR}"
    DEPENDS ${_remglk_rs_sources}
    COMMENT "Building remglk-rs (${REMGLK_RS_PROFILE})"
    VERBATIM)

add_custom_target(remglk_capi_build DEPENDS "${_remglk_rs_archive}")

add_library(remglk_capi STATIC IMPORTED GLOBAL)
set_target_properties(remglk_capi PROPERTIES
    IMPORTED_LOCATION "${_remglk_rs_archive}"
    INTERFACE_INCLUDE_DIRECTORIES "${REMGLK_RS_DIR}/remglk_capi/src/glk")
add_dependencies(remglk_capi remglk_capi_build)
