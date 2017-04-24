cmake_minimum_required(VERSION 3.0.0)
project(rosie)

# set(CMAKE_DEBUG_TARGET_PROPERTIES
#   COMPILE_DEFINITIONS
#   POSITION_INDEPENDENT_CODE
# )

# {{{ Helper cmake modules
# Include FindReadline.cmake
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/Modules)
# }}}

# {{{ Find required packages
find_package(Git REQUIRED)
# For APPLE figure out how to find libedit
find_package(Readline REQUIRED)
# }}}

# {{{ Build time directories
file(MAKE_DIRECTORY
       	${CMAKE_BINARY_DIR}/bin
	${CMAKE_BINARY_DIR}/lib)
set(BUILD_LIB_DIR ${CMAKE_BINARY_DIR}/lib CACHE INTERNAL "Build-time lib directory")
set(BUILD_BIN_DIR ${CMAKE_BINARY_DIR}/bin CACHE INTERNAL "Build-time bin directory")
# }}}

# {{{ Installation helper variables
# Set install directories variables
set(ROSIE_INSTALL_BASE_DIR "${CMAKE_INSTALL_PREFIX}/lib/rosie" CACHE INTERNAL "Rosie base install directory")
set(ROSIE_INSTALL_DOC_DIR "${CMAKE_INSTALL_PREFIX}/share/doc" CACHE INTERNAL "Rosie doc install directory")
set(ROSIE_INSTALL_ROOT_DIR "${CMAKE_INSTALL_PREFIX}/share/rosie" CACHE INTERNAL "Rosie root install directory")
set(ROSIE_INSTALL_BIN_DIR "${ROSIE_INSTALL_BASE_DIR}/bin" CACHE INTERNAL "Rosie base install binary directory")
set(ROSIE_INSTALL_LIB_DIR "${ROSIE_INSTALL_BASE_DIR}/lib" CACHE INTERNAL "Rosie base install library directory")
# }}}

# {{{ Submodules
# Easy way to reference submodules
set(SUBMOD_DIR "${CMAKE_SOURCE_DIR}/submodules")

# Cache LUA_DIR for other CMakeLists.txt (cjson for example)
set(LUA_DIR "${SUBMOD_DIR}/lua" CACHE INTERNAL "Lua path to custom build")
set(JSON_DIR "${SUBMOD_DIR}/lua-cjson")
set(LPEG_DIR "${SUBMOD_DIR}/rosie-lpeg")
set(ARGPARSE_DIR "${SUBMOD_DIR}/argparse")
set(READLINE_DIR "${SUBMOD_DIR}/lua-readline")
set(LUAMODULES_DIR "${SUBMOD_DIR}/lua-modules")

# {{{ git submodule init+update
message(STATUS "Init and update submodules")

