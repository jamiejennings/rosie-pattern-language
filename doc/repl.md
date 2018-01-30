## Rosie Pattern Engine read/eval/print loop

## Start the repl from the CLI

Use `rosie repl` to start the interactive read/eval/print loop.  You can
optionally load rpl files and specify rpl code on the command line, e.g.

``` 
$ rosie --rpl 'd=[:digit:]' repl
Rosie 1.0.0-alpha
Rosie> d
[:digit:]
Rosie>
```

EOF (^D) will exit the read/eval/print loop.


## REPL Commands

### Help is available with _.help_

All repl commands begin with a dot ".".  In addition to typing commands (which
can load rpl files or match patterns against input), you can also (1) explore
the pattern environment, and (2) define new rpl patterns.

### Exploring the environment

The `.list` command lists all the patterns currently loaded.  Additional
patterns may be loaded by using the `.load` command to load an RPL file, or the
`import` RPL statement (*not* a command, so no dot in front).

``` 
$ rosie repl
Rosie 1.0.0-alpha
Rosie> .list


Name                     Cap? Type     Color           Source
------------------------ ---- -------- --------------- -------------------------
$                             pattern  default;bold    builtin/prelude
.                             pattern  default;bold    builtin/prelude
^                             pattern  default;bold    builtin/prelude
ci                            macro                    builtin/prelude
error                         function                 builtin/prelude
find                          macro                    builtin/prelude
findall                       macro                    builtin/prelude
keepto                        macro                    builtin/prelude
message                       function                 builtin/prelude
~                             pattern  default;bold    builtin/prelude

10/10 names shown
Rosie> import os
Rosie> .list

Name                     Cap? Type     Color           Source
------------------------ ---- -------- --------------- -------------------------
$                             pattern  default;bold    builtin/prelude
.                             pattern  default;bold    builtin/prelude
^                             pattern  default;bold    builtin/prelude
ci                            macro                    builtin/prelude
error                         function                 builtin/prelude
find                          macro                    builtin/prelude
findall                       macro                    builtin/prelude
keepto                        macro                    builtin/prelude
message                       function                 builtin/prelude
os                            package                  /usr/local/lib/rosie/rpl/os.rpl
~                             pattern  default;bold    builtin/prelude

11/11 names shown
Rosie> .list os


Name                     Cap? Type     Color           Source
------------------------ ---- -------- --------------- -------------------------
os                            package                  /usr/local/lib/rosie/rpl/os.rpl

1/11 names shown
Rosie> .list os.*


Name                     Cap? Type     Color           Source
------------------------ ---- -------- --------------- -------------------------
$                             pattern  default;bold    builtin/prelude
.                             pattern  default;bold    builtin/prelude
^                             pattern  default;bold    builtin/prelude
ci                            macro                    builtin/prelude
error                         function                 builtin/prelude
find                          macro                    builtin/prelude
findall                       macro                    builtin/prelude
keepto                        macro                    builtin/prelude
message                       function                 builtin/prelude
path                     Yes  pattern  green           os
path_unix                     pattern  default;bold    os
path_windows                  pattern  default;bold    os
~                             pattern  default;bold    builtin/prelude

13/13 names shown
Rosie> 
``` 

You can see the definition of a pattern by typing its name at the repl prompt.
Some identifiers are bound to packages, or macros/functions, and not patterns.

``` 
Rosie> os.path
{path_unix / path_windows}
Rosie> os
<environment: 0x7fdd9bf221a0>
Rosie> 
``` 

### Defining new patterns

Defining new patterns is easy: simply type RPL statements at the REPL prompt.  (Note that definitions made in the repl are not
saved.)

``` 
Rosie> foo = [:digit:]+ "!!"
Rosie> foo
{{[:digit:]}+ ~ "!!"}
Rosie> 
```

You can also load rpl files with `.load` and import packages with `import` (no
dot).  Note that file names can contain embedded spaces as long as they are escaped with a backslash, `'\ '`.

### Un-defining pattern definitions

In the unusual situation in which you want to erase a pattern definition, use
the `.undefine _<id>_` command.  


## Develop and debug patterns

The commands `.match` and `.trace` match expressions against sample input
specified on the repl command line.  The `.match` command produces a match
(shown as a JSON structure), but it will produce a trace if the match failes.  A
trace is a (lengthy) explanation of the matching process that shows each step.

The `.debug` command will turn off the automatic printing of a trace if you
don't want to see it when a match fails.

A trace can be produced any time by the `.trace` command, whose arguments are
just like `.match`.






