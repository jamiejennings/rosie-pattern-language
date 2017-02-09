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

LUA = lua
LPEG = rosie-lpeg
JSON = lua-cjson

BUILD_ROOT = $(shell pwd)

# ROSIED is root of where all of the important files will be installed
ROSIED = $(DESTDIR)/share/rosie

SUBMOD = submodules
ROSIEBIN = $(BUILD_ROOT)/bin/rosie
INSTALL_ROSIEBIN = $(DESTDIR)/bin/rosie

.PHONY: default
default: $(PLATFORM)

LUA_DIR = $(SUBMOD)/$(LUA)
LPEG_DIR = $(SUBMOD)/$(LPEG)
JSON_DIR = $(SUBMOD)/$(JSON)
INSTALL_BIN_DIR = $(ROSIED)/bin
INSTALL_LIB_DIR = $(ROSIED)/lib

## ----------------------------------------------------------------------------- ##

.PHONY: clean
clean:
	rm -rf bin/* lib/*
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR)/src && make clean
	-cd $(JSON_DIR) && make clean

.PHONY: none
none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

## ----------------------------------------------------------------------------- ##

CJSON_MAKE_ARGS = LUA_VERSION=5.3 PREFIX=../lua 
CJSON_MAKE_ARGS += FPCONV_OBJS="g_fmt.o dtoa.o" CJSON_CFLAGS+=-fpic
CJSON_MAKE_ARGS += USE_INTERNAL_FPCONV=true CJSON_CFLAGS+=-DUSE_INTERNAL_FPCONV
CJSON_MAKE_ARGS += CJSON_CFLAGS+="-pthread -DMULTIPLE_THREADS"
CJSON_MAKE_ARGS += CJSON_LDFLAGS+=-pthread


.PHONY: macosx
macosx: PLATFORM=macosx
# Change the next line to CC=gcc if you prefer to use gcc on MacOSX
macosx: CC=cc
macosx: CJSON_MAKE_ARGS += CJSON_LDFLAGS="-bundle -undefined dynamic_lookup"
macosx: bin/lua lib/lpeg.so lib/cjson.so compile sniff

.PHONY: linux
linux: PLATFORM=linux
linux: CC=gcc
linux: CJSON_MAKE_ARGS+=CJSON_CFLAGS+=-std=gnu99
linux: CJSON_MAKE_ARGS+=CJSON_LDFLAGS=-shared
linux: LINUX_CFLAGS=MYCFLAGS=-fPIC
linux: LINUX_LDFLAGS=MYLDFLAGS=-Wl,--export-dynamic
linux: bin/lua lib/lpeg.so lib/cjson.so compile sniff

.PHONY: windows
windows:
	@echo Windows installation not yet supported.

submodules = submodules/lua/Makefile submodules/lua-cjson/Makefile submodules/rosie-lpeg/src/makefile

$(submodules):
	git submodule init
	git submodule update

submodules/lua/include:
	cd $(LUA_DIR) && ln -sf src include

bin/luac bin/lua: $(submodules)
	cd $(LUA_DIR) && $(MAKE) CC=$(CC) $(PLATFORM) $(LINUX_CFLAGS) $(LINUX_LDFLAGS)
	mkdir -p bin
	cp $(LUA_DIR)/src/lua bin
	cp $(LUA_DIR)/src/luac bin

lib/lpeg.so: $(submodules) submodules/lua/include
	cd $(LPEG_DIR)/src && $(MAKE) $(PLATFORM) CC=$(CC) LUADIR=../../lua
	mkdir -p lib
	cp $(LPEG_DIR)/src/lpeg.so lib

lib/cjson.so: $(submodules) submodules/lua/include
	cd $(JSON_DIR) && $(MAKE) CC=$(CC) $(CJSON_MAKE_ARGS)
	mkdir -p lib
	cp $(JSON_DIR)/cjson.so lib

bin/%.luac: src/core/%.lua bin/luac
	bin/luac -o $@ $<

luaobjects := $(patsubst src/core/%.lua,bin/%.luac,$(wildcard src/core/*.lua))

.PHONY: compile
compile: $(luaobjects)

$(ROSIEBIN):
	@/usr/bin/env echo "Creating $(ROSIEBIN)"
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(ROSIEBIN)"
	@/usr/bin/env echo -n "$(BUILD_ROOT)/src/run-rosie $(BUILD_ROOT)" >> "$(ROSIEBIN)"
	@/usr/bin/env echo ' "$$@"' >> "$(ROSIEBIN)"
	chmod 755 "$(ROSIEBIN)"

$(INSTALL_ROSIEBIN):
	@/usr/bin/env echo "Creating $(INSTALL_ROSIEBIN)"
	mkdir -p `dirname "$(INSTALL_ROSIEBIN)"` "$(ROSIED)"/{bin,src}
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo -n "$(ROSIED)/src/run-rosie $(ROSIED)" >> "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo ' "$$@"' >> "$(INSTALL_ROSIEBIN)"
	cp "$(BUILD_ROOT)"/src/run-rosie "$(ROSIED)"/src
	chmod 755 "$(INSTALL_ROSIEBIN)"

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
	cp VERSION MANIFEST "$(ROSIED)"

# Install the needed lua source files
.PHONY: install_lua_src
install_lua_src:
	@# we only need this one .lua file in the installation
	mkdir -p "$(ROSIED)"/src
	@cp src/run.lua "$(ROSIED)"/src

# Install the lua pre-compiled binary files (.luac)
.PHONY: install_luac_bin
install_luac_bin:
	mkdir -p "$(ROSIED)"/bin
	cp bin/*.luac "$(ROSIED)"/bin

# Install the provided RPL patterns
.PHONY: install_rpl
install_rpl:
	mkdir -p "$(ROSIED)"/{src,rpl}
	cp rpl/*.rpl "$(ROSIED)"/rpl
	cp src/rpl-core.rpl "$(ROSIED)"/src

# Main install rule
.PHONY: install
install: $(INSTALL_ROSIEBIN) install_lua install_so install_metadata \
	 install_lua_src install_luac_bin install_rpl

.PHONY: sniff
sniff: $(ROSIEBIN)
	@RESULT="$(shell $(ROSIEBIN) 2>&1 >/dev/null)"; \
	EXPECTED="This is Rosie v$(shell head -1 $(BUILD_ROOT)/VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
	    echo "";\
            echo "Rosie Pattern Engine installed successfully!"; \
	    if [ -z "$$BREW" ]; then \
	      	    echo "    Use 'make install' to install binary in $(DESTDIR)"; \
	      	    echo "    Use 'make test' to run the test suite"; \
	      	    echo "    To run rosie from the installation directory, use ./bin/rosie"; \
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
	echo "rosie=\"$(ROSIEBIN)\"; dofile \"$(BUILD_ROOT)/test/all.lua\"" | $(ROSIEBIN) -D

