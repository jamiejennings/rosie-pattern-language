# -*- Mode: BSDmakefile; -*-                                          
#
# Makefile for Rosie Pattern Language
#
# © Copyright IBM Corporation 2018.
# LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
# AUTHOR: Jamie A. Jennings
#
#
# 'make' builds rosie within the current directory.
#    bin/rosie is the rosie command line program.
#    src/librosie/binaries contains librosie.so/dylib and librosie.a.
#    src/librosie/python, src/librosie/go, etc. contain sample librosie clients.
#
# 'make install' builds rosie within the current directory, but
# configures librosie and the CLI to look for rosie files in DESTDIR
# (see default value below).  Then the installation files are copied to:
#    $DESTDIR/lib/librosie.a
#    $DESTDIR/lib/librosie.so (or .dylib on OS X)
#    $DESTDIR/lib/rosie/      (rosie files needed at runtime)
#    $DESTDIR/bin/rosie       (cli)
#
# 'make test CLIENTS=all' runs all of the blackbox and whitebox tests.
# For the tests to execute, rosie must have been built with as follows:
#    'make LUADEBUG=1'
#

# -----------------------------------------------------------------------------
# Customizable options
# -----------------------------------------------------------------------------

DESTDIR=/usr/local

# -----------------------------------------------------------------------------
# Platform detection
# -----------------------------------------------------------------------------

REPORTED_PLATFORM=$(shell (uname -o || uname -s) 2> /dev/null)
ifeq ($(REPORTED_PLATFORM), Darwin)
PLATFORM=macosx
else ifeq ($(REPORTED_PLATFORM), GNU/Linux)
PLATFORM=linux
else
$(error Unsupported platform (uname reported "$(REPORTED_PLATFORM)"))
endif

# -----------------------------------------------------------------------------
# References to places in the build directory
# -----------------------------------------------------------------------------

SUBMOD_DIR = $(BUILD_ROOT)/submodules
ROSIEBIN = $(BUILD_ROOT)/bin/rosie

LUA_DIR = $(SUBMOD_DIR)/$(LUA)
LPEG_DIR = $(SUBMOD_DIR)/$(LPEG)
JSON_DIR = $(SUBMOD_DIR)/$(JSON)
LUAMOD_DIR = $(SUBMOD_DIR)/$(LUAMOD)
LIBROSIE_DIR = $(BUILD_ROOT)/src/librosie
READLINE_DIR = $(SUBMOD_DIR)/$(READLINE)

LIBROSIE_A=librosie.a

ifeq ($(PLATFORM),macosx)
PLATFORM=macosx
CC=cc
LIBROSIE_DYLIB=librosie.dylib
else ifeq ($(PLATFORM),linux)
PLATFORM=linux
CC=gcc
LIBROSIE_DYLIB=librosie.so
endif

# Submodules
ARGPARSE = argparse
LUA = lua
LPEG = rosie-lpeg
JSON = lua-cjson
READLINE = lua-readline
LUAMOD = lua-modules

BUILD_ROOT = $(shell pwd)

# -----------------------------------------------------------------------------
# Install layout
# -----------------------------------------------------------------------------

LIBROSIED = $(DESTDIR)/lib
ROSIED = $(DESTDIR)/lib/rosie

# Almost everything gets copied to $(ROSIED): 
#   $(ROSIED)/bin          arch-dependent binaries (e.g. rosie, luac)
#   $(ROSIED)/lib          arch-dependent libraries (e.g. *.luac)
#   $(ROSIED)/rpl          standard library (*.rpl)
#   $(ROSIED)/doc          documentation (html format)
#   $(ROSIED)/extra        editor highlighting files, sample docker files, other things
#   $(ROSIED)/CHANGELOG    change log
#   $(ROSIED)/CONTRIBUTORS project contributors, acknowledgements
#   $(ROSIED)/LICENSE      license
#   $(ROSIED)/README       short text readme (e.g. where to open issues)
#   $(ROSIED)/VERSION      installed version
#
# Rosie executable is compiled during 'make install':
#   $(DESTDIR)/bin/rosie
#
# FUTURE: Links into $(ROSIED)
#   $(ROSIE_ROOT)/rpl  --> $(ROSIED)/rpl
#   $(ROSIE_ROOT)/pkg  --> $(ROSIED)/pkg
#   $(ROSIE_DOC)/rosie --> $(ROSIED)/doc

