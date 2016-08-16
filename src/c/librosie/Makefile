# Makefile for building TEST driver program for Rosie

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

CC=gcc -std=gnu99
CFLAGS= -O2 -Wall -Wextra -DLUA_COMPAT_5_2 $(SYSCFLAGS) $(MYCFLAGS) $(COPT)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

AR= ar rcu
RANLIB= ranlib
RM= rm -f

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS=  -I$(HOME)/tmp/lua-5.3.2/include
MYLDFLAGS= -L$(HOME)/tmp/lua-5.3.2/src
MYLIBS= 
MYOBJS=

# == END OF USER SETTINGS -- NO NEED TO CHANGE ANYTHING BELOW THIS LINE =======

PLATS= aix bsd c89 freebsd generic linux macosx mingw posix solaris

LUA_A=	$(HOME)/tmp/lua-5.3.2/src/liblua.a
LIBROSIE= $(HOME)/src/C/librosie/librosie.so


# Targets start here.
default: $(PLAT)

all:	librosie.so rtest

rtest: librosie.so rtest.c
	$(CC) -o $@ rtest.c $(CFLAGS) $(LIBROSIE) $(LUA_A) $(LIBS)

librosie.o: librosie.c librosie.h
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
	@echo "AR= $(AR)"
	@echo "RANLIB= $(RANLIB)"
	@echo "RM= $(RM)"

# Convenience targets for popular platforms
ALL= librosie.so rtest

none:
	@echo "Please do 'make PLATFORM' where PLATFORM is one of these:"
	@echo "   $(PLATS)"

linux:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E -ldl -lreadline"

macosx:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLIBS= CC=$(CC)

macosx: CC="gcc -std=gnu99"

gen_C:
librosie_gen.c:
librosie_gen.h:
	@echo Generating librosie C functions and headers
	echo 'api = require "api"; api.write_C_FILES();' | $(ROSIE) -D >/dev/null

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all $(PLATS) default o a clean depend echo none


rtest.o: rtest.c librosie.h
librosie.o: librosie_gen.c librosie_gen.h librosie.c librosie.h 
