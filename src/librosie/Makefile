## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie.so, on which Rosie's foreign function interface is based. 
##
## © Copyright IBM Corporation 2016, 2017.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## Use "DEBUG=1" on the command line to enable logging to stderr

HOME = $(shell cd ../..; pwd)
ROSIE = "$(HOME)/bin/rosie"

ifdef DEBUG
COPT=-DDEBUG
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

# ifeq ($(PLATFORM), macosx)
# CC= clang
# else
CC= gcc
# endif

CFLAGS= -pthread -O2 -Wall -Wextra -pthread -DMULTIPLE_THREADS -DLUA_COMPAT_5_2 $(COPT) $(SYSCFLAGS) $(MYCFLAGS) 
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= -lpthread $(SYSLIBS) $(MYLIBS)

AR= ar rcu
RANLIB= ranlib
RM= rm -f

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS=  -I$(HOME)/submodules/lua/include -I$(HOME)/submodules/rosie-lpeg/src 
MYLDFLAGS= 
MYLIBS= 
MYOBJS=

LUA_A=$(HOME)/submodules/lua/src/liblua.a
LUA_DYLIB_NAME=lua.5.3
LUA_DYLIB=lib$(LUA_DYLIB_NAME).dylib

$(LUA_DYLIB): $(lua_objs)
	gcc -dynamiclib -install_name $@ -compatibility_version 5.3 -current_version 5.3.2 -o $@ liblua/*.o

$(LUA_A):
	@echo "Missing Rosie object files.  Need to build rosie first."
	@false


.PHONY: lua_objs
lua_objs: $(LUA_A)
	mkdir -p liblua
	cd liblua && ar x $(LUA_A)

ALL= librosie.so librosie.a
ALLCLIENTS= python c

ifeq ($(CLIENTS),all)
  clients=$(ALLCLIENTS)
else
  clients=$(CLIENTS)
endif

librosie.o: librosie.c librosie.h
	$(CC) -o $@ -c librosie.c $(CFLAGS)

librosie.so: librosie.o $(LUA_DYLIB)
#	$(CC) -o $@ librosie.o liblua/*.o $(SYSLIBS) $(LDFLAGS)
	$(CC) -o $@ librosie.o $(SYSLIBS) $(LDFLAGS) -L. -l$(LUA_DYLIB_NAME)

librosie.a: librosie.o lua_objs
	$(AR) $@ librosie.o liblua/*.o
	$(RANLIB) $@

clean:
	$(RM) librosie.so librosie.o librosie.a liblua/*

depend:
	@$(CC) $(CFLAGS) -MM *.c

test:
	here="$(shell pwd)"; \
	for client in $(clients); do cd $${here}/$$client && $(MAKE) test; done

installtest:
	here="$(shell pwd)"; \
	for client in $(clients); do cd $${here}/$$client && $(MAKE) installtest; done

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
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX -std=gnu99 -D_GNU_SOURCE=1 -fPIC" SYSLIBS="-shared -ldl -lm -Wl,--export-dynamic -Wl,--no-undefined -Wl,-E"

macosx:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLDFLAGS="-bundle -undefined dynamic_lookup" CC=$(CC)

macosx: CFLAGS += -std=gnu99

windows:
	@echo Windows installation not yet supported.

## Targets that do not create files
.PHONY: default o a clean echo none

