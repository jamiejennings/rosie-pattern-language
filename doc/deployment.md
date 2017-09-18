## Rosie Pattern Engine deployment details

### Components compiled from C source

Name    | Description
--------|----------------------------------
cjson 	| JSON encoding/decoding library
lua     | Lua run-time
luac     | Lua compiler
rosie-lpeg	| Enhanced version of the lpeg library
lua-readline | Stub that calls the already-installed readline library

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


