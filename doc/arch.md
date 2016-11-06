## Rosie Pattern Engine pre-requisites

### Components needed by the Rosie Pattern Engine

The Rosie Pattern Engine's installation script looks for the pre-requisites
within the Rosie install directory, so that Rosie has its own copy of the
pre-requisite software, such as Lua and lpeg.

The pre-requisites are:

pre-req | description
--------|----------------------------------
lua     | Lua binary (command line driver)
lpeg	| Lua Parse Expression Grammars library
cjson 	| JSON encoding/decoding library

Like Lua, the native libraries must be built for your particular
platform.  The `makefile` included with Rosie will download and compile the
prerequisites, all within the Rosie install directory.

### Tools needed to compile and install

The tools needed to compile and install Rosie and its pre-requisites are
commonly available on most systems.

The build instructions for Rosie are in its `makefile`, which uses `cc` (MacOSX)
or `gcc` (Linux) to compile the components needed by the Rosie Pattern Engine.
Those components (see table above) are downloaded automatically using `curl`.

tool | description
-----|------------
make | processes makefile to build Rosie
cc   | on MacOSX, the compiler that is part of Apple's developer tools
gcc  | on Linux, the GNU C compiler that is most prevalent

Note: You can override the choice of compiler on the command line, e.g. if you want to use `gcc` on MacOSX:

```
make CC=gcc macosx
```


