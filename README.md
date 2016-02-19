# This is Rosie Pattern Language v0.88

### Rosie will tidy up raw data (text), recognize key pieces of data, and create JSON structured output

#### Better than regex

Like a supercharged version of Regular Expressions (regex), Rosie matches input text
against predefined patterns.

Unlike most regex tools, Rosie will also generate structured (JSON) output, and
will soon do all kinds of other things to the input data as it is being parsed.

#### Docs

To write patterns in Rosie Pattern Language, see [the RPL documentation](doc/rpl.md).

For an introduction to Rosie and explanations of the key concepts, see
[Rosie's _raison d'etre_](doc/raisondetre.md).

The [interactive read-eval-print loop (repl)](doc/repl.md) is documented separately.

### How to build and run

After cloning or downloading the Rosie Pattern Language code repository, run
`make` in the download directory.  The `makefile` will print instructions for
how to build Rosie for your platform.

In most cases, there is just one step, which is to run `make <platform>` where
`<platform>` is, e.g. `macosx` or `linux`.  The `makefile` will download the
needed prerequisites and compile them.  Then a quick test of the Rosie Pattern
Engine is invoked, just to make sure it runs and prints the correct version
number.

You should see this message if all went well: `Rosie Pattern Engine installed successfully!`

### A quick test

For a quick test of Rosie's capabilities, use the Rosie Pattern Engine to look
for a basic set of patterns in any text file on your system.  Good candidates
may be `/etc/resolv.conf` or `/var/log/system.log`.  Use the pattern
`basic.matchall` for this, e.g.

![Screen capture](doc/images/system.log-example.jpg "Rosie processing a MacOS system log")

*Note:* In order to show just a few lines of output, the output of Rosie is piped
into the Unix utility `head`, which will print (in this case) the first 5
lines.  Try removing `head` to see the entire log file, i.e. `./run basic.matchall /var/log/system.log`.


Rosie is parsing the log file into fields that are printed in various colors.
Unparsed data is shown in black text.  To see which colors correspond to which
RPL patterns, type `./run -patterns` to see all defined and loaded patterns and
the color (if any) that is assigned to them for output at the terminal.

To see the JSON version of this output, try adding the JSON flag (and perhaps
displaying just one line of output, as in this example):

```
./run -json basic.matchall /var/log/system.log | head -1
```


## Useful tips

### Write patterns on the command line

You can write patterns on the command line, e.g.:  (output will be in color,
which is not shown here)

```
bash-3.2$ ./run 'network.ip_address common.word' /etc/hosts
127.0.0.1 localhost 
255.255.255.255 broadcasthost 
```

And the same command but with JSON output:

``` 
bash-3.2$ ./run -json 'network.ip_address common.word' /etc/hosts 
{"*":{"1":{"network.ip_address":{"text":"127.0.0.1","pos":1}},"2":{"common.word":{"text":"localhost","pos":11}},"text":"127.0.0.1\tlocalhost","pos":1}}
{"*":{"1":{"network.ip_address":{"text":"255.255.255.255","pos":1}},"2":{"common.word":{"text":"broadcasthost","pos":17}},"text":"255.255.255.255\tbroadcasthost","pos":1}}
``` 

### The "-grep" option that looks for your pattern anywhere in the input

By default, Rosie matches your pattern against an entire line.  But what if you
want grep-like functionality, where a pattern may be found anywhere in the
input?  Try a command like this:

``` 
./run -grep basic.network_patterns /etc/resolv.conf
```

For example:

![Image of command line use of the grep option](doc/images/resolv.conf.example.jpg "Example of the -grep option")

Note that the pattern `basic.network_patterns` contains patterns that match path
names as well as email addresses, domain names, and ip addresses. 

### Pattern debugging on the command line

Interactive pattern debugging can be done using the read-eval-print loop (see
[interactive pattern development](doc/repl.md).  But debugging output can also
be generated at the command line.

The `-debug` command line option generates verbose output about every step of
matching.  It is best to use this option with only **one line of input** because
so much output is generated.


## Adding new patterns for Rosie to load on start-up

When Rosie starts, all the Rosie Pattern Language (rpl) files listed in
```./MANIFEST ``` are loaded.  You can write your own patterns and add your
pattern file to the end of the manifest, so that Rosie will load them.
(Currently, this is the only way to add new patterns.)


### Rosie Pattern Engine pre-requisites

The Rosie Pattern Engine's installation script looks for the pre-requisites
within the Rosie install directory, so that Rosie has its own copy of, e.g. Lua
and lpeg.

In addition to the Lua binary, the Rosie Pattern Engine uses some native
libraries written for Lua.

pre-req | description
--------|----------------------------------
lua     | Lua binary (command line driver)
lpeg	| Lua Parse Expression Grammars library
cjson 	| JSON encoding/decoding library

Like Lua, the native libraries must be built for your particular
platform.  The `makefile` included with Rosie should download and compile the
prerequisites, all within the Rosie install directory.


