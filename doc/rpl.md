<!--  -*- Mode: GFM; -*-                                                       -->
<!--                                                                           -->
<!--  © Copyright IBM Corporation 2016, 2017, 2018                             -->
<!--  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  -->
<!--  AUTHOR: Jamie A. Jennings                                                -->

# RPL 1.1 Language Reference

Notes:
1. The RPL language is versioned independently of Rosie itself.
2. See also the [Command Line Interface manual](man/rosie.html) and the interactive [read-eval-print loop (repl)](repl.md) documentation.
3. See also the [Standard Library documentation](standardlib.md).  The RPL
"standard library" is bundled with Rosie and contains many pre-defined patterns.

## Overview

RPL is a compiled, block-structured, lexically scoped, declarative pattern
expression language with a module system.  Names are bound to values of type
_pattern_, _macro_, _function_, and _environment_ (module), although only
patterns are first-class.

### What does this mean?

#### Properties of the language proper

RPL is **compiled** to a form of byte code that is specific to a _matching virtual
machine_ (mvm).  The mvm executes a small instruction set, taking input from a
byte array and produces either a _match_ or an indication that there is no
match.

The compilation process is essential to the design of RPL because it ensures
that many classes of errors can be found at compile time, i.e. in advance of the
deployment of an application that uses Rosie.

**Block structure** means there are lexical units (imaginatively called
"blocks") of code that we can talk about.  In RPL 1.1, there are two kinds of
blocks:
* Files of RPL code
* Grammars

Both kinds of blocks contain bindings, in which names are bound to pattern
expressions.  A file may also contain declarations like `import`.  RPL blocks do
not contain any control flow operators, because there are none.  RPL is a
**declarative expression language** for syntactic patterns, as are regular
expressions and context free grammars.  RPL is based on Parsing Expression
Grammars.

Blocks in RPL have **lexical scope**.  Within a file, all of the names being
bound are visible.  (The order of bindings does not matter.)  In RPL 1.1, file
scope does not, however, allow mutually recursive pattern definitions.

Inside a grammar block, all of the outer (file scope) names are visible, unless
they are shadowed by a local binding (in the grammar) of the same name.
Grammars allow mutually recursive pattern definitions, making them useful for
expressing patterns to match recursively defined syntax like JSON, XML, and
s-expressions.

The first binding in a grammar block is visible in its containing scope, i.e. in
the file scope (because grammars cannot be nested in RPL 1.1).  Any additional
bindings are visible only within the grammar block.

#### Properties of the module system

RPL has a **module system** in which a "file block" of code may define a
package, and another "file block" may use that package.  A file defines an RPL
package when it contains a _package declaration_.

Names in RPL may be _qualified_ or _unqualified_.  Qualified names have a
package prefix and a local name, e.g. `net.ip`.  A qualified name has a binding
when the package prefix is bound to a visible package and the local name is
exported from that package.  Unqualified names are just local names, with no
package prefix.

An **import declaration** instructs the compiler to bind a local name to a
package.  Typically this involves loading the package from a file.  In addition,
a (possibly empty) set of names become visible as qualified names using that
local name as a prefix.  So, the `import net` declaration gives us a local
binding for `net` (which is bound to a module) and makes visible names like
`net.ip`, `net.fqdn`, and others.

The module system is an important design point of RPL because it encourages
principled re-use of patterns through the construction and sharing of modules.
The Rosie "Standard Library" is a lofty name for a set of modules that are part
of the Rosie distribution.


### What is outside the language specification

Rosie implements an RPL compiler which is used to compile RPL pattern
expressions entered on the command line.  For convenience, the Rosie CLI
automatically imports packages referenced in such expressions.

Rosie also implements a read-eval-print loop (REPL) to support interactive
pattern debugging, including a trace facility that shows visually each step of
the matching process.

Neither the CLI nor the REPL are part of the RPL Language.


## Comments and white space

Comments begin with two dashes and end at the next newline character.  White space is not significant.

## Blocks

RPL 1.1 has two kinds of blocks: grammars and files.  Here we describe file blocks.

A file block is defined as follows in [the RPL code for Rosie](../rpl/rosie/rpl_1_1.rpl): 

```
rpl_statements = { {atmos ";" / package_decl / import_decl / language_decl / stmnt / syntax_error}* atmos $}
```

The pattern `atmos` captures whitespace and comments (the "atmosphere" in which
code lives).  A file block can contain empty statements (`;`), package
declarations, import declarations, language declarations, and things called
`stmnt` that should really be called _bindings_.  

