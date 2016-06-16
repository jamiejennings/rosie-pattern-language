## ----------------------------------------------------------------------------- ##

LUA_DIR = lua-5.3.2
LPEG_DIR = lpeg-1.0.0
JSON_DIR = lua-cjson-2.1.0

## ----------------------------------------------------------------------------- ##

PLATFORM = none
PLATFORMS = linux macosx

LUA_ARCHIVE = 'http://www.lua.org/ftp/lua-5.3.2.tar.gz'
LPEG_ARCHIVE = 'http://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.0.0.tar.gz'
JSON_ARCHIVE = 'http://www.kyne.com.au/~mark/software/download/lua-cjson-2.1.0.tar.gz'

## ----------------------------------------------------------------------------- ##

HOME = "`pwd`"

default: $(PLATFORM)

download: $(LUA_DIR) $(LPEG_DIR) $(JSON_DIR)

$(LUA_DIR): $(LUA_DIR).tar.gz
	tar -xf $(LUA_DIR).tar.gz
	cd $(LUA_DIR)/src && sed -e 's/CC=cc/CC=$$(CC)/' Makefile > Makefile2
	echo 'macosx: CC=cc' >$(LUA_DIR)/src/extra
	cd $(LUA_DIR)/src && cat Makefile2 extra > Makefile
	cd $(LUA_DIR) && ln -sf src include	    # Needed for lpeg to compile

$(LPEG_DIR): $(LPEG_DIR).tar.gz
	tar -xf $(LPEG_DIR).tar.gz

$(JSON_DIR): $(JSON_DIR).tar.gz
	tar -xf $(JSON_DIR).tar.gz

$(LUA_DIR).tar.gz:
	curl -o $(LUA_DIR).tar.gz $(LUA_ARCHIVE)

$(LPEG_DIR).tar.gz:
	curl -o $(LPEG_DIR).tar.gz $(LPEG_ARCHIVE)

$(JSON_DIR).tar.gz:
	curl -o $(JSON_DIR).tar.gz $(JSON_ARCHIVE)

.PHONY: clean superclean none test

clean:
	rm -f bin/* lib/*
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR) && make clean
	-cd $(JSON_DIR) && make clean
	-cd $(LUA_DIR) && ln -sf src include	    # Needed for lpeg to compile
	@echo "Use 'make superclean' to remove local copies of prerequisites"

superclean: clean
	rm -rf $(LUA_DIR) $(LPEG_DIR) $(JSON_DIR)
	rm -rf $(LUA_DIR).tar.gz $(LPEG_DIR).tar.gz $(JSON_DIR).tar.gz

none:
	@echo "Please do 'make PLATFORM' where PLATFORM is one of these: $(PLATFORMS)"
	@echo "Or 'make download' to download the pre-requisites"


CJSON_MAKE_ARGS = LUA_VERSION=5.3 PREFIX=../lua-5.3.2 
CJSON_MAKE_ARGS += FPCONV_OBJS="g_fmt.o dtoa.o" CJSON_CFLAGS+=-fpic
CJSON_MAKE_ARGS += USE_INTERNAL_FPCONV=true CJSON_CFLAGS+=-DUSE_INTERNAL_FPCONV 

macosx: PLATFORM=macosx
# Change the next line to CC=gcc if you prefer to use gcc on MacOSX
macosx: CC=cc
macosx: CJSON_MAKE_ARGS += CJSON_LDFLAGS="-bundle -undefined dynamic_lookup"
macosx: bin/lua lib/lpeg.so lib/cjson.so compile test

linux: PLATFORM=linux
linux: CC=gcc
linux: CJSON_MAKE_ARGS+=CJSON_CFLAGS+=-std=gnu99
linux: CJSON_MAKE_ARGS+=CJSON_LDFLAGS=-shared
linux: bin/lua lib/lpeg.so lib/cjson.so compile test

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

test:
	@echo "Rosie home is $(HOME)"
	@echo "Attempting to execute $(HOME)/run ..."
	@RESULT="$(shell $(HOME)/run 2>&1 >/dev/null)"; \
	EXPECTED="This is Rosie v$(shell head -1 VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
            echo "Rosie Pattern Engine installed successfully!"; \
            echo "Try this as a test: ./run basic.matchall /etc/resolv.conf"; \
        else \
            echo "Rosie Pattern Engine test FAILED."; \
        fi