INSTALL_LIB_DIR = $(ROSIED)/lib
INSTALL_RPL_DIR = $(ROSIED)/rpl
INSTALL_DOC_DIR = $(ROSIED)/doc
INSTALL_EXTRA_DIR = $(ROSIED)/extra
INSTALL_MAN_DIR = $(DESTDIR)/share/man/man1
INSTALL_BIN_DIR = $(DESTDIR)/bin
INSTALL_ROSIEBIN = $(INSTALL_BIN_DIR)/rosie

# -----------------------------------------------------------------------------
# Targets
# -----------------------------------------------------------------------------

ifdef ROSIE_HOME
ROSIE_HOME_GIVEN_ON_COMMAND_LINE = true
else
ROSIE_HOME="$(shell pwd)"
endif

.PHONY:
.NOTPARALLEL:
default: binaries compile sniff

# <sigh> Once we support packages (like RPM), we won't need this test.
# Note that this test should ALWAYS pass on OS X, since it ships with
# readline.
.PHONY: readlinetest
readlinetest:
	@(bash -c 'printf "#include <stdio.h>\n#include <readline/readline.h>\nint main() { }\n"' | \
	           $(CC) -std=gnu99 -lreadline -o /dev/null -xc -) && \
	   echo 'READLINE TEST: libreadline and readline.h appear to be installed' || \
	   (echo 'READLINE TEST: Missing readline library or readline.h' && /usr/bin/false)

# The submodule_sentinel indicates that submodules have been
# initialized in the git sense, i.e. that they have been cloned.  The
# sentile file is a file copied from a submodule repo, so that:
# (1) the submodule must have been checked out, and
# (2) the sentinel will not be newer than the submodule files
submodule_sentinel=submodules/~~present~~ 
submodules = submodules/lua/src/Makefile submodules/lua-cjson/Makefile submodules/rosie-lpeg/src/makefile submodules/lua-readline/Makefile
$(submodules): $(submodule_sentinel)

$(submodule_sentinel): 
	if [ -z $$BREW ]; then git submodule init; fi
	if [ -z $$BREW ]; then git submodule update --checkout; fi
	cd $(LUA_DIR) && rm -f include && ln -sf src include
	cp -p $(LUA_DIR)/README $(submodule_sentinel)
	@$(BUILD_ROOT)/src/build_info.sh "git_submodules" $(BUILD_ROOT) "git" >> $(BUILD_ROOT)/build.log

bin/luac: $(LUA_DIR)/src/lua
	mkdir -p bin
	cp $(LUA_DIR)/src/luac bin

$(LUA_DIR)/src/lua: $(submodules)
	$(MAKE) -C "$(LUA_DIR)" CC=$(CC) $(PLATFORM) $(LINUX_CFLAGS) $(LINUX_LDFLAGS)
	@$(BUILD_ROOT)/src/build_info.sh "lua" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

lpeg_lib=$(LPEG_DIR)/src/lpeg.so
lib/lpeg.so: $(lpeg_lib)
	mkdir -p lib

$(lpeg_lib): $(submodules) 
	$(MAKE) -C "$(LPEG_DIR)/src" CC=$(CC) LUADIR=../../$(LUA)
	@$(BUILD_ROOT)/src/build_info.sh "lpeg" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

json_lib=$(JSON_DIR)/cjson.so
lib/cjson.so: $(json_lib) 

$(json_lib): $(submodules) 
	$(MAKE) -C "$(JSON_DIR)" CC=$(CC)
	@$(BUILD_ROOT)/src/build_info.sh "json" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

lib/argparse.luac: $(submodules) submodules/argparse/src/argparse.lua bin/luac
	bin/luac -o lib/argparse.luac submodules/argparse/src/argparse.lua
	@$(BUILD_ROOT)/src/build_info.sh "argparse" $(BUILD_ROOT) "bin/luac" >> $(BUILD_ROOT)/build.log

readline_lib = $(READLINE_DIR)/readline.so
lib/readline.so: $(readline_lib) 

$(READLINE_DIR)/readline.so: $(submodules)
	$(MAKE) -C "$(READLINE_DIR)" CC=$(CC) LUADIR=../$(LUA)
	@$(BUILD_ROOT)/src/build_info.sh "readline_stub" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

lib/strict.luac: $(LUAMOD_DIR)/strict.lua bin/luac
	bin/luac -o $@ $<

