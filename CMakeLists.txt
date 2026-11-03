cmake_minimum_required(VERSION 3.12...3.27.4)

file(STRINGS src/game/version.h VERSION_LINE
  LIMIT_COUNT 1
  REGEX GAME_RELEASE_VERSION
)

if(VERSION_LINE MATCHES "\"([0-9]+)\\.([0-9]+)\\.([0-9]+|[0-9]+\\.[0-9]+)\"")
  set(VERSION_MAJOR ${CMAKE_MATCH_1})
  set(VERSION_MINOR ${CMAKE_MATCH_2})
  set(VERSION_PATCH ${CMAKE_MATCH_3})
elseif(VERSION_LINE MATCHES "\"([0-9]+)\\.([0-9]+)\"")
  set(VERSION_MAJOR ${CMAKE_MATCH_1})
  set(VERSION_MINOR ${CMAKE_MATCH_2})
  set(VERSION_PATCH "0")
else()
  message(FATAL_ERROR "Couldn't parse version from src/game/version.h")
endif()

# Extra support for CMake pre-3.0
if(NOT POLICY CMP0048)
  set(PROJECT_VERSION_MAJOR ${VERSION_MAJOR})
  set(PROJECT_VERSION_MINOR ${VERSION_MINOR})
  set(PROJECT_VERSION_PATCH ${VERSION_PATCH})
  set(PROJECT_VERSION ${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH})
endif()

project(teeworlds VERSION ${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH})

set(ORIGINAL_CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH})
set(ORIGINAL_CMAKE_REQUIRED_INCLUDES ${CMAKE_REQUIRED_INCLUDES})
set(ORIGINAL_CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES})
set(OWN_CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${PROJECT_SOURCE_DIR}/cmake)
set(CMAKE_MODULE_PATH ${OWN_CMAKE_MODULE_PATH})

if(CMAKE_SIZEOF_VOID_P EQUAL 4)
  set(TARGET_BITS "32")
else()
  set(TARGET_BITS "64")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
  set(TARGET_OS "windows")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(TARGET_OS "linux")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(TARGET_OS "mac")
endif()

include(CheckCCompilerFlag)
include(CheckCXXCompilerFlag)
include(CheckSymbolExists)

check_symbol_exists(__i386 "" TARGET_ARCH_X86_i386)
if(TARGET_ARCH_X86_i386)
  set(TARGET_ARCH x86)
else()
  set(TARGET_ARCH)
endif()

set(AUTO_DEPENDENCIES_DEFAULT OFF)
if(TARGET_OS STREQUAL "windows")
  set(AUTO_DEPENDENCIES_DEFAULT ON)
endif()

option(CLIENT "Compile client" ON)
option(HEADLESS_CLIENT "Build the client without graphics" OFF)
option(DOWNLOAD_DEPENDENCIES "Download dependencies (only available on Windows)" ${AUTO_DEPENDENCIES_DEFAULT})
option(DOWNLOAD_GTEST "Download and compile GTest if not found" ${AUTO_DEPENDENCIES_DEFAULT})
option(PREFER_BUNDLED_LIBS "Prefer bundled libraries over system libraries" ${AUTO_DEPENDENCIES_DEFAULT})
option(DEV "Don't generate stuff necessary for packaging" OFF)

set(OpenGL_GL_PREFERENCE GLVND)

# Set the default build type to Release
if(NOT(CMAKE_BUILD_TYPE))
  if(NOT(DEV))
    set(CMAKE_BUILD_TYPE Release)
  else()
    set(CMAKE_BUILD_TYPE Debug)
  endif()
endif()

set(DBG $<OR:$<CONFIG:Debug>,$<CONFIG:RelWithDebInfo>>)

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  src/game/version.h
)

set(SERVER_EXECUTABLE teeworlds_srv CACHE STRING "Name of the built server executable")
set(CLIENT_EXECUTABLE teeworlds CACHE STRING "Name of the build client executable")

########################################################################
# Download dependencies
########################################################################

find_package(Python3)
if(DOWNLOAD_DEPENDENCIES)
  if(Python3_EXECUTABLE AND TARGET_OS STREQUAL "windows" AND TARGET_BITS)
    set(DOWNLOADS)
    foreach(d freetype sdl)
      if(NOT EXISTS "${PROJECT_SOURCE_DIR}/other/${d}/${TARGET_OS}/lib${TARGET_BITS}")
        list(APPEND DOWNLOADS ${d})
      endif()
    endforeach()
    if(DOWNLOADS)
      message(STATUS "Downloading Freetype and SDL 2")
      execute_process(COMMAND ${Python3_EXECUTABLE} scripts/download.py ${DOWNLOADS}
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
      )
    endif()
  endif()
