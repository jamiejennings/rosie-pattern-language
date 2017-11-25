## -*- Mode: Makefile; -*-                                             
##
## © Copyright IBM Corporation 2016, 2017.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

HOME = $(shell cd ../../..; pwd)
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

PLATFORMS = linux macosx windows

default: $(PLATFORM)

ifeq ($(PLATFORM), macosx)
CC= clang
else
CC= gcc
endif

clean:
	$(RM) rosie.pyc 

test:
	python test.py local

installtest:
	python test.py system

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

macosx:

windows:
	@echo Windows installation not yet supported.

## Targets that do not create files
.PHONY: default clean echo none test installtest