execute_process(
	COMMAND ${GIT_EXECUTABLE} submodule update --init --recursive
	WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
# }}}

# {{{ lua + luac
message(STATUS "Processing lua submodule")

# src is the include directory
include_directories(${LUA_DIR}/src)

# All the "CORE" C files
set(LUA_CORE_C
	${LUA_DIR}/src/lapi.c
	${LUA_DIR}/src/lcode.c
	${LUA_DIR}/src/lctype.c
	${LUA_DIR}/src/ldebug.c
	${LUA_DIR}/src/ldo.c
	${LUA_DIR}/src/ldump.c
	${LUA_DIR}/src/lfunc.c
	${LUA_DIR}/src/lgc.c
	${LUA_DIR}/src/llex.c
	${LUA_DIR}/src/lmem.c
	${LUA_DIR}/src/lobject.c
	${LUA_DIR}/src/lopcodes.c
	${LUA_DIR}/src/lparser.c
	${LUA_DIR}/src/lstate.c
	${LUA_DIR}/src/lstring.c
	${LUA_DIR}/src/ltable.c
	${LUA_DIR}/src/ltm.c
	${LUA_DIR}/src/lundump.c
	${LUA_DIR}/src/lvm.c
	${LUA_DIR}/src/lzio.c)

# All the "LIB" C files
set(LUA_LIB_C
	${LUA_DIR}/src/lauxlib.c
	${LUA_DIR}/src/lbaselib.c
	${LUA_DIR}/src/lbitlib.c
	${LUA_DIR}/src/lcorolib.c
	${LUA_DIR}/src/ldblib.c
	${LUA_DIR}/src/liolib.c
	${LUA_DIR}/src/lmathlib.c
	${LUA_DIR}/src/loslib.c
	${LUA_DIR}/src/lstrlib.c
	${LUA_DIR}/src/ltablib.c
	${LUA_DIR}/src/lutf8lib.c
	${LUA_DIR}/src/loadlib.c
	${LUA_DIR}/src/linit.c)

# All C files
set(BASE_C
	${LUA_CORE_C}
	${LUA_LIB_C})

# Create liblua.a
add_library(lua-lib STATIC ${BASE_C})
set_target_properties(lua-lib
	PROPERTIES
	OUTPUT_NAME lua)

if(APPLE)
set_property(
    TARGET lua-lib
    APPEND_STRING
    PROPERTY COMPILE_FLAGS " -DLUA_USE_MACOSX")
elseif(UNIX)
set_property(
    TARGET lua-lib
    APPEND_STRING
    PROPERTY COMPILE_FLAGS " -DLUA_USE_MACOSX")
endif()

# Create lua executable
add_executable(lua-bin ${LUA_DIR}/src/lua.c)
# liblua.a needs to build first
add_dependencies(lua-bin lua-lib)
# Link liblua.a with lua
target_link_libraries(lua-bin lua-lib)
set_target_properties(lua-bin
	PROPERTIES
	OUTPUT_NAME lua)

# Create luac executable
add_executable(luac ${LUA_DIR}/src/luac.c)
# liblua.a builds first
add_dependencies(luac lua-lib)
target_link_libraries(luac lua-lib)

if(${CMAKE_COMPILER_IS_GNUCC} OR ${CMAKE_COMPILER_IS_GNUCXX})
	set_property(
		TARGET lua-bin luac
		APPEND_STRING
		PROPERTY COMPILE_FLAGS " -std=gnu99")
endif()

set_property(
	TARGET lua-bin luac
	APPEND_STRING
	PROPERTY COMPILE_FLAGS " -O2 -Wall -Wextra -DLUA_COMPAT_5_2")

if(APPLE)
	set_property(
		TARGET lua-bin luac
		APPEND_STRING
		PROPERTY COMPILE_FLAGS " -DLUA_USE_MACOSX")
	set_property(
		TARGET lua-lib
		APPEND_STRING
		PROPERTY LINK_FLAGS " -Wl,-E")
	target_link_libraries(lua-lib dl readline)
	target_link_libraries(lua-bin dl readline m)
	target_link_libraries(luac dl readline m)

elseif(UNIX)
	set_property(
		TARGET lua-bin luac
		APPEND_STRING
		PROPERTY COMPILE_FLAGS " -DLUA_USE_LINUX")
	set_property(
		TARGET lua-lib
		APPEND_STRING
		PROPERTY LINK_FLAGS " -Wl,-E")
	target_link_libraries(lua-lib dl readline)
	target_link_libraries(lua-bin dl readline m)
	target_link_libraries(luac dl readline m)
elseif(WIN32)
	# TODO: Add Windows support
	message(FATAL_ERROR "Windows not set up yet")
else()
	message(FATAL_ERROR "No build for ${CMAKE_SYSTEM_NAME}")
endif()
# }}}

# {{{ lua-cjson
message(STATUS "Processing lua-cjson submodule")

# Mostly a copy of lua-cjson's CMakeLists.txt, slight modifications for our needs

option(USE_INTERNAL_FPCONV "Use internal strtod() / g_fmt() code for performance" ON)
option(MULTIPLE_THREADS "Support multi-threaded apps with internal fpconv - recommended" ON)

# Use to collect add_definitions calls
set(CJSON_DEFINITIONS "")

if(NOT USE_INTERNAL_FPCONV)
	set(FPCONV_SOURCES ${JSON_DIR}/fpconv.c)
else()
	string(CONCAT CJSON_DEFINITIONS "${CJSON_DEFINITIONS}" " -DUSE_INTERNAL_FPCONV")
	set(FPCONV_SOURCES ${JSON_DIR}/g_fmt.c ${JSON_DIR}/dtoa.c)

	include(TestBigEndian)
	TEST_BIG_ENDIAN(IEEE_BIG_ENDIAN)
	if(IEEE_BIG_ENDIAN)
		string(CONCAT CJSON_DEFINITIONS "${CJSON_DEFINITIONS}" " -DIEEE_BIG_ENDIAN")
	endif()
	
	if(MULTIPLE_THREADS)
		set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
		find_package(Threads REQUIRED)
		if(NOT CMAKE_USE_PTHREADS_INIT)
			message(FATAL_ERROR
				"Pthreads not found - required by MULTIPLE_THREADS option")
		endif()
		string(CONCAT CJSON_DEFINITIONS "${CJSON_DEFINITIONS}" " -DMULTIPLE_THREADS")
	endif()
endif()

include(CheckSymbolExists)
CHECK_SYMBOL_EXISTS(isinf math.h HAVE_ISINF)
if(NOT HAVE_ISINF)
	string(CONCAT CJSON_DEFINITIONS "${CJSON_DEFINITIONS}" " -DUSE_INTERNAL_ISINF")
endif()

set(CJSON_MODULE_LINK "${CMAKE_THREADS_LIBS_INIT}")

if(WIN32)
	# Win32 modules need to be linked to the Lua library
	set(CJSON_MODULE_LINK lua-lib ${CJSON_MODULE_LINK})
	# Windows sprintf()/stdtod() handle NaN/inf differently. Not supported.
	string(CONCAT CJSON_DEFINITIONS "${CJSON_DEFINITIONS}" " -DDISABLE_INVALID_NUMBERS")
endif()

if(APPLE)
	add_library(cjson MODULE ${JSON_DIR}/lua_cjson.c ${JSON_DIR}/strbuf.c ${FPCONV_SOURCES})
else()
	add_library(cjson SHARED ${JSON_DIR}/lua_cjson.c ${JSON_DIR}/strbuf.c ${FPCONV_SOURCES})
endif()
add_dependencies(cjson lua-lib)
set_target_properties(cjson
	PROPERTIES
	PREFIX "")
set_property(
	TARGET cjson
	APPEND_STRING
	PROPERTY COMPILE_FLAGS " ${CJSON_DEFINITIONS} -fpic -pthread")
if(${CMAKE_COMPILER_IS_GNUCC} OR ${CMAKE_COMPILER_IS_GNUCXX})
	set_property(
		TARGET cjson
		APPEND_STRING
		PROPERTY COMPILE_FLAGS " -std=gnu99")
endif()
set_property(
	TARGET cjson
	APPEND_STRING
	PROPERTY LINK_FLAGS " -pthread")
if(APPLE)
	set_property(
		TARGET cjson
		APPEND_STRING
		PROPERTY LINK_FLAGS " -undefined dynamic_lookup")
endif()
target_link_libraries(cjson ${CJSON_MODULE_LINK})
# }}}

# {{{ rosie-lpeg
message(STATUS "Processing rosie-lpeg submodule")

set(LPEG_C_FILES
	${LPEG_DIR}/src/rcap.c
	${LPEG_DIR}/src/rbuf.c
	${LPEG_DIR}/src/lpvm.c
	${LPEG_DIR}/src/lpcap.c
	${LPEG_DIR}/src/lptree.c
	${LPEG_DIR}/src/lpcode.c)

# TODO: Add DEBUG files and CFLAGS

if(APPLE)
	add_library(lpeg MODULE ${LPEG_C_FILES})
	set_property(TARGET lpeg APPEND_STRING PROPERTY LINK_FLAGS " -undefined	dynamic_lookup")
else()
	add_library(lpeg SHARED ${LPEG_C_FILES})
endif()			 
set_target_properties(lpeg
	PROPERTIES
	PREFIX "")
set_property(
	TARGET lpeg
	APPEND_STRING
	PROPERTY COMPILE_FLAGS " -Wall -Wextra -pedantic -Waggregate-return -Wcast-align -Wcast-qual -Wdisabled-optimization -Wpointer-arith -Wshadow -Wsign-compare -Wundef -Wwrite-strings -Wbad-function-cast -Wdeclaration-after-statement -Wmissing-prototypes -Wnested-externs -Wstrict-prototypes -O2 -std=c99 -fPIC")
# }}}

# {{{ lua-readline
message(STATUS "Processing lua-readline submodule")

if(APPLE)
	option(
		USE_LIBEDIT
		"MACOSX: Use libedit instead of libreadline"
		ON)
endif(APPLE)

if(APPLE)
	add_library(lua-readline MODULE ${READLINE_DIR}/src/lua_readline.c)
else()
	add_library(lua-readline SHARED ${READLINE_DIR}/src/lua_readline.c)
endif()
set_target_properties(lua-readline
	PROPERTIES
	OUTPUT_NAME readline
	PREFIX "")
set_property(
	TARGET lua-readline
	APPEND_STRING
	PROPERTY COMPILE_FLAGS " -fPIC -O2 -Wl,--retain-symbols-file,${READLINE_DIR}/readline.map")

if(APPLE)
	if(USE_LIBEDIT)
		set_property(
			TARGET lua-readline
			APPEND_STRING
			PROPERTY COMPILE_FLAGS " -DLIBEDIT")
	endif(USE_LIBEDIT)
	set_property(
		TARGET lua-readline
		APPEND_STRING
		PROPERTY LINK_FLAGS " -undefined dynamic_lookup")
elseif(UNIX)
	target_link_libraries(lua-readline readline)
elseif(WIN32)
	# TODO: Add Windows
	message(FATAL_ERROR "Windows not set up yet")
else()
	message(FATAL_ERROR "No build for ${CMAKE_SYSTEM_NAME}")
endif()
# }}}

# {{{ lua-argparse
message(STATUS "Processing lua-argparse submodule")

# Since we only compile argparse.lua don't worry about add_subdirectory
# Only check for existing folder
if(NOT EXISTS ${ARGPARSE_DIR})
	message(FATAL_ERROR "argparse submodule folder not found")
endif()

set(ARGPARSE_LUA ${ARGPARSE_DIR}/src/argparse.lua)

# Generate compiled files during build
add_custom_target(argparse ALL
	DEPENDS luac)
add_custom_command(
	TARGET argparse
	PRE_BUILD
	COMMAND $<TARGET_FILE:luac> -o "${BUILD_LIB_DIR}/argparse.luac" "${ARGPARSE_LUA}"
	DEPENDS luac "${ARGPARSE_LUA}"
	COMMENT "Compiling ${ARGPARSE_LUA}"
	VERBATIM)
list(APPEND COMPILED_LUA_FILES argparse.luac)
# }}}
# }}} Submodules

# {{{ Generate Rosie core luac files
message(STATUS "Processing rosie core files")

file(GLOB CORE_LUA ${CMAKE_SOURCE_DIR}/src/core/*.lua)
list(APPEND CORE_LUA ${LUAMODULES_DIR}/recordtype.lua
	    	     ${LUAMODULES_DIR}/submodule.lua
	    	     ${LUAMODULES_DIR}/list.lua
		     ${LUAMODULES_DIR}/termcolor.lua
		     ${LUAMODULES_DIR}/test.lua)

add_custom_target(core-rosie ALL
	DEPENDS luac)
foreach(lua_file ${CORE_LUA})
	get_filename_component(lname ${lua_file} NAME)
	add_custom_command(
		TARGET core-rosie
		PRE_BUILD
		COMMAND $<TARGET_FILE:luac> -o "${BUILD_LIB_DIR}/${lname}c" "${lua_file}"
		DEPENDS luac "${lua_file}"
		COMMENT "Compiling ${lua_file}"
		VERBATIM)
	list(APPEND COMPILED_LUA_FILES ${lname})
endforeach(lua_file ${CORE_LUA})
# }}}

# {{{ Install files
message(STATUS "Processing installation rules")

# generate run-rosie
file(WRITE ${BUILD_BIN_DIR}/rosie
"#!/usr/bin/env bash
exec ${ROSIE_INSTALL_BASE_DIR}/src/run-rosie ${ROSIE_INSTALL_BASE_DIR} \"$@\"")

install(TARGETS lua-bin luac
	DESTINATION ${ROSIE_INSTALL_BIN_DIR}
	PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
install(TARGETS lua-readline lpeg cjson
	DESTINATION ${ROSIE_INSTALL_LIB_DIR})
install(DIRECTORY ${BUILD_LIB_DIR}
	DESTINATION ${ROSIE_INSTALL_BASE_DIR})
install(DIRECTORY ${CMAKE_SOURCE_DIR}/rpl
	DESTINATION ${ROSIE_INSTALL_BASE_DIR})
install(FILES
	${CMAKE_SOURCE_DIR}/CHANGELOG
	${CMAKE_SOURCE_DIR}/CONTRIBUTORS
	${CMAKE_SOURCE_DIR}/LICENSE
	${CMAKE_SOURCE_DIR}/MANIFEST
	${CMAKE_SOURCE_DIR}/README
	${CMAKE_SOURCE_DIR}/VERSION
	DESTINATION ${ROSIE_INSTALL_BASE_DIR})
# install(FILES
# 	${CMAKE_SOURCE_DIR}/src/cli.lua
# 	DESTINATION ${ROSIE_INSTALL_BASE_DIR}/src)
install(PROGRAMS
	${CMAKE_SOURCE_DIR}/src/run-rosie
	DESTINATION ${ROSIE_INSTALL_BASE_DIR}/lib)
install(PROGRAMS
	${BUILD_BIN_DIR}/rosie
	DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)
# }}}

# {{{ Packaging
message(STATUS "Processing packaging information")

set(CPACK_PACKAGE_NAME "rosie")
set(CPACK_PACKAGE_VERSION "1.0")
set(CPACK_PACKAGE_DESCRIPTION_FILE ${CMAKE_SOURCE_DIR}/README)
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "A PEG-based alternative to regular expressions")
set(CPACK_RESOURCE_FILE_LICENSE ${CMAKE_SOURCE_DIR}/LICENSE)

if(NOT CPACK_GENERATOR)
	if(APPLE)
		# apple stuff
	elseif(UNIX)
		# determine possible generators
		# Look for RPM
		find_program(rpmbuild_path "rpmbuild")
		if(rpmbuild_path)
			set(CPACK_GENERATOR RPM)
			set(CPACK_RPM_PACKAGE_LICENSE "MIT")
			set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION "/usr/local;/usr/local/bin;/usr/local/lib")
			if(NOT CPACK_RPM_PACKAGE_RELEASE)
				set(CPACK_RPM_PACKAGE_RELEASE 1)
			endif(NOT CPACK_RPM_PACKAGE_RELEASE)
			set(CPACK_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION}-${CPACK_RPM_PACKAGE_RELEASE}.${CMAKE_SYSTEM_PROCESSOR}")
		endif(rpmbuild_path)
		# Look for DEB
		find_program(dpkg_path "dpkg")
		if(dpkg_path)
			set(CPACK_GENERATOR DEB)
		endif(dpkg_path)
	else()
		# no stuff
	endif()
endif(NOT CPACK_GENERATOR)

if(CPACK_GENERATOR)
	message(STATUS "CPack Generator: ${CPACK_GENERATOR}")
	include(CPack)
endif(CPACK_GENERATOR)

# }}}