endif()

########################################################################
# Compiler flags
########################################################################

function(add_c_compiler_flag_if_supported VARIABLE FLAG)
  if(ARGC GREATER 2)
    set(CHECKED_FLAG "${ARGV2}")
  else()
    set(CHECKED_FLAG "${FLAG}")
  endif()
  string(REGEX REPLACE "[^A-Za-z0-9]" "_" CONFIG_VARIABLE "FLAG_SUPPORTED${CHECKED_FLAG}")
  check_c_compiler_flag("${CHECKED_FLAG}" ${CONFIG_VARIABLE})
  if(${CONFIG_VARIABLE})
    if(${VARIABLE})
      set("${VARIABLE}" "${${VARIABLE}};${FLAG}" PARENT_SCOPE)
    else()
      set("${VARIABLE}" "${FLAG}" PARENT_SCOPE)
    endif()
  endif()
endfunction()

if(NOT MSVC)
  # Protect the stack pointer.
  add_c_compiler_flag_if_supported(OUR_FLAGS -fstack-protector-all)

  # Control-flow protection. Should protect against ROP.
  add_c_compiler_flag_if_supported(OUR_FLAGS -fcf-protection)

  # Inaccurate floating point numbers cause problems on mingw-w64-gcc when
  # compiling for x86, might cause problems elsewhere. So don't store floats
  # in registers but keep them at higher accuracy.
  if(TARGET_ARCH STREQUAL "x86")
    add_c_compiler_flag_if_supported(OUR_FLAGS -ffloat-store)
  endif()

  # gcc < 4.10 chokes on _mm_pause on x86 without SSE support.
  if(TARGET_ARCH STREQUAL "x86")
    check_c_source_compiles("#include <immintrin.h>\nint main() { _mm_pause(); return 0; }" MM_PAUSE_WORKS_WITHOUT_MSSE2)
    if(NOT MM_PAUSE_WORKS_WITHOUT_MSSE2)
      add_c_compiler_flag_if_supported(OUR_FLAGS -msse2)
    endif()
  endif()

  if(TARGET_OS STREQUAL "mac")
    add_c_compiler_flag_if_supported(OUR_FLAGS -stdlib=libc++)
    add_c_compiler_flag_if_supported(OUR_FLAGS -mmacosx-version-min=10.7)
  endif()

  add_c_compiler_flag_if_supported(OUR_FLAGS_OWN -Wall)
  if(CMAKE_VERSION VERSION_GREATER 3.3 OR CMAKE_VERSION VERSION_EQUAL 3.3)
    add_c_compiler_flag_if_supported(OUR_FLAGS_OWN
      $<$<COMPILE_LANGUAGE:C>:-Wdeclaration-after-statement>
      -Wdeclaration-after-statement
    )
  endif()
  add_c_compiler_flag_if_supported(OUR_FLAGS_OWN -Wextra)
  add_c_compiler_flag_if_supported(OUR_FLAGS_OWN -Wno-unused-parameter)
  add_c_compiler_flag_if_supported(OUR_FLAGS_OWN -Wno-missing-field-initializers)
  add_c_compiler_flag_if_supported(OUR_FLAGS_OWN -Wformat=2) # Warn about format strings.
  add_c_compiler_flag_if_supported(OUR_FLAGS_DEP -Wno-implicit-function-declaration)
endif()

if(NOT MSVC)
  check_c_compiler_flag("-O2;-Wp,-Werror;-D_FORTIFY_SOURCE=2" DEFINE_FORTIFY_SOURCE) # Some distributions define _FORTIFY_SOURCE by themselves.
endif()

########################################################################
# COMMON FUNCTIONS
########################################################################

function(set_glob VAR GLOBBING EXTS DIRECTORY) # ...
  set(GLOBS)
  foreach(ext ${EXTS})
    list(APPEND GLOBS "${DIRECTORY}/*.${ext}")
  endforeach()
  file(${GLOBBING} GLOB_RESULT ${GLOBS})
  list(SORT GLOB_RESULT)
  set(FILES)
  foreach(file ${ARGN})
    list(APPEND FILES "${PROJECT_SOURCE_DIR}/${DIRECTORY}/${file}")
  endforeach()

  if(NOT FILES STREQUAL GLOB_RESULT)
    message(AUTHOR_WARNING "${VAR} does not contain every file from directory ${DIRECTORY}")
    set(LIST_BUT_NOT_GLOB)
    if(POLICY CMP0057)
      cmake_policy(SET CMP0057 NEW)
      foreach(file ${FILES})
        if(NOT file IN_LIST GLOB_RESULT)
          list(APPEND LIST_BUT_NOT_GLOB ${file})
        endif()
      endforeach()
      if(LIST_BUT_NOT_GLOB)
        message(AUTHOR_WARNING "Entries only present in ${VAR}: ${LIST_BUT_NOT_GLOB}")
      endif()
      set(GLOB_BUT_NOT_LIST)
      foreach(file ${GLOB_RESULT})
        if(NOT file IN_LIST FILES)
          list(APPEND GLOB_BUT_NOT_LIST ${file})
        endif()
      endforeach()
      if(GLOB_BUT_NOT_LIST)
        message(AUTHOR_WARNING "Entries only present in ${DIRECTORY}: ${GLOB_BUT_NOT_LIST}")
      endif()
      if(NOT LIST_BUT_NOT_GLOB AND NOT GLOB_BUT_NOT_LIST)
        message(AUTHOR_WARNING "${VAR} is not alphabetically sorted")
      endif()
    endif()
  endif()

  set(${VAR} ${FILES} PARENT_SCOPE)
