[![Build Status](https://travis-ci.org/jamiejennings/rosie-pattern-language.svg?branch=master)](https://travis-ci.org/jamiejennings/rosie-pattern-language)
# This is Rosie Pattern Language

## Rosie will tidy up raw data (text), recognize key pieces of data, and create JSON structured output

### Better than regex

Rosie is a supercharged alternative to Regular Expressions (regex), matching
patterns against any input text.  Rosie ships with hundreds of sample patterns
for timestamps, network addresses, email addresses, CSV files, and many more.

Unlike most regex tools, Rosie can generate structured (JSON) output.  And,
Rosie has an interactive pattern development mode to help write and debug
patterns. 


### Small and fast

The Rosie Pattern Engine takes less than 400KB (yes, *kilobytes*) of disk space, and around 20MB of
memory.  Typical log files are parsed at around 40,000 lines/second on my 4-year
old MacBook Pro, where other (popular) solutions do not achieve 10,000 lines/second.

Rosie Pattern Language is ideal for big data analytics, because Rosie is fast,
has predictable performance (unlike most regex engines), and generates json
output for downstream analysis.

For the PL and CS geeks among us, some technical notes are [here](doc/geek.md).

## A quick look at Rosie

For a quick test of Rosie's capabilities, use the Rosie Pattern Engine to look
for a basic set of patterns in any text file on your system.  Good candidates
may be `/etc/resolv.conf` or `/var/log/system.log`.  Use the pattern
`basic.matchall` for this.  In the example below, we use a few lines from the
Mac OSX system log (from the Rosie test suite):

![Screen capture](doc/images/system.log-example.jpg "Rosie processing a MacOS system log")

Rosie is parsing the log file into fields that are printed in various colors.
To see which colors correspond to which RPL patterns, type `./run -patterns` to
see all defined and loaded patterns and the color (if any) that is assigned to
them for output at the terminal.

To see the JSON version of the Rosie output, use the `-encode` option to specify
`json`.  In the example below, the pattern being matched is `common.word
basic.network_patterns`.  Rosie finds a line matching this pattern, and the
pattern matches at position 1 of the input line.  The sub-match `common.word`
also begins at position 1, and the sub-match `basic.network_patterns` begins at
position 12:
```
jamiejennings$ rosie -encode json 'common.word basic.network_patterns' /etc/resolv.conf | rjsonpp
{"*": 
   {"pos": 1.0, 
    "text": "nameserver 10.0.1.1", 
    "subs": 
      [{"common.word": 
         {"text": "nameserver", 
          "pos": 1.0}}, 
       {"basic.network_patterns": 
         {"pos": 12.0, 
          "text": "10.0.1.1", 
          "subs": 
            [{"network.ip_address": 
               {"text": "10.0.1.1", 
                "pos": 12.0}}]}}]}}
jamiejennings$ 
``` 
(Note: `rjsonpp` is a json pretty-printer, similar to `json_pp`.)

## How to build: clone the repo, and type 'make'

After cloning the repository, there is just one step: `make`.  The `makefile` will download the
needed prerequisites, compile them, and run a quick test.

You should see this message if all went well: `Rosie Pattern Engine installed successfully!`

## Current status

The current release is the "version 1.0 candidate".  The RPL language syntax and
semantics are stable, as is the (relatively new) API.  The current release is
labeled "v0.99x" where x begins with "a" and will be advanced as bugs are fixed
and small enhancements are made.

## Docs

Rosie documentation:
* [Command Line Interface documentation](doc/cli.md)
* [Rosie Pattern Language Reference](doc/rpl.md)
* [Interactive read-eval-print loop (repl)](doc/repl.md)

Blog posts on Rosie:
* [Project Overview](https://developer.ibm.com/open/rosie-pattern-language/)
* [Introduction](https://developer.ibm.com/open/2016/02/20/world-data-science-needs-rosie-pattern-language/)
* [Parsing Spark logs](https://developer.ibm.com/open/2016/04/26/develop-test-rosie-pattern-language-patterns-part-1-parsing-log-files/)
* Parsing CSV files (forthcoming)
* Generating patterns automatically (forthcoming)

For an introduction to Rosie and explanations of the key concepts, see
[Rosie's _raison d'etre_](doc/raisondetre.md).

Rosie's internal components, as well as the utilities needed to build Rosie are
listed [here](doc/arch.md).

Rosie announcements on Twitter: https://twitter.com/jamietheriveter

## Useful tips

### Sample patterns are in the rpl directory

The file `MANIFEST` lists the Rosie Pattern Language files that Rosie compiles
on startup.  These files are typically in the `rpl` directory, but could be
anywhere.  Browse the `rpl` directory to see how patterns are written.

### Write patterns on the command line

You can write patterns on the command line, e.g.:  (output will be in color,
which is not shown here)

```
jamiejennings$ rosie 'network.ip_address common.word' /etc/hosts
127.0.0.1 localhost 
255.255.255.255 broadcasthost 
```

And the same command but with JSON output:

``` 
bash-3.2$ rosie -encode json 'network.ip_address common.word' /etc/hosts 
{"*":{"1":{"network.ip_address":{"text":"127.0.0.1","pos":1}},"2":{"common.word":{"text":"localhost","pos":11}},"text":"127.0.0.1\tlocalhost","pos":1}}
{"*":{"1":{"network.ip_address":{"text":"255.255.255.255","pos":1}},"2":{"common.word":{"text":"broadcasthost","pos":17}},"text":"255.255.255.255\tbroadcasthost","pos":1}}
``` 

### The "-grep" option looks for your pattern anywhere in the input

By default, Rosie matches your pattern against an entire line.  But what if you
want grep-like functionality, where a pattern may be found anywhere in the
input?  Try a command like this:

``` 
rosie -grep basic.network_patterns /etc/resolv.conf
```

For example:

![Image of command line use of the grep option](doc/images/resolv.conf.example.jpg "Example of the -grep option")

Note that the pattern `basic.network_patterns` contains patterns that match path
names as well as email addresses, domain names, and ip addresses. 

### Pattern debugging on the command line

Interactive pattern debugging can be done using the read-eval-print loop (see
[interactive pattern development](doc/repl.md)).  But debugging output can also
be generated at the command line.

The `-debug` command line option generates verbose output about every step of
matching.  It is best to use this option with only **one line of input** because
so much output is generated.

### Adding new patterns for Rosie to load on start-up

When Rosie starts, all the Rosie Pattern Language (rpl) files listed in
`MANIFEST ` are loaded.  You can write your own patterns and add your
pattern file to the end of the manifest, so that Rosie will load them.
(Currently, this is the only way to add new patterns.)


## How you can help

### Calling Rosie from Go, Python, node.js, Ruby, Java, or ...?

Rosie is available as a [C library](ffi) that is callable from these
languages.  There are [sample programs](ffi/samples) that demonstrate it, and
these could be improved by turning them into proper libraries, one for each
target language.

If you're a Python hacker, we could use your help turning our
sample `librosie` client into a Python module.  Same for the other languages.

And since `librosie` is built on `libffi`, it's pretty easy to access Rosie from
other languages.  This is another great area to make a contribution to the
project.

### Write new patterns!

We are happy to add more patterns to the initial library we've started in the
[rpl directory](rpl), whether they build on what we have or are entirely new.

