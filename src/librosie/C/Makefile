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

LUA_DYLIB_NAME=lua.5.3
ROSIE_DYLIB_NAME=rosie
ifeq ($(PLATFORM), macosx)
LUA_DYLIB=../lib$(LUA_DYLIB_NAME).dylib
ROSIE_DYLIB=../lib$(ROSIE_DYLIB_NAME).dylib
else
LUA_DYLIB=../lib$(LUA_DYLIB_NAME).so
ROSIE_DYLIB=../lib$(ROSIE_DYLIB_NAME).so
endif


ALL= dynamic static mt

dynamic.o: dynamic.c dynamic.h
	$(CC) -o $@ -c dynamic.c $(CFLAGS)

# TODO: Should not have liblua.so dependency here!
dynamic: dynamic.o $(LUA_DYLIB)
	$(CC) -o $@ dynamic.o $(LUA_DYLIB) $(SYSLIBS)

static.o: static.c static.h
	$(CC) -o $@ -c static.c $(CFLAGS)

static: static.o $(ROSIE_A) $(LUA_DYLIB)
	$(CC) -o $@ static.o $(ROSIE_A) $(LUA_DYLIB) $(SYSLIBS)

mt.o: mt.c #mt.h
	$(CC) -o $@ -c mt.c $(CFLAGS)

mt: mt.o $(ROSIE_A) $(LUA_DYLIB)
	$(CC) -o $@ mt.o $(ROSIE_A) $(LUA_DYLIB) $(SYSLIBS)

clean:
	$(RM) dynamic.o dynamic
	$(RM) static.o static
	$(RM) mt.o mt

depend:
	@$(CC) $(CFLAGS) -MM *.c

test: static dynamic
	@echo Running C client tests on librosie
	./static
	./dynamic $(ROSIE_DYLIB)
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
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX -std=gnu99 -D_GNU_SOURCE=1 -fPIC" SYSLIBS="-ldl -lm -lpthread" CC=$(CC)

macosx:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLDFLAGS="-bundle -undefined dynamic_lookup" SYSLIBS="-lpthread" CC=$(CC)

macosx: CFLAGS += -std=gnu99

windows:
	@echo Windows installation not yet supported.

## Targets that do not create files
.PHONY: default o a clean echo none test installtest

static.o: static.c static.h 
dynamic.o: dynamic.c dynamic.h 
