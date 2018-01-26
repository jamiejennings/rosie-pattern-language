## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie
##
## © Copyright IBM Corporation 2016, 2017, 2018.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## -----------------------------------------------------------------------------
##
## Use "DEBUG=1" on the command line to cause librosie to log to stderr
## 
## Use 'make LUADEBUG=1' to build into rosie_abs a lua repl that can
## be accessed by passing '-D' as the first command line parameter.
##
## The following libraries and executables, when sitting in the
## directory DIR, look for the rosie home directory in DIR/rosie:
##  librosie.a, librosie.[so|dylib]
##  rosie_rel
##
## The following executable looks for the rosie home directory in the
## BUILD directory:
##  rosie_abs
##
## The executable rosie_abs is copied to $(BUILD_ROOT)/bin/rosie where
## it serves as the executable for the local installation.
##
## -----------------------------------------------------------------------------


# We must use the same default as in top-level makefile, so that we
# can run "make installtest" locally from the librosie directory
# without having to specify DESTDIR.
DESTDIR=/usr/local

HOME = $(shell cd ../..; pwd)
ROSIE = "$(HOME)/bin/rosie"

ifdef ROSIE_HOME
rosie_home=-DROSIE_HOME="\"$(ROSIE_HOME)\""
else
rosie_home=-DROSIE_HOME="\"$(shell cd ../..; pwd)\""
endif

ifdef LUADEBUG
lua_debug="-DLUADEBUG"
lua_repl=lua_repl.o
endif

ifdef DEBUG
COPT+=-DDEBUG
endif

REPORTED_PLATFORM=$(shell (uname -o || uname -s) 2> /dev/null)
ifeq ($(REPORTED_PLATFORM), Darwin)
PLATFORM=macosx
else ifeq ($(REPORTED_PLATFORM), GNU/Linux)
PLATFORM=linux
else
PLATFORM=none
endif

LUA_A=$(HOME)/submodules/lua/src/liblua.a
ROSIE_DYLIB_NAME=rosie
ROSIE_A=lib$(ROSIE_DYLIB_NAME).a

ifeq ($(PLATFORM),macosx)
SYSCFLAGS=-DLUA_USE_MACOSX -fPIC
SYSLIBS=
SYSLDFLAGS=-dynamiclib
CFLAGS += -std=gnu99
ROSIE_DYLIB=lib$(ROSIE_DYLIB_NAME).dylib
else 
SYSCFLAGS=-DLUA_USE_LINUX -std=gnu99 -D_GNU_SOURCE=1 -fPIC
SYSLDFLAGS=-shared
SYSLIBS=-lpthread -ldl -lm
ROSIE_DYLIB=lib$(ROSIE_DYLIB_NAME).so
endif

ifeq ($(PLATFORM), macosx)
CC= cc
else
CC= gcc
endif

CFLAGS= -O2 -Wall -Wextra -pthread -DMULTIPLE_THREADS -DLUA_COMPAT_5_2 $(COPT) $(SYSCFLAGS) $(MYCFLAGS) 
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

AR= ar rcu
RANLIB= ranlib
RM= rm -f

MYCFLAGS=  -I$(HOME)/submodules/lua/include -I$(HOME)/submodules/rosie-lpeg/src 
MYLDFLAGS= 
MYLIBS= 
MYOBJS=

default: $(ROSIE_DYLIB) librosie.a rosie_abs rosie_rel

$(LUA_A):
	@echo "Missing Rosie object files.  Need to build rosie first."
	@false


liblua: $(LUA_A)
	mkdir -p liblua
	cd liblua && ar x $(LUA_A)

ALLCLIENTS= python C

ifeq ($(CLIENTS),all)
  clients=$(ALLCLIENTS)
else
  clients=$(CLIENTS)
endif

lua_repl.o: lua_repl.c lua_repl.h
	$(CC) -o $@ -c lua_repl.c $(CFLAGS) -I$(HOME)/submodules/lua/src -fvisibility=hidden

dependent_objs=liblua/*.o \
               $(HOME)/submodules/rosie-lpeg/src/*.o \
               $(HOME)/submodules/lua-cjson/*.o 

librosie.o: librosie.c librosie.h logging.c registry.c rosiestring.c
	$(CC) -fvisibility=hidden -o $@ -c librosie.c $(CFLAGS) $(lua_debug)

librosie.so: librosie.o liblua
	$(CC) -o $@ librosie.o $(dependent_objs) $(LIBS) $(LDFLAGS)

librosie.dylib: librosie.o liblua
	$(CC) -install_name $(shell pwd)/$@ -o $@ librosie.o $(dependent_objs) $(LIBS) $(LDFLAGS)

librosie.a: librosie.o lua_repl.o liblua
	$(AR) $@ librosie.o lua_repl.o $(dependent_objs)
	$(RANLIB) $@

# We explicitly leave the LUADEBUG option out of building rosie_rel,
# which is the executable meant for installation with "make install"
# in the top level rosie-pattern-language directory.
rosie_rel.o: rosie.c librosie.c librosie.h logging.c registry.c rosiestring.c lua_repl.c lua_repl.h
	$(CC) -o $@ -c rosie.c $(CFLAGS)

rosie_abs.o: rosie.c librosie.c librosie.h logging.c registry.c rosiestring.c lua_repl.c lua_repl.h
	$(CC) -o $@ -c rosie.c $(CFLAGS) $(lua_debug) $(rosie_home)

rosie_abs: rosie.c rosie_abs.o lua_repl.o liblua
	$(CC) -o $@ rosie_abs.o $(LIBS) -lreadline lua_repl.o $(HOME)/submodules/lua-readline/src/*.o $(dependent_objs)

rosie_rel: rosie.c rosie_rel.o lua_repl.o liblua
	$(CC) -o $@ rosie_rel.o $(LIBS) -lreadline lua_repl.o $(HOME)/submodules/lua-readline/src/*.o $(dependent_objs)

clean:
	$(RM) *.o *.dylib *.so *.a rosie_abs rosie_rel
	$(RM) -rf liblua
	@here="$(shell pwd)"; \
	for client in $(ALLCLIENTS); do cd $${here}/$$client && $(MAKE) clean; done

depend:
	@$(CC) $(CFLAGS) -MM *.c

test: $(ROSIE_DYLIB) $(ROSIE_A)
	@if [ -z "$(clients)" ]; then \
	echo Missing client list to test.  Try "CLIENTS=all".; \
	exit 1; \
	fi; \
	here="$(shell pwd)"; \
	for client in $(clients); do cd $${here}/$$client && $(MAKE) test; done

installtest:
	@here="$(shell pwd)"; \
	for client in $(clients); do cd $${here}/$$client && $(MAKE) DESTDIR=$(DESTDIR) installtest; done

echo:
	@echo "HOME= $(HOME)"
	@echo "PLAT= $(PLAT)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(LDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"
	@echo "LUADEBUG= $(LUADEBUG)"


.PHONY: default clean echo

