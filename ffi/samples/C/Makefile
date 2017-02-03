## -*- Mode: BSDmakefile; -*-                                         
##
## Makefile for building sample C driver program for librosie
##
## © Copyright IBM Corporation 2016.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## Use "DEBUG=1" on the command line to enable verbose debugging output

HOME = `cd ../../..; pwd`
ROSIE = "$(HOME)/rosie"

ifdef DEBUG
COPT = "-DDEBUG"
endif

# Use -DDEBUG on the command line to enable debug printing

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

CC=gcc
CFLAGS= -O2 -Wall -Wextra -DLUA_COMPAT_5_2 $(SYSCFLAGS) $(MYCFLAGS) $(COPT)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS= -std=gnu99 -I$(HOME)/submodules/lua/include -I$(HOME)/ffi/librosie
MYLDFLAGS= 
MYLIBS= 
MYOBJS=

LIBROSIE= $(HOME)/ffi/librosie/librosie.so

## Targets

ALL= rtest

rtest: rtest.c
	$(CC) -o $@ rtest.c $(CFLAGS) $(LIBROSIE) $(LIBS)

clean:
	$(RM) rtest.o rtest

echo:
	@echo "HOME= $(HOME)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(LDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"

none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

linux:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E -ldl -lm -lreadline"

macosx:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLIBS= CC=$(CC)

macosx: CC="gcc -std=gnu99"

gen_C:
librosie_gen.c:
librosie_gen.h:
	@echo Generating librosie C functions and headers
	echo 'api = require "api"; api.write_C_FILES();' | $(ROSIE) -D >/dev/null

## Targets that do not create files
.PHONY: default o a clean echo none

rtest.o: rtest.c librosie.h
