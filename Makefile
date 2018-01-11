## ----------------------------------------------------------------------------- ##
## Customizable options:

DESTDIR=/usr/local

## End of customizable options
## ----------------------------------------------------------------------------- ##

REPORTED_PLATFORM=$(shell (uname -o || uname -s) 2> /dev/null)
ifeq ($(REPORTED_PLATFORM), Darwin)
PLATFORM=macosx
else ifeq ($(REPORTED_PLATFORM), GNU/Linux)
PLATFORM=linux
else
PLATFORM=none
endif

PLATFORMS = linux macosx windows

# Submodules
ARGPARSE = argparse
LUA = lua
LPEG = rosie-lpeg
JSON = lua-cjson
READLINE = lua-readline
LUAMOD = lua-modules


BUILD_ROOT = $(shell pwd)

# Install layout
#
# Almost everything gets copied to $(ROSIED): (e.g. /usr/local/lib/rosie)
#   $(ROSIED)/bin          arch-dependent binaries (e.g. lua, 
#   $(ROSIED)/lib          arch-dependent libraries (e.g. lpeg.so, *.luac)
#   $(ROSIED)/rpl          standard library (*.rpl)
#   $(ROSIED)/pkg          standard library compiled (*.rosie)
#   $(ROSIED)/doc          documentation (html format)
#   $(ROSIED)/extra        editor highlighting files, other things
#   $(ROSIED)/rosie.lua    loads rosie into Lua 5.3 as a lua package
#   $(ROSIED)/CHANGELOG    change log
#   $(ROSIED)/CONTRIBUTORS project contributors, acknowledgements
#   $(ROSIED)/LICENSE      license
#   $(ROSIED)/README       short text readme (e.g. where to open issues)
#   $(ROSIED)/VERSION      installed version
#
# Rosie executable is created by 'make install': $(DESTDIR)/bin/rosie
#
# FUTURE: Links into $(ROSIED)
#   $(ROSIE_ROOT)/rpl  --> $(ROSIED)/rpl
#   $(ROSIE_ROOT)/pkg  --> $(ROSIED)/pkg
#   $(ROSIE_DOC)/rosie --> $(ROSIED)/doc

ROSIED = $(DESTDIR)/lib/rosie
LIBROSIED = $(DESTDIR)/lib
# Future:
# ROSIE_DOC = $(DESTDIR)/share/doc
# ROSIE_ROOT = $(DESTDIR)/share/rosie

.PHONY: default
default: $(PLATFORM)

SUBMOD_DIR = submodules
ROSIEBIN = $(BUILD_ROOT)/bin/rosie
INSTALL_ROSIEBIN = $(DESTDIR)/bin/rosie

BUILD_LUA_PACKAGE = $(BUILD_ROOT)/rosie.lua

LUA_DIR = $(SUBMOD_DIR)/$(LUA)
LPEG_DIR = $(SUBMOD_DIR)/$(LPEG)
JSON_DIR = $(SUBMOD_DIR)/$(JSON)
READLINE_DIR = $(SUBMOD_DIR)/$(READLINE)
LUAMOD_DIR = $(SUBMOD_DIR)/$(LUAMOD)
LIBROSIE_DIR = $(BUILD_ROOT)/src/librosie

INSTALL_BIN_DIR = $(ROSIED)/bin
INSTALL_LIB_DIR = $(ROSIED)/lib
INSTALL_RPL_DIR = $(ROSIED)/rpl
INSTALL_LUA_PACKAGE = $(ROSIED)/rosie.lua
INSTALL_LIBROSIE = $(LIBROSIED)/$(LIBROSIE)
INSTALL_LIBLUA = $(LIBROSIED)/$(LIBLUA)

