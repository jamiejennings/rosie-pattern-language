## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie.so, on which Rosie's foreign function interface is based. 
##
## © Copyright IBM Corporation 2016.
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

CC= gcc
CFLAGS= -O2 -Wall -Wextra -DLUA_COMPAT_5_2 $(SYSCFLAGS) $(MYCFLAGS) $(COPT)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

RM= rm -f

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS=  -I$(HOME)/submodules/lua/include
MYLDFLAGS= -L$(HOME)/submodules/lua/src
MYLIBS= 
MYOBJS=

LUA_A=	$(HOME)/submodules/lua/src/liblua.a

ALL= librosie.so

librosie.o: librosie_gen.c librosie_gen.h librosie.c librosie.h
	$(CC) -o $@ -c librosie.c $(CFLAGS)

librosie.so: librosie.o
	$(CC) -shared -o $@ librosie.o $(LDFLAGS) $(LUA_A)

clean:
	$(RM) librosie.so librosie.o rtest.o rtest librosie_gen.c librosie_gen.h

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
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E -ldl -lreadline"

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
