_Notes_

To build `rtest`, type `make`.

The `./setup.sh` script will create a symlink to `librosie.so` in this
directory, which will allow you to run `./rtest` (after building it).

Alternatively, you can use the script `./rtest.sh`, which temporarily sets the
library load path so that `librosie.so` will be found, and then runs `./rtest`.



