## Rosie Pattern Engine read/eval/print loop

## Start the repl from the CLI

In the [Rosie Command Line Interface documentation](cli.md) you will find the
`-repl` switch, which starts the interactive read/eval/print loop after
processing any other command line options.  For example:

```
jjennings$ ./bin/rosie -repl
Rosie CLI warning: missing pattern argument
Rosie CLI warning: missing filename arguments
This is Rosie v0.99a
Rosie> 
Rosie> .help
   Rosie Help

   At the prompt, you may enter a command, an identifier name (to see its
   definition), or an RPL statement.  Commands start with a dot (".") as
   follows:

   .load path                    load RPL file (see note below)
   .manifest path                load manifest file (see note below)
   .match exp quoted_string      match RPL exp against (quoted) input data
   .eval exp quoted_string       show full evaluation (trace)
   .debug {on|off}               show debug state; with an argument, set it
   .patterns                     list patterns in the environment
   .clear <id>                   clear the pattern definition of <id>, * for all
   .help                         print this message

   Note on paths to RPL and manifest files: A filename may begin with $sys,
   which refers to the Rosie install directory, or $(VAR), which is the value of
   the environment variable $VAR.  For filenames inside a manifest file, $lib
   refers to the directory containing the manifest file.

   EOF (^D) will exit the read/eval/print loop.
Rosie> 
```

## Explore

### Help is available with _.help_

All repl commands begin with a dot ".".  In addition to typing commands (which
can load rpl files or match patterns against input), you can also (1) explore
the pattern environment, and (2) define new rpl patterns.

### Exploring the environment

The `.patterns` command lists all the patterns currently loaded.  By default,
Rosie loads the file `./MANIFEST`, which lists some files of rpl patterns.  Some
of the patterns have been assigned colors, so that the default output on the
terminal screen can indicate matches using colored text.  A few of the patterns
loaded by default are:

``` 
any                            alias                   
basic.datetime_patterns        definition      blue    
basic.matchall                 definition              
basic.network_patterns         definition      red     
common.number                  definition      underline
common.path                    definition      green   
common.word                    definition      yellow  
csv.line                       definition              
```

You can see the definition of a pattern by typing its name at the repl prompt:

``` 
Rosie> any
alias any = .
Rosie> common.number
assignment common.number = (common.denoted_hex / common.float / common.int / common.hex)
Rosie> 
``` 

### Defining new patterns

Defining new patterns is easy.  (Note that definitions made in the repl are not
saved.)

``` 
Rosie> foo = [:digit:]+ "!!"
Rosie> foo
assignment foo = (([[:digit:]])+ "!!")
Rosie> 
```

You can also load rpl files with `.load` and manifest files with `.manifest`.
File names may be absolute, relative, or Rosie-specific.  The Rosie-specific
file prefixes are `$sys` (referring to the Rosie install directory) and `$(VAR)`
(which refers to the environment variable _$VAR_).

Note that file names can contain embedded spaces as long as they are escaped
with a backslash, `'\ '`.

### Clearing pattern definitions

In the unusual situation in which you want to erase a pattern definition, use
the `.clear _<id>_` command.  To clear the entire environment, use `.clear *`.
The base environment, consisting of a handful of built-in primitive patterns
(such as `.` which matches any character, and `$` which matches only at the end
of the input), will always remain.


``` 
Rosie> foo
assignment foo = (([[:digit:]])+ "!!")
Rosie> .clear foo
Rosie> foo
Repl: undefined identifier: foo
Rosie> .clear *
Pattern environment cleared
Rosie> .patterns

Pattern                        Type            Color 
------------------------------ --------------- --------
$                              alias 
.                              alias           black 
~                              alias 

3 patterns
Rosie>
``` 

## Develop and debug patterns

The commands `.match` and `.eval` match expressions against sample input
specified on the repl command line.  The `.match` command produces a match
(shown as a JSON structure) or a trace which details where the matching process
failed.  The `.debug` command will turn off this trace if you don't want to see
it.

``` 
Rosie> foo = [:digit:]+ "!!"
Rosie> foo
assignment foo = (([[:digit:]])+ "!!")
Rosie> .match foo "42!!"
{"foo": 
   {"text": "42!!", 
    "pos": 1.0}}
Rosie> .match foo "42!"
     SEQUENCE: ({[:digit:]}+ ~ "!!")
     FAILED to match against input "42!"
     Explanation:
        SEQUENCE: ({[:digit:]}+ ~)
        Matched "42" (against input "42!")
        Explanation:
  1........QUANTIFIED EXP (raw): {[:digit:]}+
           Matched "42" (against input "42!")
           REFERENCE: ~
           Matched "" (against input "!")
           This identifier is a built-in RPL pattern
  2.....LITERAL: "!!"
        FAILED to match against input "!"

Repl: No match  (turn debug off to hide the match evaluation trace)
Rosie> .debug off
Debug is off
Rosie> .match foo "42!"
Repl: No match  (turn debug on to show the match evaluation trace)
Rosie>
``` 

The trace is produced by the `.eval` function, which evaluates each clause in an
rpl pattern and shows the results.  When you use `.eval`, you will see an entire
trace of the matching process, whether it succeeds or not.




