## ----------------------------------------------------------------------------- ##
## Customizable options:

# The place to put a link to rosie executable when using 'make install'
DESTDIR=/usr/local/bin

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

HOME = $(shell pwd)
TMP = submodules
ROSIEBIN = bin/rosie
EXECROSIE = "$(HOME)/$(ROSIEBIN)"

default: $(PLATFORM)

ARGP_DIR = $(TMP)/$(ARGPARSE)
LUA_DIR = $(TMP)/$(LUA)
LPEG_DIR = $(TMP)/$(LPEG)
JSON_DIR = $(TMP)/$(JSON)

## ----------------------------------------------------------------------------- ##

.PHONY: clean none sniff test

clean:
	rm -rf bin/* lib/*
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR)/src && make clean
	-cd $(JSON_DIR) && make clean

none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

## ----------------------------------------------------------------------------- ##

CJSON_MAKE_ARGS = LUA_VERSION=5.3 PREFIX=../lua 
CJSON_MAKE_ARGS += FPCONV_OBJS="g_fmt.o dtoa.o" CJSON_CFLAGS+=-fpic
CJSON_MAKE_ARGS += USE_INTERNAL_FPCONV=true CJSON_CFLAGS+=-DUSE_INTERNAL_FPCONV
CJSON_MAKE_ARGS += CJSON_CFLAGS+="-pthread -DMULTIPLE_THREADS"
CJSON_MAKE_ARGS += CJSON_LDFLAGS+=-pthread


macosx: PLATFORM=macosx
# Change the next line to CC=gcc if you prefer to use gcc on MacOSX
macosx: CC=cc
macosx: CJSON_MAKE_ARGS += CJSON_LDFLAGS="-bundle -undefined dynamic_lookup"
macosx: bin/lua lib/lpeg.so lib/cjson.so compile sniff

linux: PLATFORM=linux
linux: CC=gcc
linux: CJSON_MAKE_ARGS+=CJSON_CFLAGS+=-std=gnu99
linux: CJSON_MAKE_ARGS+=CJSON_LDFLAGS=-shared
linux: LINUX_CFLAGS=MYCFLAGS=-fPIC
linux: LINUX_LDFLAGS=MYLDFLAGS=-Wl,--export-dynamic
linux: bin/lua lib/lpeg.so lib/cjson.so compile sniff

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

bin/argparse.luac: submodules/argparse/src/argparse.lua
	bin/luac -o $@ $<

bin/%.luac: src/core/%.lua bin/luac
	bin/luac -o $@ $<

luaobjects := $(patsubst src/core/%.lua,bin/%.luac,$(wildcard src/core/*.lua)) bin/argparse.luac

compile: $(luaobjects)

$(EXECROSIE):
	@/usr/bin/env echo "Creating $(EXECROSIE)"
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(EXECROSIE)"
	@/usr/bin/env echo -n "$(HOME)/src/run-rosie $(HOME)" >> "$(EXECROSIE)"
	@/usr/bin/env echo ' "$$@"' >> "$(EXECROSIE)"
	@chmod 755 "$(EXECROSIE)"

install:
	@/usr/bin/env echo "Creating symbolic link $(DESTDIR)/rosie pointing to $(EXECROSIE)"
	@-ln -sf "$(EXECROSIE)" "$(DESTDIR)/rosie" && chmod 755 "$(DESTDIR)/rosie"

sniff: $(EXECROSIE)
	@RESULT="$(shell $(EXECROSIE) 2>&1 >/dev/null)"; \
	EXPECTED="This is Rosie v$(shell head -1 $(HOME)/VERSION)"; \
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
	    echo "    Rosie executable is $(EXECROSIE)"; \
	    echo "    Expected this output: $$EXPECTED"; \
	    if [ -n "$$RESULT" ]; then \
		echo "    But received this output: $$RESULT"; \
	    else \
		echo "    But received no output."; \
	    fi; \
	    false; \
        fi

test:
	@echo Running tests in test/all.lua
	echo "rosie=\"$(EXECROSIE)\"; dofile \"$(HOME)/test/all.lua\"" | $(EXECROSIE) -D

