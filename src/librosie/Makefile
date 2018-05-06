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
## Use 'LUADEBUG=1' to include into the build a lua repl that can be
## accessed by passing '-D' to the rosie CLI as the first command line
## parameter.  This feature is needed for the white-box testing
## invoked by "make test".
##
## After compilation, the resulting files are placed in the "binaries"
## subdirectory.  The contents of $(CONFIG_FILE) will tell you what
## ROSIE_HOME path was compiled into the binaries, which will there
## look for rosie files at runtime.
##
## -----------------------------------------------------------------------------

ALLCLIENTS= python C go

ifeq ($(CLIENTS),all)
  clients=$(ALLCLIENTS)
else
  clients=$(CLIENTS)
endif

HOME = $(shell cd ../..; pwd)
CONFIG_FILE = rosie_home.cfg

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

AR= ar rc
RANLIB= ranlib
RM= rm -f

dependent_objs=liblua/*.o \
               $(HOME)/submodules/rosie-lpeg/src/*.o \
               $(HOME)/submodules/lua-cjson/*.o 

.PHONY:
default:
	@if [ -z "$(ROSIE_HOME)" ]; then \
	echo "ROSIE_HOME undefined. Please supply a value on the command line."; \
	false; \
	fi; \
	PREV_CONFIGURATION="$(shell head -1 $(CONFIG_FILE) 2>/dev/null)"; \
	if [ "$(ROSIE_HOME)" = "$$PREV_CONFIGURATION" ]; then \
            echo "Configuration of ROSIE_HOME has not changed"; \
	else \
	    echo "Prior configuration of ROSIE_HOME is different; must rebuild"; \
	    echo "$(ROSIE_HOME)" >$(CONFIG_FILE); \
	fi; \
	$(MAKE) all

.PHONY:
all: binaries/$(ROSIE_DYLIB) binaries/librosie.a binaries/rosie

$(LUA_A):
	@echo "Missing Rosie object files.  Need to build the other rosie components first."
	@false

liblua: $(LUA_A)
	mkdir -p liblua
	cd liblua && ar x $(LUA_A)

lua_repl.o: lua_repl.c lua_repl.h
	$(CC) -o $@ -c lua_repl.c $(CFLAGS) -I$(HOME)/submodules/lua/src -fvisibility=hidden

%/librosie.o: $(CONFIG_FILE) librosie.c librosie.h logging.c registry.c rosiestring.c
	mkdir -p $(dir $@)
	$(CC) -fvisibility=hidden -o $@ -c librosie.c $(CFLAGS) $(debug_flag) $(lua_debug) -DROSIE_HOME="\"$(ROSIE_HOME)\""

%/librosie.so: %/librosie.o liblua
	mkdir -p $(dir $@)
	$(CC) -o $@ $< $(dependent_objs) $(LIBS) $(LDFLAGS)

%/librosie.dylib: %/librosie.o liblua
	mkdir -p $(dir $@)
	$(CC) -o $@ $< $(dependent_objs) $(LIBS) $(LDFLAGS)

%/librosie.a: %/librosie.o liblua
	$(AR) $@ $< $(dependent_objs)
	$(RANLIB) $@

%/rosie.o: $(CONFIG_FILE) rosie.c librosie.c librosie.h logging.c registry.c rosiestring.c 
	mkdir -p $(dir $@)
	$(CC) -o $@ -c rosie.c $(CFLAGS) $(debug_flag) $(lua_debug) -DROSIE_HOME="\"$(ROSIE_HOME)\""

%/rosie: %/rosie.o lua_repl.o liblua
	mkdir -p $(dir $@)
	$(CC) -o $@ $< lua_repl.o -lreadline $(HOME)/submodules/lua-readline/src/*.o $(dependent_objs) $(LIBS)

# Note: 'clean' also cleans the client directories because those are
# known here in $(ALLCLIENTS), and not known by the top level Makefile.
clean:
	$(RM) *.o *.dylib *.so *.a
	$(RM) -rf liblua binaries
	@here="$(shell pwd)"; \
	for client in $(ALLCLIENTS); do cd $${here}/$$client && $(MAKE) clean; done

test:
	@if [ -z "$(clients)" ]; then \
	echo Missing client list to test.  Try \"make CLIENTS=all\".; \
	exit 1; \
	fi; \
	here="$(shell pwd)"; \
	for client in $(clients); \
	do cd $${here}/$$client && $(MAKE) test; \
	if [ $$? -ne 0 ]; then \
		echo "TEST FAILED: $$client"; exit -1; \
		fi; \
	done

installtest:
	@here="$(shell pwd)"; \
	for client in $(clients); do cd $${here}/$$client && $(MAKE) installtest $(MAKEFILEFLAGS); done

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