lib/list.luac: $(LUAMOD_DIR)/list.lua bin/luac
	bin/luac -o $@ $<

lib/thread.luac: $(LUAMOD_DIR)/thread.lua bin/luac
	bin/luac -o $@ $<

lib/recordtype.luac: $(LUAMOD_DIR)/recordtype.lua bin/luac
	bin/luac -o $@ $<

lib/submodule.luac: $(LUAMOD_DIR)/submodule.lua bin/luac
	bin/luac -o $@ $<

lib/%.luac: src/core/%.lua bin/luac
	@mkdir -p lib
	bin/luac -o $@ $<
	@$(BUILD_ROOT)/src/build_info.sh $@ $(BUILD_ROOT) "bin/luac" >> $(BUILD_ROOT)/build.log

core_objects := $(patsubst src/core/%.lua,lib/%.luac,$(wildcard src/core/*.lua))
other_objects := lib/argparse.luac lib/list.luac lib/recordtype.luac lib/submodule.luac lib/strict.luac lib/thread.luac
luaobjects := $(core_objects) $(other_objects)

compile: binaries $(luaobjects) bin/luac $(lpeg_lib) $(json_lib) $(readline_lib)

.PHONY:
binaries: $(luaobjects) $(lpeg_lib) $(json_lib) $(readline_lib)
	@$(MAKE) -C $(LIBROSIE_DIR) ROSIE_HOME="$(ROSIE_HOME)"; \
	$(BUILD_ROOT)/src/build_info.sh "binaries" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

$(ROSIEBIN): binaries $(LIBROSIE_DIR)/binaries/rosie
	cp $(LIBROSIE_DIR)/binaries/rosie "$(BUILD_ROOT)/bin/rosie"

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------

# Main install rule
.PHONY: install
install: ROSIE_HOME = "$(DESTDIR)/lib/rosie"
install: $(INSTALL_ROSIEBIN) binaries install_metadata install_luac_bin install_rpl install_librosie install_doc install_extras install_man

# We use mv instead of cp for all the binaries, so that the binaries
# will be rebuilt every time "make install" is run, in case DESTDIR
# has changed.

$(INSTALL_ROSIEBIN): compile binaries
	mkdir -p "$(INSTALL_BIN_DIR)"
	cp "$(LIBROSIE_DIR)/binaries/rosie" "$(INSTALL_ROSIEBIN)"
	rm "$(LIBROSIE_DIR)/binaries/rosie"

# Install librosie
.PHONY: install_librosie
install_librosie: compile binaries
	cp "$(LIBROSIE_DIR)/binaries/$(LIBROSIE_DYLIB)" "$(LIBROSIED)/$(LIBROSIE_DYLIB)"
	rm "$(LIBROSIE_DIR)/binaries/$(LIBROSIE_DYLIB)"
	cp "$(LIBROSIE_DIR)/binaries/$(LIBROSIE_A)" "$(LIBROSIED)/$(LIBROSIE_A)"
	rm "$(LIBROSIE_DIR)/binaries/$(LIBROSIE_A)"

# Install any metadata needed by rosie
.PHONY: install_metadata
install_metadata:
	mkdir -p "$(ROSIED)"
	cp CHANGELOG CONTRIBUTORS LICENSE README VERSION "$(ROSIED)"
	-cp $(BUILD_ROOT)/build.log "$(ROSIED)"

# Install the lua pre-compiled binary files (.luac)
.PHONY: install_luac_bin
install_luac_bin:
	mkdir -p "$(INSTALL_LIB_DIR)"
	cp lib/*.luac "$(INSTALL_LIB_DIR)"

# TODO: Parameterize this, or use a wildcard
# Install the provided RPL patterns
.PHONY: install_rpl
install_rpl:
	mkdir -p "$(INSTALL_RPL_DIR)"
	cp rpl/*.rpl "$(INSTALL_RPL_DIR)"
	mkdir -p "$(INSTALL_RPL_DIR)"/rosie
	cp rpl/rosie/*.rpl "$(INSTALL_RPL_DIR)"/rosie/
	mkdir -p "$(INSTALL_RPL_DIR)"/builtin
	cp rpl/builtin/*.rpl "$(INSTALL_RPL_DIR)"/builtin/
	mkdir -p "$(INSTALL_RPL_DIR)"/Unicode
	cp rpl/Unicode/*.rpl "$(INSTALL_RPL_DIR)"/Unicode/

.PHONY: install_doc
install_doc:
	mkdir -p "$(INSTALL_DOC_DIR)"
	cp -R doc/ "$(INSTALL_DOC_DIR)"

.PHONY: install_extras
install_extras:
	mkdir -p "$(INSTALL_EXTRA_DIR)"
	cp -R extra/ "$(INSTALL_EXTRA_DIR)"

.PHONY: install_man
install_man:
	mkdir -p "$(INSTALL_MAN_DIR)"
	cp doc/man/rosie.1 "$(INSTALL_MAN_DIR)"

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------

.PHONY: uninstall
uninstall:
	@echo "Removing $(INSTALL_ROSIEBIN)"
	@-rm -vf $(INSTALL_ROSIEBIN)
	@echo "Removing $(ROSIED)"
	@-rm -Rvf $(ROSIED)/
	@echo "Removing librosie.a/.so/.dylib from $(LIBROSIED)"
	@-rm -vf "$(LIBROSIED)/$(LIBROSIE_DYLIB)"
	@-rm -vf "$(LIBROSIED)/$(LIBROSIE_A)"
	@echo "Removing rosie man page $(INSTALL_MAN_DIR)"
	@-rm -vf "$(INSTALL_MAN_DIR)/rosie.1"

.PHONY: sniff
sniff: $(ROSIEBIN)
	@if [ -n "$(ROSIE_HOME_GIVEN_ON_COMMAND_LINE)" ]; then \
	    echo "Rosie Pattern Engine was built with a custom ROSIE_HOME path: $(ROSIE_HOME)"; \
	    echo "Skipping sniff test of CLI due to custom path."; \
	    true; \
	else \
	RESULT="$(shell $(ROSIEBIN) version 2> /dev/null)"; \
	EXPECTED="$(shell head -1 $(BUILD_ROOT)/VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
	    echo "";\
            echo "Rosie Pattern Engine $$RESULT built successfully!"; \
	    if [ -z "$$BREW" ]; then \
	      	    echo "    Use 'make install' to install into DESTDIR=$(DESTDIR)"; \
	      	    echo "    Use 'make uninstall' to uninstall from DESTDIR=$(DESTDIR)"; \
	      	    echo "    To run rosie from the build directory, use ./bin/rosie"; \
	            echo "    Try this example, and look for color text output: rosie match all.things test/resolv.conf"; \
		    echo "";\
	    fi; \
            true; \
        else \
            echo "Rosie Pattern Engine test FAILED."; \
	    echo "    Rosie executable is $(ROSIEBIN)"; \
	    echo "    Expected this output: $$EXPECTED"; \
	    if [ -n "$$RESULT" ]; then \
		echo "    But received this output: $$RESULT"; \
	    else \
		echo "    But received no output to stdout."; \
	    fi; \
	    false; \
        fi; \
	fi

# -----------------------------------------------------------------------------
# Tests need to be done with dumb terminal type because the cli and
# repl tests compare the expected output to the actual output byte by
# byte.  With other terminal types, the ANSI color codes emitted by
# Rosie can be munged by the terminal, making some tests fail when
# they should not.

.PHONY: test
test:
	@$(BUILD_ROOT)/test/rosie-has-debug.sh $(ROSIEBIN) 2>/dev/null; \
	if [ "$$?" -ne "0" ]; then \
	echo "Rosie was not built with LUADEBUG support.  Try 'make clean; make LUADEBUG=1'."; \
	exit -1; \
	fi;
	@echo Running tests in test/all.lua
	@(TERM="dumb"; echo "dofile \"$(BUILD_ROOT)/test/all.lua\"" | $(ROSIEBIN) -D)
	@if [ -n "$(CLIENTS)" ]; then \
		echo "** Running librosie client tests **"; \
		$(MAKE) -C "$(LIBROSIE_DIR)" test; \
	else \
		echo "Skipping librosie client tests."; \
		echo "To enable, set CLIENTS=all or CLIENTS=\"C python\" or such (space separated list in quotes)."; \
	fi

.PHONY: clean
clean:
	rm -rf bin/* lib/* librosie.so librosie.dylib librosie.a
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR)/src && make clean
	-cd $(JSON_DIR) && make clean
	-cd $(READLINE_DIR) && rm -f readline.so && rm -f src/lua_readline.o
	-cd $(LIBROSIE_DIR) && make clean
	rm -f build.log

