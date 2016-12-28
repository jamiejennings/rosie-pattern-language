<!--  -*- Mode: GFM; -*-                                                     -->
<!--                                                                         -->
<!--  cli.md                                                                 -->
<!--                                                                         -->
<!--  © Copyright IBM Corporation 2016.                                      -->
<!--  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)-->
<!--  AUTHOR: Jamie A. Jennings                                              -->

## Rosie Pattern Language Command Line Interface

### Running Rosie

The `bin/rosie` script in the Rosie install directory starts the command line interface (CLI), which can be used to match rpl pattern expressions against files of data.  (To match against a single string, use the [interactive read-eval-print loop (repl)](repl.md).)

The Rosie Pattern Engine reads input files one line at a time, and tries to match each line against the pattern expression given on the command line.

One way to run Rosie is to define an alias.  In the bash shell, you can write (substituting your Rosie install directory for mine):

```
alias rosie='/Users/jjennings/Dev/rosie-pattern-language/bin/rosie'
``` 

Or use `make install` to place a link in `/usr/local/bin/rosie`.

More detail about the way Rosie is installed can be found [here](install.md).


### A quick "sniff test" to see if things are working

A good first experiment when using Rosie is to match the pattern `basic.matchall` against an arbitrary input file.  The output will (by default) be text in colors that correspond to the pattern that was matched, such as red for network addresses, blue for dates and times, etc.

### Output format (encoding)

Rosie supports output in a few formats, which are controlled by the value of the `-encode` option:

| Value     | Meaning |
| --------- | ------- |
| `color`   | print just the leaf nodes of the match tree, using colors where defined |
| `nocolor` | print just the leaf nodes of the match tree, not using any color |
| `fulltext`| print the entire match string, not using any color (kind of like the Unix `grep` tool) |
| `json`    | output a JSON-encoded match structure (a tree) |


### Help is available

``` 
$ rosie --help
Usage: rosie [--version] [-v] [-m <manifest>] [-f <load>] [-r <rpl>]
       [-h] <command> ...

Rosie Pattern Language v0.99i

Options:
   --version             Print rosie version
   -v, --verbose         Output additional messages
   -m <manifest>, --manifest <manifest>
                         Load a manifest file (default: $sys/MANIFEST)
   -f <load>, --load <load>
                         Load an RPL file
   -r <rpl>, --rpl <rpl> Inline RPL statements
   -h, --help            Show this help message and exit.

Commands:
   info                  Print rosie installation information
   patterns              List installed patterns
   repl                  Run rosie in interactive mode
   match                 Run RPL match

Additional information.
```

For help on a command, pass the `-h` or `--help` option after a command.
```
$ bin/rosie match --help
Usage: rosie match ([-e] | [-g]) [-s] [-a] [-o <encode>] [-h]
       <pattern> [[<filename>] ...]

Run RPL match

Arguments:
   pattern               RPL pattern
   filename              Input filename (default: -)

Options:
   -s, --wholefile       Read input file as single string
   -a, --all             Output non-matching lines to stderr
   -e, --eval            Output detailed trace evaluation of pattern process.
   -g, --grep            Weakly emulate grep using RPL syntax
   -o <encode>, --encode <encode>
                         Output format (default: color)
   -h, --help            Show this help message and exit.
```