endfunction()

function(set_src VAR GLOBBING DIRECTORY) # ...
  set_glob(${VAR} ${GLOBBING} "c;cpp;h" ${DIRECTORY} ${ARGN})
  set(${VAR} ${${VAR}} PARENT_SCOPE)
endfunction()

########################################################################
# INITIALIZE TARGET LISTS
########################################################################

set(TARGETS_OWN)
set(TARGETS_DEP)

set(TARGETS_LINK) # Targets with a linking stage.

########################################################################
# DEPENDENCIES
########################################################################

function(set_extra_dirs_lib VARIABLE NAME)
  set("PATHS_${VARIABLE}_LIBDIR" PARENT_SCOPE)
  set("HINTS_${VARIABLE}_LIBDIR" PARENT_SCOPE)
  if(PREFER_BUNDLED_LIBS)
    set(TYPE HINTS)
  else()
    set(TYPE PATHS)
  endif()
  if(TARGET_BITS AND TARGET_OS)
    set(DIR "other/${NAME}/${TARGET_OS}/lib${TARGET_BITS}")
    set("${TYPE}_${VARIABLE}_LIBDIR" "${DIR}" PARENT_SCOPE)
    set("EXTRA_${VARIABLE}_LIBDIR" "${DIR}" PARENT_SCOPE)
  endif()
endfunction()

function(set_extra_dirs_include VARIABLE NAME LIBRARY)
  set("PATHS_${VARIABLE}_INCLUDEDIR" PARENT_SCOPE)
  set("HINTS_${VARIABLE}_INCLUDEDIR" PARENT_SCOPE)
  is_bundled(IS_BUNDLED "${LIBRARY}")
  if(IS_BUNDLED)
    set("HINTS_${VARIABLE}_INCLUDEDIR" "other/${NAME}/include" "other/${NAME}/include/${TARGET_OS}" PARENT_SCOPE)
  endif()
endfunction()

if(CMAKE_CROSSCOMPILING)
  set(CROSSCOMPILING_NO_CMAKE_SYSTEM_PATH NO_CMAKE_SYSTEM_PATH)
else()
  set(CROSSCOMPILING_NO_CMAKE_SYSTEM_PATH)
endif()

function(is_bundled VARIABLE PATH)
  if(PATH)
    string(FIND "${PATH}" "${PROJECT_SOURCE_DIR}" LOCAL_PATH_POS)
    if(LOCAL_PATH_POS EQUAL 0 AND TARGET_BITS AND TARGET_OS)
      set("${VARIABLE}" ON PARENT_SCOPE)
    else()
      set("${VARIABLE}" OFF PARENT_SCOPE)
    endif()
  else()
    set("${VARIABLE}" OFF PARENT_SCOPE)
  endif()
endfunction()

if(NOT CMAKE_CROSSCOMPILING)
  # Check for PkgConfig once so all the other `find_package` calls can do it
  # quietly.
  find_package(PkgConfig)
endif()
find_package(ZLIB)
find_package(Crypto)
find_package(Freetype)
find_package(Git)
find_package(GTest)
find_package(Pnglite)
find_package(SDL2)
find_package(Threads)
find_package(Wavpack)


if(TARGET_OS AND TARGET_OS STREQUAL "mac")
  find_program(CMAKE_OTOOL otool)
  find_program(DMG dmg)
  find_program(HFSPLUS hfsplus)
  find_program(NEWFS_HFS newfs_hfs)
  if(DMG AND HFSPLUS AND NEWFS_HFS)
    set(DMGTOOLS_FOUND ON)
  else()
    set(DMGTOOLS_FOUND OFF)
  endif()

  find_program(HDIUTIL hdiutil)
  if(HDIUTIL)
    set(HDIUTIL_FOUND ON)
  else()
    set(HDIUTIL_FOUND OFF)
  endif()
