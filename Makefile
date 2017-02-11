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

LUA = lua
LPEG = rosie-lpeg
JSON = lua-cjson

HOME = $(shell pwd)
TMP = submodules
ROSIEBIN = bin/rosie
EXECROSIE = "$(HOME)/$(ROSIEBIN)"

default: $(PLATFORM)

LUA_DIR = $(TMP)/$(LUA)
LPEG_DIR = $(TMP)/$(LPEG)
JSON_DIR = $(TMP)/$(JSON)

## ----------------------------------------------------------------------------- ##

.PHONY: clean none sniff test default macosx linux windows none compile

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


# submodule_sentinel indicates that submodules have been initialized.
# the sentile file is a file copied from a submodule repo, so that:
# (1) the submodule must have been checked out, and
# (2) the sentinel will not be newer than the submodule files
submodule_sentinel=submodules/~~present~~ 
submodules = submodules/lua/src/Makefile submodules/lua-cjson/Makefile submodules/rosie-lpeg/src/makefile
$(submodules): $(submodule_sentinel)

# submodules:
# 	@echo Missing submodules directory.  Re-initializing.
# 	git submodule init
# 	git submodule update --checkout

$(submodule_sentinel): #submodules
	git submodule init
	git submodule update --checkout
	cd $(LUA_DIR) && ln -sf src include
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
	cd $(LPEG_DIR)/src && $(MAKE) $(PLATFORM) CC=$(CC) LUADIR=../../lua

json_lib = $(JSON_DIR)/cjson.so
lib/cjson.so: $(json_lib)
	mkdir -p lib
	cp $(json_lib) lib

$(json_lib): $(submodules)
	cd $(JSON_DIR) && $(MAKE) CC=$(CC) $(CJSON_MAKE_ARGS)

bin/%.luac: src/core/%.lua bin/luac
	bin/luac -o $@ $<

luaobjects := $(patsubst src/core/%.lua,bin/%.luac,$(wildcard src/core/*.lua))

compile: $(luaobjects) bin/luac bin/lua lib/lpeg.so lib/cjson.so

$(EXECROSIE): compile
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

