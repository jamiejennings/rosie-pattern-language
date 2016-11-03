## ----------------------------------------------------------------------------- ##
## Customizable options:

## The place to put a link to rosie binary when using 'make install'
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

# LUA_ARCHIVE = 'http://www.lua.org/ftp/lua-5.3.2.tar.gz'
# LPEG_ARCHIVE = 'http://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.0.0.tar.gz'
# JSON_ARCHIVE = 'https://www.kyne.com.au/~mark/software/download/lua-cjson-2.1.0.tar.gz'

LUA = lua
LPEG = rosie-lpeg
JSON = lua-cjson

## ----------------------------------------------------------------------------- ##

HOME = "`pwd`"
TMP = submodules

default: $(PLATFORM)

LUA_DIR = $(TMP)/$(LUA)
LPEG_DIR = $(TMP)/$(LPEG)
JSON_DIR = $(TMP)/$(JSON)

# download: $(LUA_DIR)/src $(LPEG_DIR)/src $(JSON_DIR)/src

# $(LUA_DIR)/src: 
# 	cd $(LUA_DIR) && git submodule init && git submodule update
# 	cd $(LUA_DIR) && sed -e 's/CC=cc/CC=$$(CC)/' Makefile > Makefile2
# 	echo 'macosx: CC=cc' >$(LUA_DIR)/src/extra
# 	cd $(LUA_DIR)/src && cat Makefile2 extra > Makefile
# 	cd $(LUA_DIR) && ln -sf src include	    # Needed for lpeg to compile

# $(LPEG_DIR): $(LPEG_DIR).tar.gz
# 	cd $(TMP) && tar -xf $(LPEG).tar.gz  || (echo "File obtained from $(LPEG_ARCHIVE) was corrupted"; exit 1)
# 	echo '#!/bin/bash' > $(LPEG_DIR)/makedebug
# 	echo 'make clean' >> $(LPEG_DIR)/makedebug
# 	echo 'make LUADIR=../lua-5.3.2/src COPT="-DLPEG_DEBUG -g" macosx' >> $(LPEG_DIR)/makedebug
# 	chmod a+x $(LPEG_DIR)/makedebug

# $(JSON_DIR): $(JSON_DIR).tar.gz
# 	cd $(TMP) && tar -xzf $(JSON).tar.gz || (echo "File obtained from $(JSON_ARCHIVE) was corrupted"; exit 1)

# $(LUA_DIR).tar.gz:
# 	mkdir -p $(TMP)
# 	curl -o $(LUA_DIR).tar.gz $(LUA_ARCHIVE)

# $(LPEG_DIR).tar.gz:
# 	mkdir -p $(TMP)
# 	curl -o $(LPEG_DIR).tar.gz $(LPEG_ARCHIVE)

# $(JSON_DIR).tar.gz:
# 	mkdir -p $(TMP)
# 	curl -o $(JSON_DIR).tar.gz $(JSON_ARCHIVE)

.PHONY: clean none sniff test

clean:
	rm -rf bin/* lib/*
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR)/src && make clean
	-cd $(JSON_DIR) && make clean
#	-cd $(LUA_DIR) && ln -sf src include	    # Needed for lpeg to compile
#       @echo "Use 'make superclean' to remove local copies of prerequisites"

# superclean: clean
# 	rm -rf $(TMP)

none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

CJSON_MAKE_ARGS = LUA_VERSION=5.3 PREFIX=../lua-5.3.2 
CJSON_MAKE_ARGS += FPCONV_OBJS="g_fmt.o dtoa.o" CJSON_CFLAGS+=-fpic
CJSON_MAKE_ARGS += USE_INTERNAL_FPCONV=true CJSON_CFLAGS+=-DUSE_INTERNAL_FPCONV
CJSON_MAKE_ARGS += CJSON_CFLAGS+="-pthread -DMULTIPLE_THREADS"
CJSON_MAKE_ARGS += CJSON_LDFLAGS+=-pthread


macosx: PLATFORM=macosx
# Change the next line to CC=gcc if you prefer to use gcc on MacOSX
macosx: CC=cc
macosx: CJSON_MAKE_ARGS += CJSON_LDFLAGS="-bundle -undefined dynamic_lookup"
macosx: bin/lua lib/lpeg.so lib/cjson.so compile ln sniff

linux: PLATFORM=linux
linux: CC=gcc
linux: CJSON_MAKE_ARGS+=CJSON_CFLAGS+=-std=gnu99
linux: CJSON_MAKE_ARGS+=CJSON_LDFLAGS=-shared
linux: bin/lua lib/lpeg.so lib/cjson.so compile ln sniff

windows:
	@echo Windows installation not yet supported.

bin/lua: $(LUA_DIR)
	cd $(LUA_DIR) && $(MAKE) CC=$(CC) $(PLATFORM)
	mkdir -p bin
	cp $(LUA_DIR)/src/lua bin
	cp $(LUA_DIR)/src/luac bin

lib/lpeg.so: $(LPEG_DIR)
	cd $(LPEG_DIR)/src && $(MAKE) $(PLATFORM) CC=$(CC) LUADIR=../../lua/src
	mkdir -p lib
	cp $(LPEG_DIR)/src/lpeg.so lib

lib/cjson.so: $(JSON_DIR)
	cd $(JSON_DIR) && $(MAKE) CC=$(CC) $(CJSON_MAKE_ARGS)
	mkdir -p lib
	cp $(JSON_DIR)/cjson.so lib

bin/%.luac: src/core/%.lua
	bin/luac -o $@ $<

luaobjects := $(patsubst src/core/%.lua,bin/%.luac,$(wildcard src/core/*.lua))

compile: $(luaobjects)

ln:
	@/usr/bin/env echo -n "Linking $(HOME)/run to ./rosie... "
	@-ln -sf "$(HOME)/run" "./rosie" && chmod 755 "./rosie" && ([ $$? -eq 0 ] && echo "done.") || echo "failed!" 

install:
	@/usr/bin/env echo -n "Linking $(HOME)/run to $(DESTDIR)/rosie... "
	@-ln -sf "$(HOME)/run" "$(DESTDIR)/rosie" && chmod 755 "$(DESTDIR)/rosie" && ([ $$? -eq 0 ] && echo "done.") || echo "failed!" 

sniff:
	@echo "Rosie home is $(HOME)"
	@echo "Attempting to execute $(HOME)/run ..."
	@RESULT="$(shell $(HOME)/run 2>&1 >/dev/null)"; \
	EXPECTED="This is Rosie v$(shell head -1 VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
            echo ""; \
            echo "Rosie Pattern Engine installed successfully!"; \
	    echo ""; \
            echo "Use 'make install' to install binary in $(DESTDIR)"; \
            echo "Try this and look for color text output: ./rosie basic.matchall /etc/resolv.conf"; \
            true; \
        else \
            echo "Rosie Pattern Engine test FAILED."; \
	    false; \
        fi

test:
	@echo Running tests in test/all.lua
	echo "dofile 'test/all.lua'" | ./rosie -D

