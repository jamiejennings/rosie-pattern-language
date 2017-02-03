## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie.so, on which Rosie's foreign function interface is based. 
##
## © Copyright IBM Corporation 2016, 2017.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## Use "DEBUG=1" on the command line to enable verbose debugging output

HOME = $(shell cd ../..; pwd)
ROSIE = "$(HOME)/bin/rosie"

ifdef DEBUG
COPT = "-DDEBUG"
endif

REPORTED_PLATFORM=$(shell (uname -o || uname -s) 2> /dev/null)
ifeq ($(REPORTED_PLATFORM), Darwin)
PLATFORM=macosx
else ifeq ($(REPORTED_PLATFORM), GNU/Linux)
PLATFORM=linux
else
PLATFORM=none
endif

PLATFORMS = linux macosx windows

default: $(PLATFORM)

ifeq ($(PLATFORM), macosx)
CC= clang
else
CC= gcc
endif

CFLAGS= -O2 -Wall -Wextra -DLUA_COMPAT_5_2 $(SYSCFLAGS) $(MYCFLAGS) $(COPT)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

AR= ar rcu
RANLIB= ranlib
RM= rm -f

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS=  -I$(HOME)/submodules/lua/include
MYLDFLAGS= 
MYLIBS= 
MYOBJS=

LUA_A=$(HOME)/submodules/lua/src/liblua.a
LPEG_DIR=$(HOME)/submodules/rosie-lpeg/src
LPEG_SO=$(LPEG_DIR)/lpeg.so
CJSON_DIR=$(HOME)/submodules/lua-cjson
CJSON_SO=$(CJSON_DIR)/cjson.so

$(LUA_A) $(LPEG_SO) $(CJSON_SO):
	@echo "Missing Rosie object files.  Need to build rosie first."
	@false


.PHONY: lua_objs, lpeg_objs, cjson_objs
lua_objs: $(LUA_A)
	mkdir -p liblua
	cd liblua && ar x $(LUA_A)

lpeg_objs: $(LPEG_SO)
	mkdir -p liblpeg
	cd liblpeg && cp $(LPEG_DIR)/*.o .

cjson_objs: $(CJSON_SO)
	mkdir -p libcjson
	cd libcjson && cp $(CJSON_DIR)/*.o .

ALL= librosie.so librosie.a

librosie.o: librosie_gen.c librosie_gen.h librosie.c librosie.h
	$(CC) -o $@ -c librosie.c $(CFLAGS)

librosie.so: librosie.o lua_objs lpeg_objs cjson_objs
	$(CC) -shared -o $@ librosie.o liblua/*.o liblpeg/*.o libcjson/*.o

librosie.a: librosie.o lua_objs lpeg_objs cjson_objs
	$(AR) $@ librosie.o liblua/*.o liblpeg/*.o libcjson/*.o
	$(RANLIB) $@

clean:
	$(RM) librosie.so librosie.o librosie.a rtest.o rtest librosie_gen.c librosie_gen.h liblua/* liblpeg/* libcjson/*

depend:
	@$(CC) $(CFLAGS) -MM *.c

echo:
	@echo "HOME= $(HOME)"
	@echo "PLAT= $(PLAT)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(LDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"

none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

linux:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX -D_GNU_SOURCE=1" SYSLIBS="-Wl,-E -ldl -lreadline"

macosx:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLIBS= CC=$(CC)

macosx: CFLAGS += -std=gnu99

windows:
	@echo Windows installation not yet supported.

gen_C:
librosie_gen.c:
librosie_gen.h:
	@echo Generating librosie C functions and headers
	echo 'api = require "api"; api.write_C_FILES();' | $(ROSIE) -D >/dev/null

## Targets that do not create files
.PHONY: default o a clean echo none

librosie.o: librosie_gen.c librosie_gen.h librosie.c librosie.h 