| Item                 | Meaning                                                          | Example  |
| ---------------------|------------------------------------------------------------------|----------|
| language declaration | Declares the minimum RPL version required                        | `rpl 1.1` |
| package declaration  | The statements that follow define a package with the given name  | `package net` |
| import declaration   | Load the named package(s) by searching the library path          | `import word, num, net` |
| binding/statement    | Bind a name to a value (e.g. a pattern)                          | `d = [:digit:]` |

Each block element is explained in its own section, below.  No element is
required.  (A block may be empty.)  The compiler enforces the following
constraints on blocks:

* If the language declaration is present, it must be the first non-comment, non-whitespace item in the block.
* If the package declaration is present, it must come before any import declarations.
* Import declarations, if any, must come before the first binding.  There can be many import declarations.
* There can be many bindings.
* A given name may only be assigned once.

In RPL 1.1, a file may contain only one file block.

### Language declaration

This optional element declares that the block requires the given RPL major version, and at least the given minor version.  Major versions are assumed to be incompatible, and minor versions are assumed to be backwards compatible.

Example:
```
rpl 1.1
```

### Package declaration

If the block defines a package, it must contain a package declaration element giving the package name.  The name must follow the same rules as other identifiers in RPL, namely:

* It must start with an alphabetic character
* The remaining characters may be alphanumeric or the underscore

From [the RPL code for Rosie](../rpl/rosie/rpl_1_1.rpl): 

``` 
alias id_char = [[:alnum:]] / [[_]]
alias id = { [[:alpha:]] id_char* }
```

Example:
```
package num
```

The package name is used as a prefix by RPL code that imports a package.  The identifier `net.ipv4` has the prefix `net`, so it is a reference to a package imported under the name `net`.  Packages are typically stored in files, but the name of the file does not have to match the name of the package declared inside that file.  However, it is strongly recommended that a file called `x.rpl` will declare `package x` and not some other package name.


### Import declaration

There can be many import declarations (or none).  An import declaration tells the RPL compiler to load the specified package and to make its exported identifiers available for use.

Rosie uses a package "search path" (a list of file system directories) to find a package.  We will call it the _libpath_.  Its value should be a colon-separated list, e.g. `"~/rosie-pattern-language/rpl:/usr/local/share/rpl"`.  There are several ways to customize the _libpath_:

* When using the Rosie CLI, the _libpath_ can be set on the command line, and this is the value that will be used.
* When calling the Rosie API via librosie, any value you set for _libpath_ will be used.
* If not set using the above methods, then Rosie looks for the value of the environment variable `$ROSIE_LIBPATH`.
* If none of the above, then Rosie will search the `rpl` directory of the Rosie installation.  (This directory is labeled `ROSIE_LIBDIR` in the output of the `rosie config` command.)
* If you set the _libpath_ yourself, you must include the directory of the Rosie standard library if you want Rosie to search there.

The file extension must be `.rpl` for Rosie to find it when searching the directories on _libpath_.

See the documentation for the Rosie CLI, REPL, or API (librosie) for more details.

Variations of the import declaration:

| `import word`                     | Import the `word` package |
| `import word, num, net`           | Import several packages  |
| `import num as n`                 | Import the `num` package, but call it `n` |
| `import word, num as n, net`      | These forms can be combined |
| `import rosie/rpl_1_0`            | A package reference can specify a subdirectory of a directory on the _libpath_ |
| `import a/b/c`                    | Or a chain of subdirectories |
| `import a/b/c as d`               | Import `a/b/c` as `d` instead of the default name, `c` |
| `import "a a/b/c"`                | If the package's path name contains non-identifier characters, it must be quoted |
| `import "a a/b/cde-f" as c`       | If the package file name contains non-identifier characters, it must be quoted and imported `as` a valid identifier |


### Bindings (also called statements)

Statements can be optionally separated with semi-colons (`;`), such as when combining multiple statements on a single line.

|  RPL statement              | Meaning   |
|  -------------------------- | ----------|
|  `identifier = expression`  | Assign a name to a pattern expression |
|  `grammar ... end`          | Define a proper grammar; assignments and aliases appear in place of `...` |


