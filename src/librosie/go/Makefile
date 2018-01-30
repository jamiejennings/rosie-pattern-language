## -*- Mode: Makefile; -*-                                             
##
## © Copyright IBM Corporation 2016, 2017, 2018
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

go_installed=$(shell command -v "go")

.PHONY:
rtest: src/rtest/rtest.go src/rosie/rosie.go
	if [ -n "$(go_installed)" ]; then \
	./setup.sh; \
	. ./setvars && go build rtest; \
	fi

clean:
	$(RM) rtest setvars
	$(RM) src/rosie/librosie.a
	$(RM) -rf src/rosie/include

test: rtest
	if [ -n "$(go_installed)" ]; then \
	  ./rtest; \
	else \
	  echo "Go installation not found, skipping test of go client"; \
	fi


echo:
	@echo "HOME= $(HOME)"
	@echo "PLAT= $(PLAT)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(LDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"


## Targets that do not create files
.PHONY: clean echo test
