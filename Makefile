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
#ROSIE_DOC = $(DESTDIR)/share/doc
#ROSIE_ROOT = $(DESTDIR)/share/rosie

.PHONY: default
default: $(PLATFORM) save_build_info

SUBMOD = submodules
ROSIEBIN = $(BUILD_ROOT)/bin/rosie
INSTALL_ROSIEBIN = $(DESTDIR)/bin/rosie

BUILD_LUA_PACKAGE = $(BUILD_ROOT)/rosie.lua

LUA_DIR = $(SUBMOD)/$(LUA)
LPEG_DIR = $(SUBMOD)/$(LPEG)
JSON_DIR = $(SUBMOD)/$(JSON)
READLINE_DIR = $(SUBMOD)/$(READLINE)
LUAMOD_DIR = $(SUBMOD)/$(LUAMOD)

INSTALL_BIN_DIR = $(ROSIED)/bin
INSTALL_LIB_DIR = $(ROSIED)/lib
INSTALL_LUA_PACKAGE = $(ROSIED)/rosie.lua

.PHONY: clean
clean:
	rm -rf bin/* lib/* rosie.lua
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR)/src && make clean
	-cd $(JSON_DIR) && make clean
	-cd $(READLINE_DIR) && rm -f readline.so && rm -f src/lua_readline.o
	rm -f $(submodule_sentinel)

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
	   echo "READLINE TEST: libreadline and readline.h appear to be installed" || \
	   (echo "READLINE TEST: Missing readline library or readline.h" && \
	    echo "READLINE TEST: See https://github.com/jamiejennings/rosie-pattern-language#how-to-build-clone-the-repo-and-type-make" && \
	    /usr/bin/false)

.PHONY: macosx
macosx: PLATFORM=macosx
macosx: CC=cc
macosx: CJSON_MAKE_ARGS += CJSON_LDFLAGS="-bundle -undefined dynamic_lookup"
macosx: bin/lua lib/lpeg.so lib/cjson.so lib/readline.so compile sniff

.PHONY: linux
linux: PLATFORM=linux
linux: CC=gcc
linux: CJSON_MAKE_ARGS+=CJSON_CFLAGS+=-std=gnu99
linux: CJSON_MAKE_ARGS+=CJSON_LDFLAGS=-shared
linux: LINUX_CFLAGS=MYCFLAGS=-fPIC
linux: readlinetest bin/lua lib/lpeg.so lib/cjson.so lib/readline.so compile sniff

.PHONY: windows
windows:
	@echo Windows installation not yet supported.

# submodule_sentinel indicates that submodules have been initialized.
# the sentile file is a file copied from a submodule repo, so that:
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

bin/lua: $(LUA_DIR)/src/lua
	mkdir -p bin
	cp $(LUA_DIR)/src/lua bin

$(LUA_DIR)/src/lua: $(submodules)
	cd $(LUA_DIR) && $(MAKE) CC=$(CC) $(PLATFORM) $(LINUX_CFLAGS) $(LINUX_LDFLAGS)

bin/luac: bin/lua
	cp $(LUA_DIR)/src/luac bin

lpeg_lib=$(LPEG_DIR)/src/lpeg.so
lib/lpeg.so: $(lpeg_lib)
	mkdir -p lib
	cp $(lpeg_lib) lib

$(lpeg_lib): $(submodules)
	cd $(LPEG_DIR)/src && $(MAKE) $(PLATFORM) CC=$(CC) LUADIR=../../$(LUA)

json_lib = $(JSON_DIR)/cjson.so
lib/cjson.so: $(json_lib)
	mkdir -p lib
	cp $(json_lib) lib

$(json_lib): $(submodules)
	cd $(JSON_DIR) && $(MAKE) CC=$(CC) $(CJSON_MAKE_ARGS)

lib/argparse.luac: submodules/argparse/src/argparse.lua
	bin/luac -o $@ $<

readline_lib = $(READLINE_DIR)/readline.so
lib/readline.so: $(readline_lib)
	mkdir -p lib
	cp $(readline_lib) lib

$(READLINE_DIR)/readline.so:
	cd $(READLINE_DIR) && $(MAKE) CC=$(CC) LUA_INCLUDE_DIR=../$(LUA)/include

$(EXECROSIE): compile
	@/usr/bin/env echo "Creating $(EXECROSIE)"
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(EXECROSIE)"
	@/usr/bin/env echo -n "$(HOME)/lib/run-rosie $(HOME)" >> "$(EXECROSIE)"
	@/usr/bin/env echo ' "$$@"' >> "$(EXECROSIE)"
	@chmod 755 "$(EXECROSIE)"

lib/list.luac: $(LUAMOD_DIR)/list.lua bin/luac
	bin/luac -o $@ $<

lib/recordtype.luac: $(LUAMOD_DIR)/recordtype.lua bin/luac
	bin/luac -o $@ $<

lib/submodule.luac: $(LUAMOD_DIR)/submodule.lua bin/luac
	bin/luac -o $@ $<

lib/%.luac: src/core/%.lua bin/luac
	bin/luac -o $@ $<

lib/run-rosie:
	mkdir -p lib
	@cp src/run-rosie lib

core_objects := $(patsubst src/core/%.lua,lib/%.luac,$(wildcard src/core/*.lua))
other_objects := lib/argparse.luac lib/list.luac lib/recordtype.luac lib/submodule.luac
luaobjects := $(core_objects) $(other_objects)

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
	@chmod 755 "$(ROSIEBIN)"
	@/usr/bin/env echo "Creating $(BUILD_LUA_PACKAGE)"
	@/usr/bin/env echo "local ROSIE_HOME =  \"$(BUILD_ROOT)\"" > "$(BUILD_LUA_PACKAGE)"
	@cat "$(BUILD_ROOT)/src/rosie-package-template.lua" >> "$(BUILD_LUA_PACKAGE)"

# See comment above re: ROSIEBIN
.PHONY: $(INSTALL_ROSIEBIN)
$(INSTALL_ROSIEBIN): $(ROSIEBIN)
	@/usr/bin/env echo "Creating $(INSTALL_ROSIEBIN)"
	mkdir -p `dirname "$(INSTALL_ROSIEBIN)"` "$(ROSIED)"/bin
	cp "$(BUILD_ROOT)"/bin/rosie "$(INSTALL_ROSIEBIN)"
	@chmod 755 "$(INSTALL_ROSIEBIN)"

# Install the lua interpreter
.PHONY: install_lua
install_lua: bin/lua
	mkdir -p "$(INSTALL_BIN_DIR)"
	cp bin/lua "$(INSTALL_BIN_DIR)"

# Install all of the shared objects
.PHONY: install_so
install_so: lib/lpeg.so lib/cjson.so
	mkdir -p "$(INSTALL_LIB_DIR)"
	cp lib/lpeg.so lib/cjson.so "$(INSTALL_LIB_DIR)"

# Install any metadata needed by rosie
.PHONY: install_metadata
install_metadata:
	mkdir -p "$(ROSIED)"
	cp CHANGELOG CONTRIBUTORS LICENSE README THANKS VERSION "$(ROSIED)"

# Install the real run script, and the rosie.lua file
.PHONY: install_run_script
install_run_script:
	mkdir -p "$(INSTALL_LIB_DIR)"
	@cp src/run-rosie "$(INSTALL_LIB_DIR)"
	@cp rosie.lua "$(ROSIED)"/

# Install the lua pre-compiled binary files (.luac)
.PHONY: install_luac_bin
install_luac_bin:
	mkdir -p "$(INSTALL_LIB_DIR)"
	cp lib/*.luac "$(INSTALL_LIB_DIR)"

# Install the provided RPL patterns
.PHONY: install_rpl
install_rpl:
	mkdir -p "$(ROSIED)"/rpl
	cp -r rpl "$(ROSIED)"/

# Main install rule
.PHONY: install
install: $(INSTALL_ROSIEBIN) install_lua install_so install_metadata \
	install_run_script install_luac_bin install_rpl
#	@echo 
#	@echo TO TEST THE INSTALLATION: make installtest
#	@echo TO UNINSTALL: remove one directory and several files/links, e.g.
#	@echo     rm -rf $(ROSIED)
#	@echo     rm $(INSTALL_ROSIEBIN) $(ROSIE_ROOT)/rpl $(ROSIE_ROOT)/pkg $(ROSIE_DOC)/rosie
#	@echo 

.PHONY: uninstall
uninstall:
	@echo "Removing $(INSTALL_ROSIEBIN)"
	@-rm -vf $(INSTALL_ROSIEBIN)
	@echo "Removing $(ROSIED)"
	@-rm -Rvf $(ROSIED)/

.PHONY: save_build_info
save_build_info: $(ROSIEBIN)
	@$(BUILD_ROOT)/src/build_info.sh $(BUILD_ROOT) $(CC) > $(BUILD_ROOT)/build.log

.PHONY: sniff
sniff: $(ROSIEBIN)
	@RESULT="$(shell $(ROSIEBIN) --version 2> /dev/null)"; \
	EXPECTED="$(shell head -1 $(BUILD_ROOT)/VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
	    echo "";\
            echo "Rosie Pattern Engine built successfully!"; \
	    if [ -z "$$BREW" ]; then \
	      	    echo "    Use 'make install' to install into $(DESTDIR)"; \
	      	    echo "    Use 'make test' to run the test suite here in the build directory"; \
	      	    echo "    To run rosie from the build directory, use ./bin/rosie"; \
	            echo "    Try this example, and look for color text output: rosie basic.matchall /etc/resolv.conf"; \
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

.PHONY: test
test:
	@echo Running tests in test/all.lua
	echo "dofile \"$(BUILD_ROOT)/test/all.lua\"" | $(ROSIEBIN) -D

.PHONY: installtest
installtest:
	@echo Creating links in $(ROSIED) to testing code in $(BUILD_ROOT)
	-ln -s $(BUILD_ROOT)/src/test-functions.lua $(ROSIED)/src
	-ln -s $(BUILD_ROOT)/test $(ROSIED)
	@echo Running tests in test/all.lua
	echo "ROSIE_HOME=\"$(ROSIED)\"; dofile \"$(ROSIED)/test/all.lua\"" | $(INSTALL_ROSIEBIN) -D
	@echo Removing links in $(ROSIED) to testing code in $(BUILD_ROOT)
	-rm $(ROSIED)/src/test-functions.lua
	-rm $(ROSIED)/test

