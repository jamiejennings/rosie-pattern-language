## -*- Mode: Makefile; -*-                                             
##
## Makefile for building librosie.so, on which Rosie's foreign function interface is based. 
##
## © Copyright IBM Corporation 2016, 2017.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## Use "DEBUG=1" on the command line to cause librosie to log to stderr

# Same default as in top-level makefile, so that we can run "make
# installtest" locally from the librosie directory without having to
# specify DESTDIR.
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
LUA_DYLIB_NAME=lua.5.3
ROSIE_DYLIB_NAME=rosie
ROSIE_A=lib$(ROSIE_DYLIB_NAME).a

ifeq ($(PLATFORM),macosx)
SYSCFLAGS=-DLUA_USE_MACOSX
SYSLIBS=
SYSLDFLAGS=-undefined dynamic_lookup
CFLAGS += -std=gnu99
LUA_DYLIB=lib$(LUA_DYLIB_NAME).so
LIBLUA_LDFLAGS=-dynamiclib -compatibility_version 5.3 -current_version 5.3.2
ROSIE_DYLIB=lib$(ROSIE_DYLIB_NAME).dylib
else 
SYSCFLAGS=-DLUA_USE_LINUX -std=gnu99 -D_GNU_SOURCE=1 -fPIC
SYSLDFLAGS=
SYSLIBS=-lpthread -shared -ldl -lm
LUA_DYLIB=lib$(LUA_DYLIB_NAME).so
LIBLUA_LDFLAGS=-shared -ldl -lm
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

# lib$(LUA_DYLIB_NAME).dylib: lua_objs
# #	$(CC) -dynamiclib -install_name $(shell pwd)/$@ -compatibility_version 5.3 -current_version 5.3.2 -o $@ liblua/*.o
# 	$(CC) -dynamiclib -compatibility_version 5.3 -current_version 5.3.2 -o $@ liblua/*.o

# lib$(LUA_DYLIB_NAME).so: lua_objs
# 	$(CC) -o $@ liblua/*.o $(LIBLUA_LDFLAGS)
# 	cp $@ ../../lib/$@

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

dependent_objs=liblua/*.o ../../submodules/rosie-lpeg/src/*.o ../../submodules/lua-cjson/*.o

librosie.o: librosie.c librosie.h logging.c registry.c rosiestring.c
	$(CC) -o $@ -c librosie.c $(CFLAGS)

librosie.so: librosie.o liblua
	$(CC) -o $@ librosie.o $(dependent_objs) $(SYSLIBS) $(LDFLAGS)

librosie.dylib: librosie.o liblua
	$(CC) -dynamiclib -install_name $(shell pwd)/$@ -o $@ librosie.o $(dependent_objs) $(SYSLIBS) $(LDFLAGS)

librosie.a: librosie.o liblua
	$(AR) $@ librosie.o $(dependent_objs)
	$(RANLIB) $@

clean:
	$(RM) librosie.dylib librosie.so librosie.o librosie.a liblua.5.3.dylib
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

none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

.PHONY: windows
windows:
	@echo Windows installation not yet supported.

## Targets that do not create files
.PHONY: default o a clean echo none

