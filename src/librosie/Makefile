## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie.so, on which Rosie's foreign function interface is based. 
##
## © Copyright IBM Corporation 2016, 2017.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## Use "DEBUG=1" on the command line to cause librosie to log to stderr

# Use 'make LUADEBUG=1' to build in a lua repl that can be accessed by
# passing '-D' as the first command line parameter.


# We must use the same default as in top-level makefile, so that we
# can run "make installtest" locally from the librosie directory
# without having to specify DESTDIR.
DESTDIR=/usr/local

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

LUA_A=$(HOME)/submodules/lua/src/liblua.a
ROSIE_DYLIB_NAME=rosie
ROSIE_A=lib$(ROSIE_DYLIB_NAME).a

ifeq ($(PLATFORM),macosx)
SYSCFLAGS=-DLUA_USE_MACOSX -fPIC
SYSLIBS=-lreadline
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

default: $(ROSIE_DYLIB) $(ROSIE_A)

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

ifdef LUADEBUG
lua_repl=lua_repl.o
lua_debug="-DLUADEBUG"
endif

lua_repl.o: lua_repl.c lua_repl.h
	$(CC) -o $@ -c lua_repl.c $(CFLAGS) -I$(HOME)/submodules/lua/src -fvisibility=hidden

dependent_objs=liblua/*.o \
               $(lua_repl) \
               $(HOME)/submodules/rosie-lpeg/src/*.o \
               $(HOME)/submodules/lua-cjson/*.o \
               $(HOME)/submodules/lua-readline/src/*.o

librosie.o: $(lua_repl) librosie.c librosie.h logging.c registry.c rosiestring.c
	$(CC) -fvisibility=hidden -o $@ -c librosie.c $(CFLAGS) $(lua_debug)

librosie.so: librosie.o liblua
	$(CC) -o $@ librosie.o $(dependent_objs) $(SYSLIBS) $(LDFLAGS)

librosie.dylib: librosie.o liblua
	$(CC) -install_name $(shell pwd)/$@ -o $@ librosie.o $(dependent_objs) $(SYSLIBS) $(LDFLAGS)

librosie.a: librosie.o liblua
	$(AR) $@ librosie.o $(dependent_objs)
	$(RANLIB) $@

clean:
	$(RM) librosie.dylib librosie.so librosie.o librosie.a lua_repl.o
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

