## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie
##
## © Copyright IBM Corporation 2016, 2017, 2018.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## -----------------------------------------------------------------------------
##
## Use "DEBUG=1" on the command line to cause librosie to log
## informational and error messages to stderr.
## 
## Use 'LUADEBUG=1' to build into rosie_local/rosie_system a lua repl
## that can be accessed by passing '-D' as the first command line
## parameter.  This feature is needed for the white-box testing
## invoked by "make test".
##
## The executable rosie_local looks for the rosie home directory in
## the BUILD directory, while rosie_system looks for the rosie home
## directory in $(DESTDIR), which is the install directory.  
##
## -----------------------------------------------------------------------------

ALLCLIENTS= python C

ifeq ($(CLIENTS),all)
  clients=$(ALLCLIENTS)
else
  clients=$(CLIENTS)
endif

# We must use the same default as in top-level makefile, so that we
# can run "make installtest" locally from the librosie directory
# without having to specify DESTDIR.
DESTDIR=/usr/local
HOME = $(shell cd ../..; pwd)

ifdef LUADEBUG
lua_debug="-DLUADEBUG"
lua_repl=lua_repl.o
endif

ifdef DEBUG
debug_flag=-DDEBUG
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
  CC=cc
  SYSCFLAGS=-DLUA_USE_MACOSX -fPIC
  SYSLIBS=
  SYSLDFLAGS=-dynamiclib
  CFLAGS += -std=gnu99
  ROSIE_DYLIB=lib$(ROSIE_DYLIB_NAME).dylib
else 
  CC=gcc
  SYSCFLAGS=-DLUA_USE_LINUX -std=gnu99 -D_GNU_SOURCE=1 -fPIC
  SYSLDFLAGS=-shared
  SYSLIBS=-lpthread -ldl -lm
  ROSIE_DYLIB=lib$(ROSIE_DYLIB_NAME).so
endif

MYCFLAGS=-I$(HOME)/submodules/lua/include -I$(HOME)/submodules/rosie-lpeg/src 
MYLDFLAGS= 
MYLIBS= 
MYOBJS=

CFLAGS= -O2 -Wall -Wextra -pthread -DMULTIPLE_THREADS -DLUA_COMPAT_5_2 $(SYSCFLAGS) $(MYCFLAGS)
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

AR= ar rcu
RANLIB= ranlib
RM= rm -f

dependent_objs=liblua/*.o \
               $(HOME)/submodules/rosie-lpeg/src/*.o \
               $(HOME)/submodules/lua-cjson/*.o 

.PHONY:
default:
	@echo Use "make local" or "make system"
	@exit -1

.PHONY:
local: rosie_home=-DROSIE_HOME="\"$(HOME)\""
local: local/$(ROSIE_DYLIB) local/librosie.a local/rosie

.PHONY:
system: rosie_home=-DROSIE_HOME="\"$(DESTDIR)/lib/rosie\""
system: system/$(ROSIE_DYLIB) system/librosie.a system/rosie

$(LUA_A):
	@echo "Missing Rosie object files.  Need to build rosie first."
	@false

liblua: $(LUA_A)
	mkdir -p liblua
	cd liblua && ar x $(LUA_A)

lua_repl.o: lua_repl.c lua_repl.h
	$(CC) -o $@ -c lua_repl.c $(CFLAGS) -I$(HOME)/submodules/lua/src -fvisibility=hidden

%/librosie.o: librosie.c librosie.h logging.c registry.c rosiestring.c
	mkdir -p $(dir $@)
	$(CC) -fvisibility=hidden -o $@ -c librosie.c $(CFLAGS) $(debug_flag) $(lua_debug) $(rosie_home)

%/librosie.so: %/librosie.o liblua
	mkdir -p $(dir $@)
	$(CC) -o $@ $< $(dependent_objs) $(LIBS) $(LDFLAGS)

%/librosie.dylib: %/librosie.o liblua
	mkdir -p $(dir $@)
	$(CC) -o $@ $< $(dependent_objs) $(LIBS) $(LDFLAGS)

%/librosie.a: %/librosie.o liblua
	$(AR) $@ $< $(dependent_objs)
	$(RANLIB) $@

%/rosie.o: rosie.c librosie.c librosie.h logging.c registry.c rosiestring.c 
	mkdir -p $(dir $@)
	$(CC) -o $@ -c rosie.c $(CFLAGS) $(debug_flag) $(lua_debug) $(rosie_home)

%/rosie: %/rosie.o lua_repl.o liblua
	mkdir -p $(dir $@)
	$(CC) -o $@ $< lua_repl.o $(LIBS) -lreadline $(HOME)/submodules/lua-readline/src/*.o $(dependent_objs)

# Note: 'clean' also cleans the client directories because those are
# "known" here, and not known by the top level Makefile.
clean:
	$(RM) *.o *.dylib *.so *.a
	$(RM) -rf liblua local system
	@here="$(shell pwd)"; \
	for client in $(ALLCLIENTS); do cd $${here}/$$client && $(MAKE) clean; done

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
	@echo "DEBUG= $(DEBUG)"


.PHONY: default clean echo test installtest

