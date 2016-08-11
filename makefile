## ----------------------------------------------------------------------------- ##

# place to put a link to rosie binary during install:
DESTDIR=/usr/local/bin

## ----------------------------------------------------------------------------- ##

PLATFORM = none
PLATFORMS = linux macosx

LUA_ARCHIVE = 'http://www.lua.org/ftp/lua-5.3.2.tar.gz'
LPEG_ARCHIVE = 'http://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.0.0.tar.gz'
JSON_ARCHIVE = 'http://www.kyne.com.au/~mark/software/download/lua-cjson-2.1.0.tar.gz'

LUA = lua-5.3.2
LPEG = lpeg-1.0.0
JSON = lua-cjson-2.1.0

## ----------------------------------------------------------------------------- ##

HOME = "`pwd`"
TMP = tmp

default: $(PLATFORM)

LUA_DIR = $(TMP)/$(LUA)
LPEG_DIR = $(TMP)/$(LPEG)
JSON_DIR = $(TMP)/$(JSON)

download: $(LUA_DIR) $(LPEG_DIR) $(JSON_DIR)

$(LUA_DIR): $(LUA_DIR).tar.gz
	cd $(TMP) && tar -xf $(LUA).tar.gz
	cd $(LUA_DIR)/src && sed -e 's/CC=cc/CC=$$(CC)/' Makefile > Makefile2
	echo 'macosx: CC=cc' >$(LUA_DIR)/src/extra
	cd $(LUA_DIR)/src && cat Makefile2 extra > Makefile
	cd $(LUA_DIR) && ln -sf src include	    # Needed for lpeg to compile

$(LPEG_DIR): $(LPEG_DIR).tar.gz
	cd $(TMP) && tar -xf $(LPEG).tar.gz
	echo '#!/bin/bash' > $(LPEG_DIR)/makedebug
	echo 'make clean' >> $(LPEG_DIR)/makedebug
	echo 'make LUADIR=../lua-5.3.2/src COPT="-DLPEG_DEBUG -g" macosx' >> $(LPEG_DIR)/makedebug
	chmod a+x $(LPEG_DIR)/makedebug

$(JSON_DIR): $(JSON_DIR).tar.gz
	cd $(TMP) && tar -xf $(JSON).tar.gz

$(LUA_DIR).tar.gz:
	mkdir -p $(TMP)
	curl -o $(LUA_DIR).tar.gz $(LUA_ARCHIVE)

$(LPEG_DIR).tar.gz:
	mkdir -p $(TMP)
	curl -o $(LPEG_DIR).tar.gz $(LPEG_ARCHIVE)

$(JSON_DIR).tar.gz:
	mkdir -p $(TMP)
	curl -o $(JSON_DIR).tar.gz $(JSON_ARCHIVE)

.PHONY: clean superclean none sniff test

clean:
	rm -rf bin/* lib/*
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR) && make clean
	-cd $(JSON_DIR) && make clean
	-cd $(LUA_DIR) && ln -sf src include	    # Needed for lpeg to compile
	@echo "Use 'make superclean' to remove local copies of prerequisites"

superclean: clean
	rm -rf $(TMP)

none:
	@echo "Please do 'make PLATFORM' where PLATFORM is one of these: $(PLATFORMS)"
	@echo "Or 'make download' to download the pre-requisites"


CJSON_MAKE_ARGS = LUA_VERSION=5.3 PREFIX=../lua-5.3.2 
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
linux: bin/lua lib/lpeg.so lib/cjson.so compile sniff

bin/lua: $(LUA_DIR)
	cd $(LUA_DIR) && $(MAKE) CC=$(CC) $(PLATFORM)
	mkdir -p bin
	cp $(LUA_DIR)/src/lua bin
	cp $(LUA_DIR)/src/luac bin

lib/lpeg.so: $(LPEG_DIR)
	cd $(LPEG_DIR) && $(MAKE) CC=$(CC) LUADIR=../lua-5.3.2/src $(PLATFORM)
	mkdir -p lib
	cp $(LPEG_DIR)/lpeg.so lib

lib/cjson.so: $(JSON_DIR)
	cd $(JSON_DIR) && $(MAKE) CC=$(CC) $(CJSON_MAKE_ARGS)
	mkdir -p lib
	cp $(JSON_DIR)/cjson.so lib

compile:
	bin/lua -e "ROSIE_HOME=\"`pwd`\"" src/rosie-compile.lua

install:
	@/usr/bin/env echo -n "Linking $(HOME)/run to $(DESTDIR)/rosie... "
	@-ln -sf "$(HOME)/run" "$(DESTDIR)/rosie" && chmod 755 "$(DESTDIR)/rosie" && ([ $$? -eq 0 ] && echo "done.") || echo "failed!" 

sniff:
	@echo "Rosie home is $(HOME)"
	@echo "Attempting to execute $(HOME)/run ..."
	@RESULT="$(shell $(HOME)/run 2>&1 >/dev/null)"; \
	EXPECTED="This is Rosie v$(shell head -1 VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
            echo "\nRosie Pattern Engine installed successfully!"; \
	    echo ""; \
            echo "Use 'make install' to install binary in $(DESTDIR)"; \
            echo "And here is a command to try: ./run basic.matchall /etc/resolv.conf"; \
        else \
            echo "Rosie Pattern Engine test FAILED."; \
        fi

test:
	echo "dofile 'test/all.lua'" | rosie -D