A statement may have modifiers, which are [explained below](#statement-modifiers).  Briefly, they are:

| Modifier | Meaning                                  | Example                          |
|----------|------------------------------------------|----------------------------------|
| `alias`  | Create an alias for a pattern expression | `alias d = [:digit:]`            |
| `local`  | Declares an name to be local to the block where it is defined | `local number = num.signed_number` |
| `local alias`  | The `local` keword must come first | `local alias h = [:xdigit:]` |


#### Simple bindings

A binding like `d = [:digit:]` binds the name `d` to the expression on the right hand side of the `=` sign.  On the right hand side may be any [pattern expression](#pattern-expressions).

* By binding a name, you can use the name in other expressions (in RPL code, on the command line, at the REPL).
* When Rosie matches this named pattern, it captures the input that matched, and tags that input with the pattern name.

When the output is JSON, you can see that the matching text is labeled with the name of the pattern.  The pattern name appears in the "type" field: 

``` 
$ rosie --rpl 'd = [:digit:]' -o json match d
7
{"type":"d","s":1,"e":2,"data":"7"}
$ rosie --rpl 'ds = [:digit:]+' -o json match ds
123
{"type":"ds","s":1,"e":4,"data":"123"}
``` 

For more information on the JSON output format, see [this section](#output-json) below.  You can read more about [RPL expressions](#expressions) below.

The `alias` [statement modifier](#statement-modifiers) will make the name an _alias_ (substitution) for the expression on the right hand side.  That way, the name will not appear in the output.


#### Grammars

In the scope of a file, RPL bindings cannot be mutually recursive.  (The compiler will complain.)  To enable mutual recursion, place the relevant statements inside a _grammar_.  

Mutually recursive patterns can recognize recursive structures like nested lists (e.g. JSON, XML, s-expressions) or things like "strings that have an equal number of a's and b's".  Grammars are defined by putting a set of assignment/alias statements inside a `grammar`...`end` block, e.g.:

```
same = S $
grammar
  alias S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  alias B = { {"b" S} / {"a" B B} }
end
``` 
Scope:
* A grammar introduces a new scope.  Bindings from the outer scope are visible, but new bindings in the grammar shadow outer bindings for the same name.  This is the usual lexical scope rule.
* The grammar binds one new name in the outer scope, the name of its first rule.  In the example above, only `S` is visible outside the grammar block.

Notes:
* The `local` keyword is not allowed inside a grammar.  To make the grammar's one visible binding local to the file scope, put `local` before the `grammar` keyword.
* Any binding in a grammar may be an `alias`, including the first bound name.

If the example above were saved to the file `g.rpl`, we could load that file into Rosie and match either `same` or `S`.  The only difference is that `same` ensures that the entire input is matched.  The grammar `S` matches strings that contain the same number of a's as b's (and no other characters).  The second example below does match, because the input `baabb` has 3 b's and only 2 a's.

``` 
$ echo "aabb" | rosie -o json -f g.rpl match same
{"type":"same","s":1,"e":5,"data":"aabb"}
$ echo "baabb" | rosie -o json -f g.rpl match same
$ echo "" | rosie -o json -f g.rpl match same
{"type":"same","s":1,"e":1,"data":""}
``` 










#### Binding modifiers

**Alias**

Use `alias` to create a new name that is an alias (substitute) for the expression on the right hand side.  Using an alias is equivalent to inserting the expression itself.  In the statement `alias foo = bar+ baz`, the name `foo` is defined.  When it is used in an expression, it is as if `bar+ baz` were used instead.

**Local**

When writing a package of RPL patterns, there are names you want to be visible when someone imports your package.  The `local` modifier hides a definition so that it is not visible.  The scope of a `local` name is the block in which it is declared.


## Expressions

Here are some key things to remember:

* To match a literal string, enclose it in double quotes.  Outside of quotes you can use identifiers to which you have already assigned patterns, aliases, or grammars.
* Normally, Rosie looks for word boundaries automatically. In other words, Rosie tokenizes automatically. To prevent automatic tokenization, put curly braces `{...}` around your expression.  This is called an _untokenized_ or _raw_ expression.
* Alternatives are indicated by the forward slash `/` operator, not a vertical bar, because Rosie uses _ordered choice_.  See [below](#regex-vs-rpl) for more.

Rosie's pattern expressions are as follows:

|  RPL expression | Meaning                      |
|  -------------- | -------                      |
|  `"abcdef"`     | (String literal) Matches the string `abcdef`.  E.g. `"Hello, world"` matches only the input "Hello, world", with exactly one space after the comma |
|  `pat*`         | Zero or more instances of `pat`                                    |
|  `(pat)*`       | Zero or more instances of `pat` with a token boundary between occurrences |
|  `pat+`         | One or more instances of `pat`; use `(pat)+` if you want token boundaries between occurrences |
|  `pat?`         | Zero or one instances of `pat`
|  `pat{n,m}`         | Bounded repetition of `pat`; use `(pat){n,m}` if you want token boundaries between occurrences |
|  `pat{,m}`         | `n` defaults to 0 |
|  `pat{n,}`         | `m` defaults to infinity |
|  `pat{n}`         | Equivalent to `pat{n,n}`; use `(pat){n}` if you want token boundaries between occurrences |
|  `!pat`         | Not looking at `pat` (predicate: consumes no input)                      |
|  `>pat`         | Looking at `pat` (predicate: consumes no input)                       |
|  `!>pat`         | Equivalent to `!pat` |
|  `<pat`         | Looking backwards at `pat` (predicate: consumes no input)                       |
|  `!<pat`         | Equivalent to `<!pat` |
|  `p / q`        | Ordered choice between `p` and `q`     |
|  `p q`          | Sequence of `p` followed by `q`     |
|  `(...)`         | _Tokenized (or "cooked") sequence_, in which Rosie automatically looks for token boundaries between pattern elements |
|  `{...}`         | _Untokenized (or "raw" sequence)_, which tells Rosie to match the pattern exactly as written, inhibiting tokenization |
|  `[:name:]`      | _Named character class_, from the POSIX standard:  alpha, xdigit, digit, print, cntrl, lower, space, alnum, upper, punct, graph  |
|  `[x-y]`         | _Range character class_, from character x to character y  |
|  `[...]`         | _List character class_, which matches any of the characters listed (in place of `...`) |
|  `[:^name:]`     | Complement of a named character class |
|  `[^x-y]`        | Complement of a range character class |
|  `[^...]`        | Complement of a list character class, matching any character that is NOT one of the ones listed in place of `...` |
|  `[cs1 cs2 ...]` | Union of one or more character sets `cs1`, `cs2`, etc. (E.g. `[[a-f][0-9]]`) |
|  `[^ cs1 cs2 ...]` | Complement of a union of character sets |
|  `fn:pat`     | Apply the macro/function `fn` to `pat`, resulting in a new pattern expression |

**NOTES:**
1. The "quantified expressions" (`pat?`, `pat*`, `pat+`, `pat?`, and `pat{n,m}`) are _greedy_.  They will consume as many repetitions as possible, always.
2. The "quantified expressions" are also _possessive_.  Once they consume their input, they are never re-evaluated.  I.e. they are not subject to backtracking.
3. The two grouping constructs (raw and cooked) are used in the way that parentheses are usually used in programming: to force the order of operations that you want.  So if you want "a or b, followed by c", write `(a / b) c` or `{ {a / b} c }`.

Inside of quotation marks, the only special character is `\` (backslash), which is the escape character.  Inside of a character set (in square brackets `[]`), the special characters are `-` (which is only special when it is the middle of three characters, specifying a character range) and square brackets `[` `]` and caret `^`.  These characters must be escaped to use them literally within a character set, e.g. a class containing a single right bracket and a caret is `[\]\^]`.

## Matches/Captures

Rosie's match output is structured in a way that mirrors the pattern that was matched.  You can see the structure if you look at the JSON output from Rosie.  (On a terminal, the default is for Rosie to print the matched pieces of input in color.  Use the `-o json` option to get JSON instead.)  There will be one JSON structure for each line in the input, and each structure is called a *match*.  A match contains the name of the pattern that generated it, the starting position in the input of the matched text, the matched text itself, and any *sub-matches*.  Sub-matches have the same structure as matches; i.e. matches have a tree structure.

A match output by Rosie is kind of like a capture in regex.  Except way cooler, because a match has the recursive structure of a parse tree. (In the language of compilers, Rosie's output is a *parse tree*.)

There are a few really important things you need to know about Rosie's matches:

1. Sub-matches are captured only for the identifiers in a pattern.  And only when those identifiers are *not* aliases.  Sub-matches are indexed by the identifier name that generated them.
2. Literal strings in patterns are not returned as sub-matches.  This is a special case of the previous rule.  
3. If you *want* a literal string or some other primitive expression (e.g. `[:digit:]{3}`) to appear as a sub-match, assign it a name.  Here's an example where a literal string is assigned the name `down_message`.  The pattern `alert` contains the identifier `down_message`, and so there will be a sub-match of `alert` called `down_message`:

``` 
down_message = "The system will go down in"
delay = num.int "seconds"
alert = down_message delay
``` 

Remember, aliases are substitutions, like macros in some programming languages.  They do not create a new named capture like ordinary (non-alias) named patterns do.  (Rationale:  Aliases let you give names to patterns, so that you can refer to them by name, without declaring that you want this name to appear as a separate capture/match in Rosie's output.)  The choice between assigning a name to a pattern and creating an alias for the same pattern gives you some control over what appears in the output.


## If you know regex already, this is RPL <a name="regex-vs-rpl"></a> 

### Anchors

* A Rosie pattern begins matching at the start of the input line, so the `^` (caret) anchor is rarely needed in RPL.  To skip over characters, you have to be explicit in your pattern about what to skip.  See [below](#find_patterns) for more.
* A Rosie pattern will match successfully even if the entire input is not consumed.  To force a match of the complete input line, use the `$` anchor at the end of your pattern to force a match to the end of the input.
* Rosie automatically tokenizes the input in a way similar to the "word boundary" (`\b`) anchor in regex.  There is a Rosie identifier `~` that refers to the boundary definition used by Rosie.  You can use it explictly as needed, e.g. `~date.any~` matches the pattern `date.any` (from [rpl/date.rpl](../rpl/date.rpl)) only when there is a token boundary before and after it.

### Ordered choice

The "alternation" operator in a Rosie pattern is an _ordered choice_.  Instead of using the pipe symbol `|`, which represents equal alternatives in regex, Rosie uses a forward slash `/` to denote an ordered choice between two alternatives.  The pattern `(a / b) c` is read as "a or b, followed by c" and is processed this way:

1. If `a` matches the start of the input, then the choice is satisfied, so go on to match `c`
2. Else if `b` matches the start of the input, then the choice is satisfied, so go on to match `c`
3. Otherwise, the entire pattern fails because `(a / b)` could not be matched

Once a choice is made, Rosie will never backtrack and try another alternative.  Let's make that clear with a different example.  The RPL pattern `a / (a b)` will not match the input "a b" because the pattern will never look for b.  This pattern is processed as follows:

1. If `a` matches the start of the input, then the ordered choice is satisfied, and the overall pattern succeeds
2. Else try the next alternative, `(a b)`.  The sequence `(a b)` will always fail because we arrived here due to the fact that we could not match `a`.  If we cannot match `a`, then we cannot match the sequence `(a b)`.

The order of the alternatives matters in Rosie.  The pattern `(a b) / a` will match input "a b", because this pattern looks for the sequence "a b" first.

When writing RPL patterns, then, we must pay attention to the order of choices in an alternation expression.  Ordered choices are part of Parse Expression Grammars, and while they place constraints on pattern writers, they help guarantee linear-time execution.

### "Tokenized or "cooked" mode

Normally, Rosie tokenizes the input, using whitespace and punctuation to separate the tokens.  Most of the time, this just _does the right thing_, such as when you're trying to match a noun followed by a verb, or a timestamp followed by an ip address.  As a trivial example, consider:

```
a = "a"
b = "b"
``` 

The expression `a b` will match the input "a b" (and "a \t \n  b", etc.) and produce this output:

``` 
$ rosie repl
Rosie> a="a"; b="b"
Rosie> .match a b "a b"
{"data": "a b", 
 "e": 4, 
 "s": 1, 
 "subs": 
   [{"data": "a", 
     "e": 2, 
     "s": 1, 
     "type": "a"}, 
    {"data": "b", 
     "e": 4, 
     "s": 3, 
     "type": "b"}], 
 "type": "*"}
Rosie> .match a b "a     b"
{"data": "a     b", 
 "e": 8, 
 "s": 1, 
 "subs": 
   [{"data": "a", 
     "e": 2, 
     "s": 1, 
     "type": "a"}, 
    {"data": "b", 
     "e": 8, 
     "s": 7, 
     "type": "b"}], 
 "type": "*"}
Rosie> 
``` 

But `a b` will **not** match the input "ab".  Neither will `(a b)`.  An expression like `a b` or `(a b)` should be read as "a, then a token boundary, then b".   

If you wanted to match "ab", then you do not want to match `a` and `b` as separate tokens, but instead as raw characters.  You need the untokenized (or "raw") sequence `{a b}` to match "ab", which will produce this output:

``` 
Rosie> .match {a b} "a b"
No match  [Turn debug on to show the trace output]
Rosie> .match {a b} "ab"
{"data": "ab", 
 "e": 3, 
 "s": 1, 
 "subs": 
   [{"data": "a", 
     "e": 2, 
     "s": 1, 
     "type": "a"}, 
    {"data": "b", 
     "e": 3, 
     "s": 2, 
     "type": "b"}], 
 "type": "*"}
Rosie> 
``` 

**NOTE:** The name of the matched pattern is "*" in the examples above because the pattern `a b` was entered on the command line.  I.e. it does not have a name.

When you quantify a simple expression using `*`, `+`, `?`, or `{n,m}`, Rosie will treat the expression as if it were raw.  So `"foo"+` will match "foofoofoo" and not "foo foo foo".  You can force a tokenized match using a cooked group: `("foo")+` will match "foo foo foo".  Most of the time, quantified expressions are used in character-oriented syntactic patterns, so the default usually _does the right thing_.

But for that occasion when you want to match exactly two ip addresses separated by whitespace, be sure to write `(net.ip){2}`.  The right way to read this expression is to remember that the repetition operator (`{2}` in this example) causes Rosie to look for a sequence.  Since the pattern `(net.ip)` is inside parentheses, the sequence `(net.ip){2}` is equivalent to `(net.ip net.ip)`, which in turn expands into `net.ip ~ net.ip`.

### Greedy quantifiers

There is one way in which regex are particularly concise, which is when you want to match a pattern that _ends_ in a recognizable way.  For example, words from `/usr/share/dict/words` that end in "ear" can be found with the expression `.*ear$` as an argument to `grep`:

```sh
$ grep .*ear$ /usr/share/dict/words | head -5
abear
afear
anear
appear
arear
```

<a name="find_patterns"></a>
In RPL patterns, quantifiers like `*` are greedy and will eat up as much input as possible.  The pattern `.*ear` will never match anything in RPL, because the `.*` will consume all the input, leaving nothing to match "ear".  You have to tell Rosie when to _stop_ consuming input.  (This is one reason that RPL grammars are efficient.)

To write an RPL pattern that consumes characters (`.` consumes 1 character) until the string "ear" is found, and then match "ear", you could write:

```
{ !"ear" . }* "ear"
```

The part of the pattern inside the braces reads as "while not looking at _ear_, match any character".  The star `*` says to repeat this zero or more times.

Because this is a frequent idiom, Rosie provides a macro called `find1` that searches for a pattern, and then consumes it.  For example, let's look for words that end in "ear":

``` 
$ rosie match -o line '{ {!"ear" .}* "ear" $}' /usr/share/dict/words | head -5
abear
afear
anear
appear
arear
$ rosie match -o line '{ find1:"ear" $}' /usr/share/dict/words | head -5
abear
afear
anear
appear
arear
$ 
```

Another common use of Unix grep is to find all occurrences of a pattern.  (The `grep -o` option will print all of the matches.)  The Rosie macro `find` provides a shorthand for grep's behavior.

``` 
$ cat test/resolv.conf
#
# This is an example file, hand-generated for testing rosie.
# Last update: Wed Jun 28 16:58:22 EDT 2017
# 
domain abc.aus.example.com
search ibm.com mylocaldomain.myisp.net example.com
nameserver 192.9.201.1
nameserver 192.9.201.2
nameserver fde9:4789:96dd:03bd::1

$ grep '.com' test/resolv.conf
domain abc.aus.example.com
search ibm.com mylocaldomain.myisp.net example.com
$ grep -o '.com' test/resolv.conf
.com
.com
.com
$ rosie match 'find:".com"' test/resolv.conf
.com
.com .com
``` 


### Matching the entire input line with nothing left over

Rosie is happy to match the first part of a line and ignore the rest.  Often, this is a good thing, but not always.  If you want to be sure that the entire input matches your pattern with no input left over, use the "end of input" pattern, `$`.

### Matching starts at the first character of the line

The Rosie Pattern Engine begins matching with the first character of the input.  This is why the `find1` macro is so useful.  Also, remember that the token boundary `~` can be used to skip over whitespace, e.g.

``` 
$ rosie repl
Rosie> import num
Rosie> .debug off
Debug is off
Rosie> .match num.int "    321"
No match  [Turn debug on to show the trace output]
Rosie> .match ~ num.int "    321"
{"data": "    321", 
 "e": 8, 
 "s": 1, 
 "subs": 
   [{"data": "321", 
     "e": 8, 
     "s": 5, 
     "type": "num.int"}], 
 "type": "*"}
Rosie> 
```