.PHONY: clean
clean:
	rm -rf bin/* lib/* rosie.lua librosie.so librosie.dylib
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR)/src && make clean
	-cd $(JSON_DIR) && make clean
	-cd $(READLINE_DIR) && rm -f readline.so && rm -f src/lua_readline.o
	-cd $(LIBROSIE_DIR) && make clean
	rm -f build.log

.PHONY: none
none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

## ----------------------------------------------------------------------------- ##

CJSON_MAKE_ARGS = LUA_VERSION=5.3 PREFIX=../$(LUA) 
CJSON_MAKE_ARGS += FPCONV_OBJS="g_fmt.o dtoa.o" CJSON_CFLAGS+=-fpic
CJSON_MAKE_ARGS += USE_INTERNAL_FPCONV=true CJSON_CFLAGS+=-DUSE_INTERNAL_FPCONV
CJSON_MAKE_ARGS += CJSON_CFLAGS+="-pthread -DMULTIPLE_THREADS"
CJSON_MAKE_ARGS += CJSON_LDFLAGS+=-pthread

# Sigh.  Once we support Linux packages (like RPM), we won't need this test.
# Note that this test should ALWAYS pass on OS X, since it ships with readline.
.PHONY: readlinetest
readlinetest:
	@(bash -c 'printf "#include <stdio.h>\n#include <readline/readline.h>\nint main() { }\n"' | \
	           cc -std=gnu99 -lreadline -o /dev/null -xc -) && \
	   echo 'READLINE TEST: libreadline and readline.h appear to be installed' || \
	   (echo 'READLINE TEST: Missing readline library or readline.h' && /usr/bin/false)

ifeq ($(PLATFORM),macosx)
PLATFORM=macosx
CC=cc
CJSON_MAKE_ARGS += CJSON_LDFLAGS="-bundle -undefined dynamic_lookup"
LIBROSIE=librosie.dylib
LIBLUA=liblua.5.3.dylib
endif

.PHONY: macosx
macosx: bin/lua lib/lpeg.so lib/cjson.so lib/readline.so $(LIBROSIE) librosie.a compile sniff

ifeq ($(PLATFORM),linux)
PLATFORM=linux
CC=gcc
CJSON_MAKE_ARGS+=CJSON_CFLAGS+=-std=gnu99
CJSON_MAKE_ARGS+=CJSON_LDFLAGS=-shared
LINUX_CFLAGS=MYCFLAGS=-fPIC
LIBROSIE=librosie.so
LIBLUA=liblua.5.3.so
endif
.PHONY: linux
linux: readlinetest bin/lua lib/lpeg.so lib/cjson.so lib/readline.so $(LIBROSIE) librosie.a compile sniff

.PHONY: windows
windows:
	@echo Windows installation not yet supported.

# The submodule_sentinel indicates that submodules have been
# initialized in the git sense, i.e. that they have been cloned.  The
# sentile file is a file copied from a submodule repo, so that:
# (1) the submodule must have been checked out, and
# (2) the sentinel will not be newer than the submodule files
submodule_sentinel=submodules/~~present~~ 
submodules = submodules/lua/src/Makefile submodules/lua-cjson/Makefile submodules/rosie-lpeg/src/makefile submodules/lua-readline/Makefile
$(submodules): $(submodule_sentinel)

$(submodule_sentinel): 
	git submodule init
	git submodule update --checkout
	cd $(LUA_DIR) && rm -f include && ln -sf src include
	cp -p $(LUA_DIR)/README $(submodule_sentinel)
	@$(BUILD_ROOT)/src/build_info.sh "git_submodules" $(BUILD_ROOT) "git" >> $(BUILD_ROOT)/build.log

bin/lua: $(LUA_DIR)/src/lua
	mkdir -p bin
	cp $(LUA_DIR)/src/lua bin

$(LUA_DIR)/src/lua: $(submodules)
	cd $(LUA_DIR) && $(MAKE) CC=$(CC) $(PLATFORM) $(LINUX_CFLAGS) $(LINUX_LDFLAGS)
	@$(BUILD_ROOT)/src/build_info.sh "lua" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

bin/luac: bin/lua
	cp $(LUA_DIR)/src/luac bin

lpeg_lib=$(LPEG_DIR)/src/lpeg.so
lib/lpeg.so: $(lpeg_lib)
	mkdir -p lib
	cp $(lpeg_lib) lib

$(lpeg_lib): $(submodules) 
	cd $(LPEG_DIR)/src && $(MAKE) CC=$(CC) LUADIR=../../$(LUA)
	@$(BUILD_ROOT)/src/build_info.sh "lpeg" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

json_lib=$(JSON_DIR)/cjson.so
lib/cjson.so: $(json_lib) 
	mkdir -p lib
	cp $(json_lib) lib

$(json_lib): $(submodules) 
	cd $(JSON_DIR) && $(MAKE) CC=$(CC) $(CJSON_MAKE_ARGS)
	@$(BUILD_ROOT)/src/build_info.sh "json" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

lib/argparse.luac: $(submodules) submodules/argparse/src/argparse.lua bin/luac
	bin/luac -o lib/argparse.luac submodules/argparse/src/argparse.lua
	@$(BUILD_ROOT)/src/build_info.sh "argparse" $(BUILD_ROOT) "bin/luac" >> $(BUILD_ROOT)/build.log

readline_lib = $(READLINE_DIR)/readline.so
lib/readline.so: $(readline_lib) 
	mkdir -p lib
	cp $(readline_lib) lib

$(READLINE_DIR)/readline.so: $(submodules)
	cd $(READLINE_DIR) && $(MAKE) CC=$(CC) LUADIR=../$(LUA)
	@$(BUILD_ROOT)/src/build_info.sh "readline_stub" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

$(EXECROSIE): compile
	@/usr/bin/env echo "Creating $(EXECROSIE)"
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(EXECROSIE)"
	@/usr/bin/env echo -n "$(HOME)/lib/run-rosie $(HOME)" >> "$(EXECROSIE)"
	@/usr/bin/env echo ' "$$@"' >> "$(EXECROSIE)"
	@chmod 755 "$(EXECROSIE)"

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
	bin/luac -o $@ $<
	@$(BUILD_ROOT)/src/build_info.sh $@ $(BUILD_ROOT) "bin/luac" >> $(BUILD_ROOT)/build.log

lib/run-rosie:
	mkdir -p lib
	@cp src/run-rosie lib

core_objects := $(patsubst src/core/%.lua,lib/%.luac,$(wildcard src/core/*.lua))
other_objects := lib/argparse.luac lib/list.luac lib/recordtype.luac lib/submodule.luac lib/strict.luac lib/thread.luac
luaobjects := $(core_objects) $(other_objects)

librosie.dylib:
librosie.so:
librosie.a: $(luaobjects) lib/lpeg.so lib/cjson.so
	cd $(LIBROSIE_DIR) && $(MAKE) CC=$(CC)
	@$(BUILD_ROOT)/src/build_info.sh "librosie" $(BUILD_ROOT) $(CC) >> $(BUILD_ROOT)/build.log

compile: $(luaobjects) bin/luac bin/lua lib/lpeg.so lib/cjson.so lib/readline.so lib/run-rosie

# The PHONY declaration below will force the creation of bin/rosie every time.  This is needed
# only because the user may move the working directory.  When that happens, the user should
# be able to run 'make' again to reconstruct a new bin/rosie script (which contains a
# reference to the working directory).
.PHONY: $(ROSIEBIN)
$(ROSIEBIN): compile
	@/usr/bin/env echo "Creating $(ROSIEBIN)"
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(ROSIEBIN)"
	@/usr/bin/env echo -n "exec $(BUILD_ROOT)/lib/run-rosie " >> "$(ROSIEBIN)"
	@/usr/bin/env echo -n ' "$$0"' >> "$(ROSIEBIN)"
	@/usr/bin/env echo -n " $(BUILD_ROOT)" >> "$(ROSIEBIN)"
	@/usr/bin/env echo ' "$$@"' >> "$(ROSIEBIN)"
	@mkdir -p lib
	@chmod 755 "$(ROSIEBIN)"
	@/usr/bin/env echo "Creating $(BUILD_LUA_PACKAGE)"
	@/usr/bin/env echo "local home = \"$(BUILD_ROOT)\"" > "$(BUILD_LUA_PACKAGE)"
	@/usr/bin/env echo "return dofile(home .. \"/lib/boot.luac\")(home)" >> "$(BUILD_LUA_PACKAGE)"

# See comment above re: ROSIEBIN
.PHONY: $(INSTALL_ROSIEBIN)
$(INSTALL_ROSIEBIN): compile
	@/usr/bin/env echo "Creating $(INSTALL_ROSIEBIN)"
	@mkdir -p "$(DESTDIR)"/bin
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo -n "exec $(ROSIED)/lib/run-rosie " >> "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo -n ' "$$0"' >> "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo -n " $(ROSIED)" >> "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo ' "$$@"' >> "$(INSTALL_ROSIEBIN)"
	@mkdir -p "$(ROSIED)"
	@chmod 755 "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo "Creating $(INSTALL_LUA_PACKAGE)"
	@/usr/bin/env echo "local home = \"$(ROSIED)\"" > "$(INSTALL_LUA_PACKAGE)"
	@/usr/bin/env echo "return dofile(home .. \"/lib/boot.luac\")(home)" >> "$(INSTALL_LUA_PACKAGE)"

# Install the lua interpreter
.PHONY: install_lua
install_lua: bin/lua
	mkdir -p "$(INSTALL_BIN_DIR)"
	cp bin/lua "$(INSTALL_BIN_DIR)"

# Install all of the shared objects
.PHONY: install_so
install_so: lib/lpeg.so lib/cjson.so lib/readline.so
	mkdir -p "$(INSTALL_LIB_DIR)"
	cp lib/lpeg.so lib/cjson.so lib/readline.so "$(INSTALL_LIB_DIR)"

# Install any metadata needed by rosie
.PHONY: install_metadata
install_metadata:
	mkdir -p "$(ROSIED)"
	cp CHANGELOG CONTRIBUTORS LICENSE README VERSION "$(ROSIED)"
	-cp $(BUILD_ROOT)/build.log "$(ROSIED)"

# Install the real run script, and the rosie.lua file
.PHONY: install_run_script
install_run_script:
	mkdir -p "$(INSTALL_LIB_DIR)"
	@cp src/run-rosie "$(INSTALL_LIB_DIR)"

# Install the lua pre-compiled binary files (.luac)
.PHONY: install_luac_bin
install_luac_bin:
	mkdir -p "$(INSTALL_LIB_DIR)"
	cp lib/*.luac "$(INSTALL_LIB_DIR)"

# Install the provided RPL patterns
.PHONY: install_rpl
install_rpl:
	mkdir -p "$(INSTALL_RPL_DIR)"
	cp rpl/*.rpl "$(INSTALL_RPL_DIR)"
	mkdir -p "$(INSTALL_RPL_DIR)"/rosie
	cp rpl/rosie/*.rpl "$(INSTALL_RPL_DIR)"/rosie/

# Install librosie
.PHONY: install_librosie
install_librosie: $(LIBROSIE)
	cp "$(LIBROSIE_DIR)/$(LIBROSIE)" "$(INSTALL_LIBROSIE)"
	cp "$(LIBROSIE_DIR)/$(LIBLUA)" "$(INSTALL_LIBLUA)"

# Main install rule
.PHONY: install
install: $(INSTALL_ROSIEBIN) install_lua install_so install_metadata \
	install_run_script install_luac_bin install_rpl install_librosie

.PHONY: uninstall
uninstall:
	@echo "Removing $(INSTALL_ROSIEBIN)"
	@-rm -vf $(INSTALL_ROSIEBIN)
	@echo "Removing $(ROSIED)"
	@-rm -Rvf $(ROSIED)/

.PHONY: sniff
sniff: $(ROSIEBIN)
	@RESULT="$(shell $(ROSIEBIN) --version 2> /dev/null)"; \
	EXPECTED="$(shell head -1 $(BUILD_ROOT)/VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
	    echo "";\
            echo "Rosie Pattern Engine built successfully!"; \
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
		echo "    But received no output."; \
	    fi; \
	    false; \
        fi

# -----------------------------------------------------------------------------
# Tests need to be done with dumb terminal type because the cli and
# repl tests compare the expected output to the actual output byte by
# byte.  With other terminal types, the ANSI color codes emitted by
# Rosie can be munged by the terminal, making some tests fail when
# they should not.

.PHONY: test
test:
	@echo Running tests in test/all.lua
	@(TERM="dumb"; echo "dofile \"$(BUILD_ROOT)/test/all.lua\"" | $(ROSIEBIN) -D)
	@if [ -n "$(CLIENTS)" ]; then \
		echo "** Running librosie client tests **"; \
		cd $(LIBROSIE_DIR) && $(MAKE) test; \
	else \
		echo "Skipping librosie client tests."; \
		echo "To enable, set CLIENTS=all or CLIENTS=\"C python\" or such (space separated list in quotes)."; \
	fi

.PHONY: installtest
installtest:
	@echo Running tests in $(BUILD_ROOT)/test/all.lua
	@(TERM="dumb"; echo "dofile \"$(BUILD_ROOT)/test/all.lua\"" | $(INSTALL_ROSIEBIN) -D)
	@if [ -n "$(CLIENTS)" ]; then \
		echo "** Running librosie client tests **"; \
		cd $(LIBROSIE_DIR) && $(MAKE) test; \
	else \
		echo "Skipping librosie client tests."; \
		echo "To enable, set CLIENTS=all or CLIENTS=\"C python\" or such (space separated list in quotes)."; \
	fi


