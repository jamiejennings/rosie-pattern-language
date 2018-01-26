# Makefile for building the Rosie Pattern Language CLI
# Requires ../src/librosie/librosie.a and a system installation of libreadline/libedit

# Use 'make LUADEBUG=1' to build in a lua repl that can be accessed by
# passing '-D' as the first command line parameter.

REPORTED_PLATFORM=$(shell (uname -o || uname -s) 2> /dev/null)
ifeq ($(REPORTED_PLATFORM), Darwin)
PLATFORM=macosx
else ifeq ($(REPORTED_PLATFORM), GNU/Linux)
PLATFORM=linux
else
$(error Unsupported platform (uname reported "$(REPORTED_PLATFORM)"))
endif

ROSIE_CLI_A=../librosie/librosiecli.a

ifeq ($(PLATFORM),macosx)
CC=cc
SYSCFLAGS=-DLUA_USE_MACOSX -fPIC -std=gnu99
SYSLIBS=-lreadline
SYSLDFLAGS=
endif

ifeq ($(PLATFORM),linux)
CC=gcc
SYSCFLAGS=-DLUA_USE_LINUX -fPIC -std=gnu99 -D_GNU_SOURCE=1
SYSLIBS=-lpthread -ldl -lm -lreadline
SYSLDFLAGS=
endif

CFLAGS=-O2 -Wall -Wextra -I../librosie -I../../submodules/rosie-lpeg/src -I../../submodules/lua/src $(SYSCFLAGS)
LDFLAGS=$(SYSLDFLAGS) 
LIBS=$(SYSLIBS)

RM= rm -f

ifdef LUADEBUG
lua_debug="-DLUADEBUG"
endif

default: rosie

rosie: $(ROSIE_CLI_A) rosie.c
	$(CC) -o $@ rosie.c $(CFLAGS) $(lua_debug) $(LDFLAGS) $(LIBS) $(ROSIE_CLI_A)

clean:
	$(RM) rosie rosie.o

depend:
	@$(CC) $(CFLAGS) -MM l*.c

echo:
	@echo "PLAT= $(PLAT)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(SYSLDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "AR= $(AR)"
	@echo "RANLIB= $(RANLIB)"
	@echo "RM= $(RM)"


.PHONY: echo default clean depend echo

