builddir=build

ifeq (,$(VERBOSE))
	MAKEFLAGS:=$(MAKEFLAGS)s
	ECHO=echo
else
	ECHO=@:
endif

.DEFAULT: all
.PHONY: all build clean cmake

all: build

build: cmake
	$(MAKE) -C ${builddir}

install: cmake
	$(MAKE) -C ${builddir} install

cmake ${builddir}/CMakeCache.txt:
	mkdir -p ${builddir}
	cd ${builddir} && cmake $(CMAKE_ARGS) "$(@D)" ..

clean:
	$(RM) -rf ${builddir}

package: cmake
	$(MAKE) -C ${builddir} package
