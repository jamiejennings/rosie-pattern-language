# Makefile for building TEST driver program for Rosie

# The value of HOME should be the Rosie install directory (called ROSIE_HOME in
# the Rosie source).  It's important that this value be passed without any additional
# surrounding quotation marks.
HOME = `cd ../../..; pwd`

# Use COPT="-DDEBUG" on the command line to enable debug printing


# See ../doc/readme.html for installation and customization instructions.

# == CHANGE THE SETTINGS BELOW TO SUIT YOUR ENVIRONMENT =======================

# Your platform. See PLATS for possible values.
PLAT= none

CC=gcc -std=gnu99
CFLAGS= -O2 -Wall -Wextra -DLUA_COMPAT_5_2 $(SYSCFLAGS) $(MYCFLAGS) -DROSIE_HOME=$(HOME) $(COPT)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

AR= ar rcu
RANLIB= ranlib
RM= rm -f

SYSCFLAGS=
SYSLDFLAGS=
SYSLIBS=

MYCFLAGS=  -I/Users/jjennings/Work/Dev/rosie-pattern-language/tmp/lua-5.3.2/include
MYLDFLAGS= -L/Users/jjennings/Work/Dev/rosie-pattern-language/tmp/lua-5.3.2/src
MYLIBS= 
MYOBJS=

# == END OF USER SETTINGS -- NO NEED TO CHANGE ANYTHING BELOW THIS LINE =======

PLATS= aix bsd c89 freebsd generic linux macosx mingw posix solaris

LUA_A=	/Users/jjennings/Work/Dev/rosie-pattern-language/tmp/lua-5.3.2/src/liblua.a
LIBROSIE= /Users/jjennings/Work/Dev/rosie-pattern-language/src/C/librosie/librosie.so


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
	$(RM) librosie.so librosie.o rtest.o rtest

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

# list targets that do not create files (but not all makes understand .PHONY)
.PHONY: all $(PLATS) default o a clean depend echo none


rtest.o: rtest.c librosie.h
librosie.o: librosie.c
