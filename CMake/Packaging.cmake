# these are cache variables, so they could be overwritten with -D,

set(CPACK_PACKAGE_NAME "${PROJECT_NAME}"
    CACHE STRING "The resulting package name"
)

set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Simple C++ application"
    CACHE STRING "Package description for the package metadata"
)
set(CPACK_PACKAGE_VENDOR "Some Company")

set(CPACK_VERBATIM_VARIABLES YES)

set(CPACK_PACKAGE_INSTALL_DIRECTORY ${CPACK_PACKAGE_NAME})
SET(CPACK_OUTPUT_FILE_PREFIX "${CMAKE_SOURCE_DIR}/_packages")

set(CPACK_PACKAGE_VERSION_MAJOR ${PROJECT_VERSION_MAJOR})
set(CPACK_PACKAGE_VERSION_MINOR ${PROJECT_VERSION_MINOR})
set(CPACK_PACKAGE_VERSION_PATCH ${PROJECT_VERSION_PATCH})
set(CPACK_PACKAGE_VERSION "${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}")

set(CPACK_PACKAGE_CONTACT "YOUR@E-MAIL.net")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "YOUR NAME")

#set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_RESOURCE_FILE_README "${CMAKE_SOURCE_DIR}/README.md")

if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
set(CPACK_SYSTEM_NAME ${LSB_RELEASE_CODENAME_SHORT})
# package name for deb
# if set, then instead of some-application-0.9.2-Linux.deb
# you'll get some-application_0.9.2_amd64.deb (note the underscores too)
#set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
execute_process(COMMAND dpkg --print-architecture OUTPUT_VARIABLE ARCHITECTURE OUTPUT_STRIP_TRAILING_WHITESPACE)
set( CPACK_DEBIAN_FILE_NAME ${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION}-${CPACK_SYSTEM_NAME}-${ARCHITECTURE}.deb )
# if you want every group to have its own package,
# although the same happens if this is not sent (so it defaults to ONE_PER_GROUP)
# and CPACK_DEB_COMPONENT_INSTALL is set to YES
set(CPACK_COMPONENTS_GROUPING ALL_COMPONENTS_IN_ONE)#ONE_PER_GROUP)
# without this you won't be able to pack only specified component
set(CPACK_DEB_COMPONENT_INSTALL YES)

set(CPACK_EXTERNAL_ENABLE_STAGING YES)
set(CPACK_EXTERNAL_PACKAGE_SCRIPT "${PROJECT_BINARY_DIR}/appimage-generate.cmake")

# linuxdeploy AppImage arch must match the host (PC x86_64 or Pi aarch64).
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(LINUXDEPLOY_ARCH "aarch64")
else()
  set(LINUXDEPLOY_ARCH "x86_64")
endif()

file(GENERATE
  OUTPUT "${PROJECT_BINARY_DIR}/appimage-generate.cmake"
  CONTENT "
include(CMakePrintHelpers)
cmake_print_variables(CPACK_TEMPORARY_DIRECTORY)
cmake_print_variables(CPACK_TOPLEVEL_DIRECTORY)
cmake_print_variables(CPACK_PACKAGE_DIRECTORY)
cmake_print_variables(CPACK_PACKAGE_FILE_NAME)

set(LINUXDEPLOY_ARCH \"${LINUXDEPLOY_ARCH}\")

find_program(LINUXDEPLOY_EXECUTABLE
  NAMES linuxdeploy linuxdeploy-\${LINUXDEPLOY_ARCH}.AppImage
  PATHS \${CPACK_PACKAGE_DIRECTORY}/linuxdeploy)

if (NOT LINUXDEPLOY_EXECUTABLE)
  message(STATUS \"Downloading linuxdeploy (\${LINUXDEPLOY_ARCH})\")
  file(MAKE_DIRECTORY \"\${CPACK_PACKAGE_DIRECTORY}/linuxdeploy\")
  set(LINUXDEPLOY_EXECUTABLE \${CPACK_PACKAGE_DIRECTORY}/linuxdeploy/linuxdeploy-\${LINUXDEPLOY_ARCH}.AppImage)
  set(_LD_URL \"https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-\${LINUXDEPLOY_ARCH}.AppImage\")
  file(DOWNLOAD
      \${_LD_URL}
      \${LINUXDEPLOY_EXECUTABLE}
      INACTIVITY_TIMEOUT 30
      LOG \${CPACK_PACKAGE_DIRECTORY}/linuxdeploy/download.log
      STATUS LINUXDEPLOY_DOWNLOAD)
  list(GET LINUXDEPLOY_DOWNLOAD 0 _LD_STATUS)
  if (NOT _LD_STATUS EQUAL 0)
    set(_LD_URL \"https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-\${LINUXDEPLOY_ARCH}.AppImage\")
    file(DOWNLOAD
        \${_LD_URL}
        \${LINUXDEPLOY_EXECUTABLE}
        INACTIVITY_TIMEOUT 30
        LOG \${CPACK_PACKAGE_DIRECTORY}/linuxdeploy/download.log
        STATUS LINUXDEPLOY_DOWNLOAD)
  endif()
  execute_process(COMMAND chmod +x \${LINUXDEPLOY_EXECUTABLE} COMMAND_ECHO STDOUT)
endif()

# Write the AppImage into _packages/ (absolute path). A relative OUTPUT lands in
# the cpack cwd (build-cmake), which is not where CRT packaging looks.
file(MAKE_DIRECTORY \"${CMAKE_SOURCE_DIR}/_packages\")
set(_APPIMAGE_OUT \"${CMAKE_SOURCE_DIR}/_packages/\${CPACK_PACKAGE_FILE_NAME}.AppImage\")

# NO_STRIP avoids failures on newer ELF; EXTRACT_AND_RUN helps hosts without FUSE (e.g. some Pi setups).
# LDAI_OUTPUT / LINUXDEPLOY_OUTPUT_VERSION are the current names; OUTPUT / VERSION kept for older plugins.
execute_process(
  COMMAND
    \${CMAKE_COMMAND} -E env
      NO_STRIP=1
      APPIMAGE_EXTRACT_AND_RUN=1
      LDAI_OUTPUT=\${_APPIMAGE_OUT}
      OUTPUT=\${_APPIMAGE_OUT}
      LINUXDEPLOY_OUTPUT_VERSION=\${CPACK_PACKAGE_VERSION}
      VERSION=\${CPACK_PACKAGE_VERSION}
    \${LINUXDEPLOY_EXECUTABLE}
    --appimage-extract-and-run
    --appdir=\${CPACK_TEMPORARY_DIRECTORY}
    --executable=$<TARGET_FILE:soh>
    $<$<BOOL:$<TARGET_PROPERTY:soh,APPIMAGE_DESKTOP_FILE>>:--desktop-file=$<TARGET_PROPERTY:soh,APPIMAGE_DESKTOP_FILE>>
    $<$<BOOL:$<TARGET_PROPERTY:soh,APPIMAGE_ICON_FILE>>:--icon-file=$<TARGET_PROPERTY:soh,APPIMAGE_ICON_FILE>>
    --output=appimage
)
")

endif()

include(CPack)
