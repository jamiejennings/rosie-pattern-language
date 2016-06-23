<!--  -*- Mode: GFM; -*-                                                     -->
<!--                                                                         -->
<!--  cli.md                                                                 -->
<!--                                                                         -->
<!--  © Copyright IBM Corporation 2016.                                      -->
<!--  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)-->
<!--  AUTHOR: Jamie A. Jennings                                              -->

## Rosie Pattern Language Command Line Interface

### Running Rosie

The `run` script in the Rosie install directory starts the command line interface (CLI), which can be used to match rpl pattern expressions against files of data.  (To match against a single string, use the [interactive read-eval-print loop (repl)](repl.md).)

The Rosie Pattern Engine reads input files one line at a time, and tries to match each line against the pattern expression given on the command line.

A good way to run Rosie is to define an alias.  In the bash shell, you can write (substituting your Rosie install directory for mine):

```
alias rosie='/Users/jjennings/Dev/rosie-pattern-language/run'
``` 

Or if you cd into the Rosie install directory, this:

``` 
alias rosie=`pwd`/run
``` 

Putting this alias definition into your `~/.bashrc` file will load it every time an interactive bash shell starts.  Now you can type `rosie` to start the Rosie CLI. 

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
bash-3.2$ ./run -help
This is Rosie v0.99a
The Rosie install directory is: /Users/jjennings/Work/Dev/rosie-pattern-language
Rosie help:
Rosie usage: ./run <options> <pattern> <filename>*
Valid <options> are: -help -patterns -verbose -all -repl -grep -eval -wholefile -manifest -f -e -encode

-help              prints this message
-patterns          print list of available patterns
-verbose           output warnings and other informational messages
-all               write matches to stdout and non-matching lines to stderr
-repl              start Rosie in the interactive mode (read-eval-print loop)
-grep              emulate grep (weakly), but with RPL, by searching for all
                   occurrences of <pattern> in the input
-eval              output a detailed "trace" evaluation of how the pattern
                   processed the input; this feature generates LOTS of output,
                   so best to use it on ONE LINE OF INPUT
-wholefile         read the whole input file into memory as a single string,
                   instead of line by line
-manifest <arg>    load the manifest file <arg> instead of MANIFEST from $sys
                   (the Rosie install directory); use a single dash '-' to
                   load no manifest file
-f <arg>           load the RPL file <arg>, after manifest (if any) is loaded;
                   use a single dash '-' to read from the stdin
-e <arg>           compile the RPL statements in <arg>, after manifest and
                   RPL file (if any) are loaded
-encode <arg>      encode output in <arg> format: color (default), nocolor,
                   fulltext, or json

<pattern>            RPL expression, which may be the name of a defined pattern,
                     against which each line will be matched
<filename>+          one or more file names to process, the last of which may be
                     a dash "-" to read from standard input

Notes: 
(1) lines from the input file for which the pattern does NOT match are written
    to stderr so they can be redirected, e.g. to /dev/null
(2) the -eval option currently does not work with the -grep option

bash-3.2$
```


