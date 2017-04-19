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

verbose: cmake
	$(MAKE) -C ${builddir} CMAKE_ARGS="-DCMAKE_VERBOSE_MAKEFILE=ON" VERBOSE=1

install: cmake
	$(MAKE) -C ${builddir} install

cmake ${builddir}/CMakeCache.txt:
	mkdir -p ${builddir}
	cd ${builddir} && cmake $(CMAKE_ARGS) "$(@D)" ..

clean:
	$(RM) -rf ${builddir}

package: cmake
	$(MAKE) -C ${builddir} package
