## Rosie Pattern Engine build and installation details

### Overview

Rosie is written in C and Lua.  And, the Lua virtual machine is written in C.
As a result, building Rosie requires a C toolchain.  The overall build process
is roughly this:

1. Compile C components, one of which is the Lua compiler, luac
2. Use luac to compile the Lua components
3. "Sniff test" the Rosie executable (bin/rosie) to make sure it starts

The Rosie tests are organized into white-box tests and black-box tests.  The
white-box tests require Rosie to be built with the LUADEBUG option (see
Makefile).  That option enables a Lua REPL to be built into Rosie, and that Lua
REPL is used to test all the language features.

The black-box tests are primarily clients of librosie, written in languages like
C, Python, and Go.  These require only a regular build of Rosie, with no special
options.

### Librosie requires a Rosie installation

Librosie requires the compiled Lua files (in the lib directory) and the rpl
files (in the rpl directory).  The directory above rpl and lib is called the
_Rosie home_.  Librosie is compiled with knowledge of its Rosie home, so that it
can find its files at run-time.

When you `git clone` (or `tar -xf`) a Rosie distribution, the contents are
placed into the directory `rosie-pattern-language` by default.  This is the
_build directory_, and serves as the home for a local build:

<blockquote>
<ul>

<item>`make` creates an executable (bin/rosie) whose home is the
build directory.
<p>
<item>`make install` creates an executable whose home is `DESTDIR` (defaults
to `/usr/local`).  That executable is copied to `DESTDIR/bin/rosie`, and its
Rosie home is created in `DESTDIR/lib/rosie`.

</ul>
</blockquote>


### Components compiled from C source

Name    | Description
--------|----------------------------------
cjson 	| JSON encoding/decoding library
lua     | Lua run-time
luac     | Lua compiler
rosie-lpeg	| Enhanced version of the lpeg library
lua-readline | Stub that calls the already-installed readline library
librosie  | Library implementing the core Rosie functionality (not the CLI, REPL)

If you don't have a C compiler installed, here is one way to obtain `gcc`,
`make`, and `git`:

* RedHat family: `sudo yum install gcc make git`
* Debian family: `sudo apt-get install gcc make git`
* Arch: `pacman -S make gcc git`


The build process requires `readline.so` and `readline.h`, and will
complain if they are not present.  Other users have found the following commands
useful, though your mileage may vary:

* RedHat family: `sudo yum install readline readline-devel git gcc`
* Debian family: `sudo apt install libreadline6 libreadline6-dev`
* Arch: `pacman -S readline`


### Tools needed to compile and install

The tools needed to compile and install Rosie and its pre-requisites are
commonly available on most systems.

The build instructions for Rosie are in its `makefile`, which uses `cc` (MacOSX)
or `gcc` (Linux) to compile the components needed by the Rosie Pattern Engine.
Those components (see table above) are downloaded automatically using `curl`.

Tool | Description
-----|------------
make | processes makefile to build Rosie
cc   | on MacOSX, the compiler that is part of Apple's developer tools
gcc  | on Linux, the GNU C compiler that is most prevalent

Note: You can override the choice of compiler on the command line, e.g. if you want to use `gcc` on MacOSX:

```
make CC=gcc macosx
```


