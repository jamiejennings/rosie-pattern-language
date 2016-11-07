# Rosie Pattern Language installation information

## All platforms

### What happens during installation

When you make a local clone of the Rosie repository using `git clone`, by default the
contents will be placed into a directory called `rosie-pattern-language`.

This is called the *Rosie Home Directory* in other documentation, and is usually written
`ROSIE_HOME`.  When you `cd` into this directory and type `make`, the following things
happen:

* Several git submodules will be cloned into the `rosie-pattern-language` directory
* Each submodule will be built using `make` and `gcc` (or `cc`)
* The `lua` submodule produces the lua compiler, `luac`, which is used to compile Rosie
* The `./bin/rosie` executable is created by the Makefile (it is a one line script)
* A "sniff test" is run to make sure that Rosie can run

*Note: The executable script `./bin/rosie` contains a reference to the installation directory.*

### make install

If you run `make install`, a link in `/usr/local/bin` (by default) will be created.  This
link will point to `bin/rosie` in the rosie directory.  Set the make variable `DESTDIR` to
change the install directory, e.g.

```shell
make install DESTDIR=/tmp
```

### Updating the installation

If there is an update to rosie and you use `git pull` to update your copy, you should then
run `make` again, in order to rebuild any components that have changed.


### Moving the installation around

You can copy/move the rosie installation directory anywhere, e.g.

```shell
mv rosie-pattern-language /usr/local/share/rosie
```

But you **must** re-run `make` in the new directory in order to re-generate `bin/rosie`,
which contains a reference to the rosie install directory.  Then re-run `make install` to
update the `/usr/local/bin` link to also point to the new location.

### The $sys feature

On the command line, in custom scripts, and in rosie manifest files, you will occasionally
want to refer to the Rosie Home Directory and its `rpl` directory of pattern definitions.
Rosie understands the filename prefix `$sys` and translates it to the Rosie Home
Directory.  For example,

```shell
jennings$ rosie -f '$sys/rpl/network.rpl' -grep network.ip_address /etc/resolv.conf 
9.0.128.50 
9.0.130.50 
jennings$ 
``` 

Recall also that the prefix `$lib` can be used only within a manifest file, and refers to
the directory in which the manifest file is currently located.  This makes it easy to move
pattern libraries around simply by copying collections of `rpl` and manifest files.

## OS X when installed via brew

[Homebrew](http://brew.sh) hides the download and build steps, and it performs the
equivalent of `make install` as well.  The "formula" for installing rosie is stored in the
[homebrew-rosie](https://github.com/jamiejennings/homebrew-rosie) repository on github.
By default, it puts all of the important rosie files into `/usr/local/share/rosie` and the
executable in `/usr/local/bin/rosie`.

## Using or developing with multiple rosie versions

You can have as many versions of rosie installed locally as you wish, since each one
refers only to files within its own ROSIE_HOME.  For convenience, the script `bin/rosie`
looks for the environment variable `$ROSIE_HOME`, and if it is set, then that version of
rosie will be launched.

In short, it is possible to launch rosie by typing simply `rosie`, provided that
`/usr/local/bin` is on your `$PATH`.  When `$ROSIE_HOME` is not set, you will get the
system installation of rosie.  When `$ROSIE_HOME` is set, you will get the version
installed in that location.

## When in doubt

If you are unsure about your current configuration of rosie, use `rosie -info` and pay
attention to the first two pieces of information: the Rosie Home Directory and the
version.  In the example below, rosie is installed in `/usr/local/Cellar`, which is where
`brew` keeps its files.  (Brew creates a link to these files from `/usr/local/share`, as
shown.)

```shell 
jennings$ rosie -info
Local installation information:
  ROSIE_HOME = /usr/local/Cellar/rosie/current/share/rosie
  ROSIE_VERSION = 0.99g
  HOSTNAME = jamies-mbp-2.raleigh.ibm.com
  HOSTTYPE = x86_64
  OSTYPE = darwin16
Current invocation: 
  current working directory = /Users/jjennings/Work/Dev/public/rosie-pattern-language
  invocation command = bash /usr/local/bin/rosie -info
  script value of Rosie home = /usr/local/Cellar/rosie/current/share/rosie
  environment variable $ROSIE_HOME is not set
jennings$
jennings$ ls -l /usr/local/share/rosie
lrwxr-xr-x  1 jjennings  admin  35 Nov  7 14:36 /usr/local/share/rosie -> ../Cellar/rosie/current/share/rosie
jennings$ ls -l /usr/local/bin/rosie
lrwxr-xr-x  1 jjennings  admin  33 Nov  7 14:36 /usr/local/bin/rosie -> ../Cellar/rosie/current/bin/rosie
jennings$ 
``` 


