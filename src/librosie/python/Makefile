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

default: test

true=$(shell command -v true)
python2=$(shell command -v python2 || command -v python || command -v true 2>/dev/null)
python3=$(shell command -v python3 || command -v python || command -v true 2>/dev/null)

ifeq ($(python2),$(python3))
python3=$(true)
endif

ROSIE_DYLIB_NAME=rosie
ifeq ($(PLATFORM), macosx)
CC= clang
ROSIE_DYLIB=lib$(ROSIE_DYLIB_NAME).dylib
else
CC= gcc
ROSIE_DYLIB=lib$(ROSIE_DYLIB_NAME).so
endif

test: ../local/$(ROSIE_DYLIB)
	@if [ "$(python2)" != "$(true)" ]; then \
		echo Testing with $(shell $(python2) --version 2>&1); \
		$(python2) -c 'import cffi'; \
		if [ $$? -eq 0 ]; then LD_LIBRARY_PATH=../local $(python2) test.py local; \
		else echo "cffi not found -- skipping test"; \
		fi; \
	fi
	@if [ "$(python3)" != "$(true)" ]; then \
		echo Testing with $(shell $(python3) --version 2>&1); \
		$(python3) -c 'import cffi'; \
		if [ $$? -eq 0 ]; then LD_LIBRARY_PATH=../local $(python3) test.py local; \
		else echo "cffi not found -- skipping test"; \
		fi; \
		LD_LIBRARY_PATH=../local $(python3) test.py local; \
	fi

clean:
	$(RM) rosie.pyc 

# Some linux distros may not have DESTDIR on their search path by
# default, like when running as root in a docker image.  (This can be
# checked with `/sbin/ldconfig -v`.) So we explicitly set
# LD_LIBRARY_PATH in the SYSTEM installation test.
installtest:
	LD_LIBRARY_PATH=$(DESTDIR)/lib python test.py system

echo:
	@echo "HOME= $(HOME)"
	@echo "PLAT= $(PLAT)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(LDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"


## Targets that do not create files
.PHONY: default clean echo test installtest
