## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie.so, on which Rosie's foreign function interface is based. 
##
## © Copyright IBM Corporation 2016, 2017.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## Use "DEBUG=1" on the command line to enable logging to stderr

HOME = $(shell cd ../../..; pwd)
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

CFLAGS= -pthread -O2 -Wall -Wextra -DLUA_COMPAT_5_2 $(COPT) $(SYSCFLAGS) $(MYCFLAGS) 
LDFLAGS= -lpthread $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

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

ROSIE_A=$(HOME)/src/librosie/librosie.a

LUA_A=$(HOME)/submodules/lua/src/liblua.a

$(LUA_A):
	@echo "Missing Rosie object files.  Need to build rosie first."
	@false

.PHONY: lua_objs
# lua_objs: $(LUA_A)
# 	mkdir -p liblua
# 	cd liblua && ar x $(LUA_A)

ALL= dynamic static mt

dynamic.o: dynamic.c dynamic.h
	$(CC) -o $@ -c dynamic.c $(CFLAGS)

dynamic: dynamic.o
	$(CC) -o $@ dynamic.o 

static.o: static.c static.h
	$(CC) -o $@ -c static.c $(CFLAGS)

static: static.o $(ROSIE_A) $(LUA_A)
	$(CC) -o $@ static.o $(ROSIE_A) $(LUA_A)

mt.o: mt.c #mt.h
	$(CC) -o $@ -c mt.c $(CFLAGS)

mt: mt.o $(ROSIE_A) $(LUA_A)
	$(CC) -o $@ mt.o $(ROSIE_A) $(LUA_A)

clean:
	$(RM) dynamic.o dynamic
	$(RM) static.o static
	$(RM) mt.o mt

depend:
	@$(CC) $(CFLAGS) -MM *.c

test: static dynamic
	@echo Running C client tests on librosie
	./static
	DYLD_LIBRARY_PATH=.. ; ./dynamic
	@echo
	@echo TODO: CHECK EXIT CODE FROM TEST PROGRAMS

installtest:
	@echo No tests of C client configured to use system installation of librosie

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
.PHONY: default o a clean echo none test installtest

static.o: static.c static.h 
dynamic.o: dynamic.c dynamic.h 