endif()

message(STATUS "******** Teeworlds ********")
message(STATUS "Target OS: ${TARGET_OS} ${TARGET_BITS}bit")
message(STATUS "Compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

message(STATUS "Dependencies:")
function(show_dependency_status OUTPUT_NAME NAME)
  if(${NAME}_FOUND)
    if(${NAME}_BUNDLED)
      message(STATUS " * ${OUTPUT_NAME} not found (using bundled version)")
    else()
      message(STATUS " * ${OUTPUT_NAME} found")
    endif()
  else()
    message(STATUS " * ${OUTPUT_NAME} not found")
  endif()
endfunction()

if(TARGET_OS AND TARGET_OS STREQUAL "mac")
  show_dependency_status("Dmg tools" DMGTOOLS)
endif()
show_dependency_status("Freetype" FREETYPE)
if(TARGET_OS AND TARGET_OS STREQUAL "mac")
  show_dependency_status("Hdiutil" HDIUTIL)
endif()
show_dependency_status("OpenSSL Crypto" CRYPTO)
show_dependency_status("Pnglite" PNGLITE)
show_dependency_status("Python3" Python3)
show_dependency_status("SDL2" SDL2)
show_dependency_status("Wavpack" WAVPACK)
show_dependency_status("Zlib" ZLIB)

if(NOT(Python3_FOUND))
  message(SEND_ERROR "You must install Python to compile Teeworlds")
endif()

if(CLIENT AND NOT(FREETYPE_FOUND))
  message(SEND_ERROR "You must install Freetype to compile the Teeworlds client")
endif()
if(CLIENT AND NOT(SDL2_FOUND))
  message(SEND_ERROR "You must install SDL2 to compile the Teeworlds client")
endif()
if(NOT(GTEST_FOUND))
  if(DOWNLOAD_GTEST)
    if(GIT_FOUND)
      message(STATUS "Automatically downloading GTest to be able to run tests")
    else()
      set(DOWNLOAD_GTEST OFF)
      message(WARNING "To automatically download GTest, you have to install Git")
    endif()
  else()
    message(STATUS "To run the tests, you have to install GTest")
  endif()
endif()

if(TARGET_OS STREQUAL "windows")
  set(PLATFORM_CLIENT)
  set(PLATFORM_CLIENT_LIBS opengl32 winmm imm32)
  set(PLATFORM_LIBS ws2_32) # Windows sockets
elseif(TARGET_OS STREQUAL "mac")
  find_library(CARBON Carbon)
  find_library(COCOA Cocoa)
  find_library(OPENGL OpenGL)
  set(PLATFORM_CLIENT
    src/macoslaunch/client.m
  )
  set(PLATFORM_CLIENT_LIBS ${COCOA} ${OPENGL})
  set(PLATFORM_LIBS ${CARBON})
else()
  set(PLATFORM_CLIENT)
  find_package(OpenGL)
  if(CMAKE_VERSION VERSION_LESS 3.10)
    set(PLATFORM_CLIENT_LIBS ${OPENGL_gl_LIBRARY})
  else()
    set(PLATFORM_CLIENT_LIBS ${OPENGL_opengl_LIBRARY})
  endif()
  set(PLATFORM_CLIENT_INCLUDE_DIRS ${OPENGL_INCLUDE_DIR})
  if(TARGET_OS STREQUAL "linux")
    set(PLATFORM_LIBS rt) # clock_gettime for glibc < 2.17
  else()
    set(PLATFORM_LIBS)
  endif()
endif()

########################################################################
# DOWNLOAD GTEST
########################################################################

if(NOT(GTEST_FOUND) AND DOWNLOAD_GTEST)
  set(TEEWORLDS_GTEST_VERSION v1.13.0)
  configure_file(cmake/Download_GTest_CMakeLists.txt.in googletest-download/CMakeLists.txt)
  execute_process(COMMAND ${CMAKE_COMMAND} -G "${CMAKE_GENERATOR}" .
    RESULT_VARIABLE result
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/googletest-download
  )
  if(result)
    message(WARNING "CMake step for googletest failed: ${result}")
    set(DOWNLOAD_GTEST OFF)
  else()
    execute_process(COMMAND ${CMAKE_COMMAND} --build .
      RESULT_VARIABLE result
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/googletest-download
    )
    if(result)
      message(WARNING "Build step for googletest failed: ${result}")
      set(DOWNLOAD_GTEST OFF)
    else()
      # Prevent overriding the parent project's compiler/linker settings on Windows
      set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

      # Add googletest directly to our build. This defines the gtest target.
      add_subdirectory(
        ${PROJECT_BINARY_DIR}/googletest-src
        ${PROJECT_BINARY_DIR}/googletest-build
        EXCLUDE_FROM_ALL
      )

      if(MSVC)
        foreach(target gtest)
          # `/w` disables all warnings. This is needed because `gtest` enables
          # `/WX` (equivalent of `-Werror`) for some reason, breaking builds
          # when MSVS adds new warnings.
          target_compile_options(${target} PRIVATE /w)
          if(POLICY CMP0091)
            set_property(TARGET ${target} PROPERTY MSVC_RUNTIME_LIBRARY MultiThreaded$<${DBG}:Debug>)
          else()
            target_compile_options(${target} PRIVATE $<$<NOT:${DBG}>:/MT> $<${DBG}:/MTd>)
          endif()
        endforeach()
      endif()

      set(GTEST_LIBRARIES gtest)
      set(GTEST_INCLUDE_DIRS)
      if(CMAKE_VERSION VERSION_LESS 2.8.11)
        set(GTEST_INCLUDE_DIRS "${gtest_SOURCE_DIR}/include")
      endif()
    endif()
  endif()
endif()

########################################################################
# DEPENDENCY COMPILATION
########################################################################

set_src(DEP_JSON_SRC GLOB src/engine/external/json-parser json.c json.h)
add_library(json EXCLUDE_FROM_ALL OBJECT ${DEP_JSON_SRC})

set_src(DEP_MD5_SRC GLOB src/engine/external/md5 md5.c md5.h)
add_library(md5 EXCLUDE_FROM_ALL OBJECT ${DEP_MD5_SRC})

list(APPEND TARGETS_DEP json md5)
set(DEP_JSON $<TARGET_OBJECTS:json>)
set(DEP_MD5)
if(NOT CRYPTO_FOUND)
  set(DEP_MD5 $<TARGET_OBJECTS:md5>)
endif()

########################################################################
# DATA
########################################################################

set(EXPECTED_DATA
  audio/foley_body_impact-01.wv
  audio/foley_body_impact-02.wv
  audio/foley_body_impact-03.wv
  audio/foley_body_splat-01.wv
  audio/foley_body_splat-02.wv
  audio/foley_body_splat-03.wv
  audio/foley_body_splat-04.wv
  audio/foley_dbljump-01.wv
  audio/foley_dbljump-02.wv
  audio/foley_dbljump-03.wv
  audio/foley_foot_left-01.wv
  audio/foley_foot_left-02.wv
  audio/foley_foot_left-03.wv
  audio/foley_foot_left-04.wv
  audio/foley_foot_right-01.wv
  audio/foley_foot_right-02.wv
  audio/foley_foot_right-03.wv
  audio/foley_foot_right-04.wv
  audio/foley_land-01.wv
  audio/foley_land-02.wv
  audio/foley_land-03.wv
  audio/foley_land-04.wv
  audio/hook_attach-01.wv
  audio/hook_attach-02.wv
  audio/hook_attach-03.wv
  audio/hook_loop-01.wv
  audio/hook_loop-02.wv
  audio/hook_noattach-01.wv
  audio/hook_noattach-02.wv
  audio/hook_noattach-03.wv
  audio/music_menu.wv
  audio/sfx_ctf_cap_pl.wv
  audio/sfx_ctf_drop.wv
  audio/sfx_ctf_grab_en.wv
  audio/sfx_ctf_grab_pl.wv
  audio/sfx_ctf_rtn.wv
  audio/sfx_hit_strong-01.wv
  audio/sfx_hit_strong-02.wv
  audio/sfx_hit_weak-01.wv
  audio/sfx_hit_weak-02.wv
  audio/sfx_hit_weak-03.wv
  audio/sfx_msg-client.wv
  audio/sfx_msg-highlight.wv
  audio/sfx_msg-server.wv
  audio/sfx_pickup_arm-01.wv
  audio/sfx_pickup_arm-02.wv
  audio/sfx_pickup_arm-03.wv
  audio/sfx_pickup_arm-04.wv
  audio/sfx_pickup_gun.wv
  audio/sfx_pickup_hrt-01.wv
  audio/sfx_pickup_hrt-02.wv
  audio/sfx_pickup_launcher.wv
  audio/sfx_pickup_ninja.wv
  audio/sfx_pickup_sg.wv
  audio/sfx_skid-01.wv
  audio/sfx_skid-02.wv
  audio/sfx_skid-03.wv
  audio/sfx_skid-04.wv
  audio/sfx_spawn_wpn-01.wv
  audio/sfx_spawn_wpn-02.wv
  audio/sfx_spawn_wpn-03.wv
  audio/vo_teefault_cry-01.wv
  audio/vo_teefault_cry-02.wv
  audio/vo_teefault_ninja-01.wv
  audio/vo_teefault_ninja-02.wv
  audio/vo_teefault_ninja-03.wv
  audio/vo_teefault_ninja-04.wv
  audio/vo_teefault_pain_long-01.wv
  audio/vo_teefault_pain_long-02.wv
  audio/vo_teefault_pain_short-01.wv
  audio/vo_teefault_pain_short-02.wv
  audio/vo_teefault_pain_short-03.wv
  audio/vo_teefault_pain_short-04.wv
  audio/vo_teefault_pain_short-05.wv
  audio/vo_teefault_pain_short-06.wv
  audio/vo_teefault_pain_short-07.wv
  audio/vo_teefault_pain_short-08.wv
  audio/vo_teefault_pain_short-09.wv
  audio/vo_teefault_pain_short-10.wv
  audio/vo_teefault_pain_short-11.wv
  audio/vo_teefault_pain_short-12.wv
  audio/vo_teefault_sledge-01.wv
  audio/vo_teefault_sledge-02.wv
  audio/vo_teefault_sledge-03.wv
  audio/vo_teefault_spawn-01.wv
  audio/vo_teefault_spawn-02.wv
  audio/vo_teefault_spawn-03.wv
  audio/vo_teefault_spawn-04.wv
  audio/vo_teefault_spawn-05.wv
  audio/vo_teefault_spawn-06.wv
  audio/vo_teefault_spawn-07.wv
  audio/wp_flump_explo-01.wv
  audio/wp_flump_explo-02.wv
  audio/wp_flump_explo-03.wv
  audio/wp_flump_launch-01.wv
  audio/wp_flump_launch-02.wv
  audio/wp_flump_launch-03.wv
  audio/wp_gun_fire-01.wv
  audio/wp_gun_fire-02.wv
  audio/wp_gun_fire-03.wv
  audio/wp_hammer_hit-01.wv
  audio/wp_hammer_hit-02.wv
  audio/wp_hammer_hit-03.wv
  audio/wp_hammer_swing-01.wv
  audio/wp_hammer_swing-02.wv
  audio/wp_hammer_swing-03.wv
  audio/wp_laser_bnce-01.wv
  audio/wp_laser_bnce-02.wv
  audio/wp_laser_bnce-03.wv
  audio/wp_laser_fire-01.wv
  audio/wp_laser_fire-02.wv
  audio/wp_laser_fire-03.wv
  audio/wp_ninja_attack-01.wv
  audio/wp_ninja_attack-02.wv
  audio/wp_ninja_attack-03.wv
  audio/wp_ninja_attack-04.wv
  audio/wp_ninja_hit-01.wv
  audio/wp_ninja_hit-02.wv
  audio/wp_ninja_hit-03.wv
  audio/wp_ninja_hit-04.wv
  audio/wp_noammo-01.wv
  audio/wp_noammo-02.wv
  audio/wp_noammo-03.wv
  audio/wp_noammo-04.wv
  audio/wp_noammo-05.wv
  audio/wp_shotty_fire-01.wv
  audio/wp_shotty_fire-02.wv
  audio/wp_shotty_fire-03.wv
  audio/wp_switch-01.wv
  audio/wp_switch-02.wv
  audio/wp_switch-03.wv
  countryflags/AD.png
  countryflags/AE.png
  countryflags/AF.png
  countryflags/AG.png
  countryflags/AI.png
  countryflags/AL.png
  countryflags/AM.png
  countryflags/AO.png
  countryflags/AR.png
  countryflags/AS.png
  countryflags/AT.png
  countryflags/AU.png
  countryflags/AW.png
  countryflags/AX.png
  countryflags/AZ.png
  countryflags/BA.png
  countryflags/BB.png
  countryflags/BD.png
  countryflags/BE.png
  countryflags/BF.png
  countryflags/BG.png
  countryflags/BH.png
  countryflags/BI.png
  countryflags/BJ.png
  countryflags/BL.png
  countryflags/BM.png
  countryflags/BN.png
  countryflags/BO.png
  countryflags/BR.png
  countryflags/BS.png
  countryflags/BT.png
  countryflags/BW.png
  countryflags/BY.png
  countryflags/BZ.png
  countryflags/CA.png
  countryflags/CC.png
  countryflags/CD.png
  countryflags/CF.png
  countryflags/CG.png
  countryflags/CH.png
  countryflags/CI.png
  countryflags/CK.png
  countryflags/CL.png
  countryflags/CM.png
  countryflags/CN.png
  countryflags/CO.png
  countryflags/CR.png
  countryflags/CU.png
  countryflags/CV.png
  countryflags/CW.png
  countryflags/CX.png
  countryflags/CY.png
  countryflags/CZ.png
  countryflags/DE.png
  countryflags/DJ.png
  countryflags/DK.png
  countryflags/DM.png
  countryflags/DO.png
  countryflags/DZ.png
  countryflags/EC.png
  countryflags/EE.png
  countryflags/EG.png
  countryflags/EH.png
  countryflags/ER.png
  countryflags/ES.png
  countryflags/ET.png
  countryflags/FI.png
  countryflags/FJ.png
  countryflags/FK.png
  countryflags/FM.png
  countryflags/FO.png
  countryflags/FR.png
  countryflags/GA.png
  countryflags/GB.png
  countryflags/GD.png
  countryflags/GE.png
  countryflags/GF.png
  countryflags/GG.png
  countryflags/GH.png
  countryflags/GI.png
  countryflags/GL.png
  countryflags/GM.png
  countryflags/GN.png
  countryflags/GP.png
  countryflags/GQ.png
  countryflags/GR.png
  countryflags/GS.png
  countryflags/GT.png
  countryflags/GU.png
  countryflags/GW.png
  countryflags/GY.png
  countryflags/HK.png
  countryflags/HN.png
  countryflags/HR.png
  countryflags/HT.png
  countryflags/HU.png
  countryflags/ID.png
  countryflags/IE.png
  countryflags/IL.png
  countryflags/IM.png
  countryflags/IN.png
  countryflags/IO.png
  countryflags/IQ.png
  countryflags/IR.png
  countryflags/IS.png
  countryflags/IT.png
  countryflags/JE.png
  countryflags/JM.png
  countryflags/JO.png
  countryflags/JP.png
  countryflags/KE.png
  countryflags/KG.png
  countryflags/KH.png
  countryflags/KI.png
  countryflags/KM.png
  countryflags/KN.png
  countryflags/KP.png
  countryflags/KR.png
  countryflags/KW.png
  countryflags/KY.png
  countryflags/KZ.png
  countryflags/LA.png
  countryflags/LB.png
  countryflags/LC.png
  countryflags/LI.png
  countryflags/LK.png
  countryflags/LR.png
  countryflags/LS.png
  countryflags/LT.png
  countryflags/LU.png
  countryflags/LV.png
  countryflags/LY.png
  countryflags/MA.png
  countryflags/MC.png
  countryflags/MD.png
  countryflags/ME.png
  countryflags/MF.png
  countryflags/MG.png
  countryflags/MH.png
  countryflags/MK.png
  countryflags/ML.png
  countryflags/MM.png
  countryflags/MN.png
  countryflags/MO.png
  countryflags/MP.png
  countryflags/MQ.png
  countryflags/MR.png
  countryflags/MS.png
  countryflags/MT.png
  countryflags/MU.png
  countryflags/MV.png
  countryflags/MW.png
  countryflags/MX.png
  countryflags/MY.png
  countryflags/MZ.png
  countryflags/NA.png
  countryflags/NC.png
  countryflags/NE.png
  countryflags/NF.png
  countryflags/NG.png
  countryflags/NI.png
  countryflags/NL.png
  countryflags/NO.png
  countryflags/NP.png
  countryflags/NR.png
  countryflags/NU.png
  countryflags/NZ.png
  countryflags/OM.png
  countryflags/PA.png
  countryflags/PE.png
  countryflags/PF.png
  countryflags/PG.png
  countryflags/PH.png
  countryflags/PK.png
  countryflags/PL.png
  countryflags/PM.png
  countryflags/PN.png
  countryflags/PR.png
  countryflags/PS.png
  countryflags/PT.png
  countryflags/PW.png
  countryflags/PY.png
  countryflags/QA.png
  countryflags/RE.png
  countryflags/RO.png
  countryflags/RS.png
  countryflags/RU.png
  countryflags/RW.png
  countryflags/SA.png
  countryflags/SB.png
  countryflags/SC.png
  countryflags/SD.png
  countryflags/SE.png
  countryflags/SG.png
  countryflags/SH.png
  countryflags/SI.png
  countryflags/SK.png
  countryflags/SL.png
  countryflags/SM.png
  countryflags/SN.png
  countryflags/SO.png
  countryflags/SR.png
  countryflags/SS.png
  countryflags/ST.png
  countryflags/SV.png
  countryflags/SX.png
  countryflags/SY.png
  countryflags/SZ.png
  countryflags/TC.png
  countryflags/TD.png
  countryflags/TF.png
  countryflags/TG.png
  countryflags/TH.png
  countryflags/TJ.png
  countryflags/TK.png
  countryflags/TL.png
  countryflags/TM.png
  countryflags/TN.png
  countryflags/TO.png
  countryflags/TR.png
  countryflags/TT.png
  countryflags/TV.png
  countryflags/TW.png
  countryflags/TZ.png
  countryflags/UA.png
  countryflags/UG.png
  countryflags/US.png
  countryflags/UY.png
  countryflags/UZ.png
  countryflags/VA.png
  countryflags/VC.png
  countryflags/VE.png
  countryflags/VG.png
  countryflags/VI.png
  countryflags/VN.png
  countryflags/VU.png
  countryflags/WF.png
  countryflags/WS.png
  countryflags/XBZ.png
  countryflags/XCA.png
  countryflags/XEN.png
  countryflags/XES.png
  countryflags/XGA.png
  countryflags/XNI.png
  countryflags/XSC.png
  countryflags/XWA.png
  countryflags/YE.png
  countryflags/ZA.png
  countryflags/ZM.png
  countryflags/ZW.png
  countryflags/default.png
  countryflags/index.json
  deadtee.png
  editor/automap/desert_main.json
  editor/automap/grass_doodads.json
  editor/automap/grass_main.json
  editor/automap/jungle_deathtiles.json
  editor/automap/jungle_main.json
  editor/automap/winter_main.json
  editor/background.png
  editor/checker.png
  editor/cursor.png
  editor/entities.png
  emoticons.png
  fonts/DejaVuSans.ttf
  fonts/SourceHanSans.ttc
  fonts/index.json
  game.png
  languages/belarusian.json
  languages/bosnian.json
  languages/brazilian_portuguese.json
  languages/breton.json
  languages/bulgarian.json
  languages/catalan.json
  languages/chuvash.json
  languages/czech.json
  languages/danish.json
  languages/dutch.json
  languages/esperanto.json
  languages/estonian.json
  languages/finnish.json
  languages/french.json
  languages/gaelic_scottish.json
  languages/galician.json
  languages/german.json
  languages/greek.json
  languages/hungarian.json
  languages/index.json
  languages/irish.json
  languages/italian.json
  languages/japanese.json
  languages/korean.json
  languages/kyrgyz.json
  languages/license.txt
  languages/lithuanian.json
  languages/norwegian.json
  languages/polish.json
  languages/portuguese.json
  languages/readme.txt
  languages/romanian.json
  languages/russian.json
  languages/serbian.json
  languages/simplified_chinese.json
  languages/slovak.json
  languages/slovenian.json
  languages/spanish.json
  languages/swedish.json
  languages/traditional_chinese.json
  languages/turkish.json
  languages/ukrainian.json
  mapres/bg_cloud1.png
  mapres/bg_cloud2.png
  mapres/bg_cloud3.png
  mapres/desert_doodads.png
  mapres/desert_main.png
  mapres/desert_mountains.png
  mapres/desert_mountains2.png
  mapres/desert_sun.png
  mapres/easter.png
  mapres/generic_deathtiles.png
  mapres/generic_lamps.png
  mapres/generic_shadows.png
  mapres/generic_unhookable.png
  mapres/grass_doodads.png
  mapres/grass_main.png
  mapres/jungle_background.png
  mapres/jungle_deathtiles.png
  mapres/jungle_doodads.png
  mapres/jungle_main.png
  mapres/jungle_midground.png
  mapres/jungle_unhookables.png
  mapres/light.png
  mapres/moon.png
  mapres/mountains.png
  mapres/snow.png
  mapres/stars.png
  mapres/sun.png
  mapres/winter_doodads.png
  mapres/winter_main.png
  mapres/winter_mountains.png
  mapres/winter_mountains2.png
  mapres/winter_mountains3.png
  maps/ctf1.map
  maps/ctf2.map
  maps/ctf3.map
  maps/ctf4.map
  maps/ctf5.map
  maps/ctf6.map
  maps/ctf7.map
  maps/ctf8.map
  maps/dm1.map
  maps/dm2.map
  maps/dm3.map
  maps/dm6.map
  maps/dm7.map
  maps/dm8.map
  maps/dm9.map
  maps/license.txt
  maps/lms1.map
  maps/readme.txt
  particles.png
  race_flag.png
  skins/beaver.json
  skins/bluekitty.json
  skins/bluestripe.json
  skins/body/bat.png
  skins/body/bear.png
  skins/body/beaver.png
  skins/body/dog.png
  skins/body/force.png
  skins/body/fox.png
  skins/body/hippo.png
  skins/body/kitty.png
  skins/body/koala.png
  skins/body/monkey.png
  skins/body/mouse.png
  skins/body/piglet.png
  skins/body/raccoon.png
  skins/body/spiky.png
  skins/body/standard.png
  skins/body/x_ninja.png
  skins/bot.png
  skins/brownbear.json
  skins/bumbler.json
