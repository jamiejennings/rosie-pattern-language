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

There is also an [overview of RPL for people who know regex](i-know-regex.md).

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

| Example                         | Explanation |
| ------------------------------- | ----------- |
| `import word`                   | Import the `word` package |
| `import word, num, net`         | Import several packages  |
| `import num as n`               | Import the `num` package, but call it `n` |
| `import word, num as n, net`    | These forms can be combined |
| `import rosie/rpl_1_0`          | A package reference can specify a subdirectory of a directory on the _libpath_ |
| `import a/b/c`                  | Or a chain of subdirectories |
| `import a/b/c as d`             | Import `a/b/c` as `d` instead of the default name, `c` |
| `import "a a/b/c"`              | If the package's path name contains non-identifier characters, it must be quoted |
| `import "a a/b/cde-f" as c`     | If the package file name contains non-identifier characters, it must be quoted and imported `as` a valid identifier |


### Bindings (statements)

Statements can be optionally separated with semi-colons (`;`), such as when combining multiple statements on a single line.

|  RPL statement              | Meaning   |
|  -------------------------- | ----------|
|  `identifier = expression`  | Assign a name to a pattern expression |
|  `grammar ... end`          | Define a proper grammar; assignments and aliases appear in place of `...` |


A statement may have modifiers, which are [explained below](#modifiers).  Briefly, they are:

| Modifier | Meaning                                  | Example                          |
|----------|------------------------------------------|----------------------------------|
| `alias`  | Create an alias for a pattern expression | `alias d = [:digit:]`            |
| `local`  | Declares a name to be local to the block where it is defined | `local number = num.signed_number` |
| `local alias`  | The `local` keyword must come first | `local alias h = [:xdigit:]` |


#### Simple bindings

A binding like `d = [:digit:]` binds the name `d` to the expression on the right hand side of the `=` sign.  On the right hand side may be any [pattern expression](#expressions).

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

For more information on the JSON output format, see [the section on Matches and Captures](#matches-captures).  You can read more about [RPL expressions](#expressions) below.

The `alias` [statement modifier](#modifiers) will make the name an _alias_ (substitution) for the expression on the right hand side.  That way, the name will not appear in the output.


#### Grammars

In the scope of a file, RPL bindings cannot be mutually recursive.  (The
compiler will complain.)  To bind a mutually recursive set of patterns, or a single
recursive pattern, place the statements inside a _grammar_.  

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

#### Modifiers

**Alias**

Use `alias` to bind a name that is an alias (substitute) for the expression on the right hand side.  Using an alias is equivalent to inserting the expression itself.  In the statement `alias foo = bar+ baz`, the name `foo` is bound.  When `foo` is used in an expression, it is as if `bar+ baz` were used instead.

**Local**

When writing a package of RPL patterns, there are names you want to be visible when someone imports your package.  The `local` modifier hides a definition so that it is not visible.  The scope of a `local` name is the block in which it is declared.  In RPL 1.1, the only place `local` has any meaning (and therefore, the only place it can be used) is in the file scope.


## Expressions

Most of RPL consists of pattern expressions.  Simple expressions compose into
larger expressions.  When a concept in RPL is aligned with regex, it generally
has the same syntax.

Here are some key things to remember:

* To match a literal string, enclose it in double quotes.  Outside of quotes you can use identifiers (names) which are bound to other patterns, aliases, etc.
* Several kinds of character escape sequences can be used in literals and character sets.
* There are 3 grouping mechanisms:
  * `{...}` Curly braces enclose an _untokenized_ expression.
  * `(...)` Parentheses enclose a _tokenized_ expression, in which there is an implicit token boundary between each element of a sequence.
  * `[...]` Square brackets enclose a _bracket_ expression, which is usually used to construct character sets, but can be used more generally as a _disjunction_ of the patterns it contains.
  
### Table of RPL expression types

| Name    | Example                   | Meaning |
| ------- | -------                   | ------- |
| Literal            | `"abcdef"`     | Matches the string `abcdef`.  E.g. `"Hello, world"` matches only the input "Hello, world", with exactly one space after the comma |
| Star (untokenized) | `pat*`         | Zero or more instances of `pat` |
| Star (tokenized)  | `(pat)*`       | Zero or more instances of `pat` with a token boundary between occurrences |
| Plus (untokenized) | `pat+`         | One or more instances of `pat` |
| Plus (tokenized)   | `(pat)+`       | One or more instances of `pat` with a token boundary between occurrences |
| Question           | `pat?`         | Zero or one instance of `pat` |
| Bounded repetition (tokenized)   | `(pat){n,m}`   | At least n instances, and matching at most m instances of `pat`, with a token boundary between occurrences |
| Bounded repetition (untokenized) | `pat{n,m}`     | At least n instances, and matching at most m instances of `pat` |
|                    | `pat{,m}`         | `n` defaults to 0. Analogously, `(pat){,m}` for a tokenized repetition. |
|                    | `pat{n,}`         | `m` defaults to infinity. Analogously, `(pat){n,}` for a tokenized repetition. |
|                    |  `pat{n}`         | Equivalent to `pat{n,n}`.  Analogously, `(pat){n}` for a tokenized repetition. |
| Look ahead         | `>pat`         | Looking at `pat` (predicate: consumes no input)                       |
| Negative look ahead | `!pat`         | Not looking at `pat` (predicate: consumes no input)                      |
|                    | `!>pat`         | Equivalent to `!pat` |
| Look behind        | `<pat`         | Looking backwards at `pat` (predicate: consumes no input)                       |
| Negative look behind | `!<pat`         | Not looking backwards at `pat`.  Equivalent to `<!pat` |
| Ordered choice/alternative | `p / q`        | Ordered choice between `p` and `q` |
| Sequence           | `p q`          | Sequence of `p` followed by `q`     |
| Conjunction        | `p & q`        | Equivalent to `{>p q}` (looking at `p`, matching `q`) |
| Tokenized sequence | `(...)`         | _Tokenized sequence_, in which Rosie automatically looks for token boundaries between pattern elements |
| Untokenized sequence | `{...}`       | _Untokenized (or "raw") sequence)_ |
|  Named character set | `[:name:]`    | From the POSIX standard:  alpha, xdigit, digit, print, cntrl, lower, space, alnum, upper, punct, graph  |
|                      | `[:^name:]`| Complement. Matches a single character not in the named set. |
| Character range | `[x-y]`         | Matches a single character from the Unicode codepoint of x to the Unicode codepoint of y, inclusive |
|                 | `[^x-y]`        | Complement. Matches a single character not in the given range. |
| Character list  | `[...]`         | Matches any of the characters listed (in place of `...`) |
|                 | `[^...]`        | Complement. Matches a single character not listed in `...`. |
| Union (Disjunction) | `[cs1 cs2 ...]` | Union of one or more character sets `cs1`, `cs2`, etc. (E.g. `[[a-f][0-9]]`) |
|                     | `[^ cs1 cs2 ...]` | Complement. Matches a single character not in the given union. |
| Application         | `fn:pat`     | Apply the macro/function `fn` to `pat`.  See [Macros and Functions](#macros) below. |

### Pre-defined patterns

| Symbol | Name     | Meaning |
| ------ | -------- | ------- | 
| `.`    | dot      | Matches a single Unicode character encoded in UTF-8, or (failing that) a single byte |
| `~`    | boundary | Matches a word boundary, similar to "\\b" in regex.  See below for details. |
| `$`    | dollar   | Matches at the end of the input.  Consumes no input. |
| `^`    | caret    | Matches at the start of the input.  Consumes no input. |
| `ci`   | _macro_  | `ci:pat` matches a case-insensitive version of `pat` |
| `find` | _macro_  | `find:pat` consumes input until `pat` matches; `pat` is a sub-match |
| `findall` | _macro_ | `findall:pat` consumes all input, returning all occurrences of `pat` as sub-matches |
| `keepto`  | _macro_ | `keepto:pat` consumes all input until `pat` matches, returns the data prior to `pat` as a sub-match, in addition to `pat` as a sub-match |
| `message` | _function_      | `message:Str` consumes no input; it inserts a node into the output with type `message` and data `Str`. (See note on strings, below.) |
|           |                 | `message:(Str, Type)` consumes no input; it inserts a node into the output with type `Type` and data `Str`. (See note on strings, below.) |
| `error`   | _function_      |	`error:Str` consumes no input; it inserts a node into the output with type `error` and data `Str`, and then aborts the matching process. (See note on strings, below.) |
|           |                 |	`error:(Str, Type)` consumes no input; it inserts a node into the output with type `Type` and data `Str`, and then **aborts** the matching process. (See note on strings, below.) |


### The boundary pattern

The boundary symbol, `~`, is an ordered choice of:

| Constituent                  | Meaning |
| ---------------------------- | ------- |
| `[:space:]+`                 | consume all (ASCII) whitespace |
| `{ >word_char !<word_char }` | looking at a word character, and back at non-word character |
| `>[:punct:] / <[:punct:]`    | looking at punctuation, or back at punctuation |
| `{ <[:space:] ![:space:] }`  | looking back at whitespace, but not ahead at whitespace |
| `$`                          | looking at end of input |
| `^`                          | looking back at start of input |
 
**Important note:** `word_char` is the ASCII-only pattern `[[A-Z][a-z][0-9]]`.

While the default boundary pattern is defined as shown, you may redefine it
within an RPL file.  The new definition will be used throughout the RPL file
that contains it.

One reason to customize the boundary is to make it simpler, so that it matches
faster.  Another reason may be to replace the ASCII definitions of whitespace
and word constituents with more rich definitions, e.g. using Unicode predicates.

### A note on strings in RPL

The functions `message` and `error` take string arguments.  Strings in RPL are
marked with a hash symbol (`#`) to distinguish them from pattern literals, and
come in two forms:

* `#tag` is the string "tag".  This short syntax is convenient for single words that have the same syntax as RPL identifiers.
* `#"long string"` is the long form syntax.  The "long string" part has the same syntax as RPL pattern literals.  It can contain white space and use escape sequences to denote non-ASCII characters.

### Escape sequences

With any language, there are two things you need to know about escape
sequences.  Which escape sequences _can_ I use, and which _must_ I use?

#### What can I escape in RPL?

In RPL, you can use the any of the following escape sequences when writing
string or character literals:

| RPL syntax | Name | Meaning |
| -----------| -----| --------|
| `\xHH`       | Hex escape | A single byte; where HH is in 00-FF |
| `\uHHHH`     | Unicode escape | The UTF-8 encoding of a Unicode codepoint; HHHH in 0000-FFFF |
| `\UHHHHHHHH` | Long Unicode escape | The UTF-8 encoding of a Unicode codepoint; HHHHHHHH in 00000000-10FFFFFF |
| `\a`, `\b`, `\t`, `\n`, `\f`, `\r` | Subset of the [ANSI C escape sequences](https://en.wikipedia.org/wiki/Escape_sequences_in_C) | Codepoints 07 (bell), 08 (backspace), 09 (tab), 0A (newline), 0C (formfeed), 0D (return) |

Rationale: 
1. The RPL hex escape is a variant of the same in ANSI C, except that the RPL
syntax requires exactly two hex digits.  We expect the hex escape to be used
for parsing binary data and for specifying non-characters, such as single bytes
in the range 80-FF.
2. Both Unicode escapes, `\u` and `\U`, are also part of ANSI C, and have been
adopted by other languages as well.  The long form is expected to be needed
rarely, because of the paucity of defined codepoints above FFFF.
3. Several of the ANSI C escape sequences are used much too often to ignore,
particularly tab, newline, and carriage return.  We dropped the vertical tab,
which has fallen into disuse, but kept the bell, backspace, and formfeed
sequences.

#### What escape sequences are mandatory in RPL?

There are only a handful of cases in which an escape sequence _must be used_ in
order to refer to the character itself.  The rule is to _always escape the magic
characters_.  Luckily, there are few magic characters, and whether they are
magic depends only on their context, not on their position.

| Char | Context | Explanation |
| ---- | ------- | ----------- |
| `\`  | Everywhere | The escape character, backslash, is always magic; to get a literal backslash, write `\\` |
| `"`  | Strings, Literals | In a string, the double quote is magic (signaling the end of the string); to put a double quote in a string, write `\"` |
| `[ ] ^ -` | Character lists | In a character list or range, the magic characters are `[`, `]`, `^`, and `-`; in those contexts, write `\[`, `\]`, `\^`, and `\-` |

Rationale:
1. To reduce cognitive load, we try to reduce the number of rules.  Here, there
is essentially one rule, with variants applying to strings and character sets.
2. Importantly, there are no exceptions to the rule.  The position of a
character in a character set or string is irrelevant to the rule.


### Repetitions are greedy and possessive

Repetitions are expressions like `pat*`, `pat+`, `pat{n,m}`, and all of their
variations.  In RPL, they are _greedy_: They will consume as many repetitions as
possible, always.

Repetitions are also _possessive_: Once they match, they are never re-evaluated.
I.e. later match failures can not cause backtracking (in which an earlier
repetition would be revisited).

### Precedence and association rules

The sequence operator in Rosie is simply adjacency: there is only whitespace between two or more expressions in a sequence.  When adjacency is viewed as an operator, it has equal precedence in RPL with the ordered choice operator.

RPL expressions are right associative.  Such expressions are easy to read if you
think of the phrase "and/or the rest".  A sequence like `x ...` can be read as
"a sequence of `x` and then the rest".  A choice like `a / ...` can be read as
"either `a` or the rest".  So, `a / x y` reads as "`a` or the rest", and "the
rest" is "the sequence of `x` then `y`".

For example:

* `a b c / d` is equivalent to `a (b (c / d))`
* `a b c / d / e f` is equivalent to `a (b (c / (d / (e f))))`
* `a b c / d e / f g` is equivalent to `a (b (c / (d (e / (f g)))))`

The tokenized and untokenized grouping constructs (`()` and `{}`, respectively)
are used in the way that parentheses are usually used in programming: to force
a particular order of operations.  E.g. if you want "`a` or `b`, followed by `c`", write:

* `(a / b) c` for a tokenized sequence that is equivalent to `{{a / b} ~ c}`; or
* `{ {a / b} c }` for an untokenized sequence with no boundary patterns.


## Matches/Captures

Pattern matching technologies like regex are, in their bare form, predicates.
They return a boolean, indicating whether the pattern matched the input.  Of
course, there is a lot of utility to be gained from also returning the part of
the input that matched.  This is why regex introduced the concept of a _capture_.

In regex, you tell the matching engine what to capture by inserting parentheses
into your expression.  In RPL, we took a different approach.

Every named pattern in RPL is (conceptually, at least) captured.  In order to
reduce the size of the match data returned by an RPL matcher (like Rosie), an
implementation may provide directives that indicate which captures may be
omitted from the output.

It is important to understand that the concept of captures is orthogonal to the
semantics of matching.  A goal of RPL is to be able to define patterns based
solely on their ability to match the desired input, and _subsequently_ decide
which captured elements should be present in the output.

Indeed, different users should be able to use the same pattern, with each user
deciding at match time which captured elements they want included in the output.

To obtain this separation of capture semantics from match semantics, we first
imagine that there exists a _complete_ set of captures from which we could, in
theory, select any subset.  In RPL, the complete set of captures includes a
capture for every pattern that has a name.

The rationale for this decision is that the pattern name has the role of a type,
and therefore can be used to tag a capture in a meaningful way.  Another way to
think about it is: if something is important enough that you want to see it
captured in the output, then it deserves a name.

<blockquote>
<small>
Note: <br>
When a Rosie matching engine is given an anonymous
expression to match against some input, the engine assigns the anonymous
expression the name `*`, which was chosen in part because it is not a valid RPL
identifier, so it cannot be confused with an actual pattern.  This is an
implementation detail, and not part of the RPL language definition.
</small>
</blockquote>

An RPL matching engine (like Rosie) takes an RPL pattern and an input, and
returns some output.  The main piece of output is called (imaginatively) a
_match_.  A second essential piece of output is the amount of unmatched ("left
over") input data.  Recall that RPL is based on Parsing Expression Grammars, and
the convention there is to match as much of the input as possible, and then stop
if the end of the pattern is reached.

(You can always add `$` to the end of a pattern to ensure that a successful
match is one that consumes the entire input.)

Let's assume for now that a _match_ contains a complete set of captures.  There
is a "natural" structure to such a match, and it is a tree.  A node in the tree
is a _match_ record:

<blockquote>
<em>match</em> := { type, s, e, data, subs}
<br>
where
<br>
<blockquote>
<em>type</em> is an RPL pattern name; <br>
<em>s</em> is the start position of the match in the input (1-based); <br>
<em>e</em> is the end position of the match in the input (1-based); <br>
<em>data</em> is the actual text that matched, i.e. the "capture"; <br>
<em>subs</em> is a list of sub-matches (children in the tree);
</blockquote>
</blockquote>


Example:

```shell 
$ rosie -o jsonpp match '"nameserver" net.ipv6' test/resolv.conf
{"data": "nameserver fde9:4789:96dd:03bd::1", 
 "type": "*", 
 "e": 34, 
 "subs": 
   [{"data": "fde9:4789:96dd:03bd::1", 
     "type": "net.ipv6", 
     "e": 34, 
     "s": 12}], 
 "s": 1}
$ 
``` 

In the example above, you can observe the following:
1. an anonymous expression was entered on the command line (`"nameserver" net.ipv6`);
2. Rosie produced one _match_ (encoded as a json object), so we know that one line of the file `test/resolv.conf` matched the pattern;
3. the type of the match is `*` because the expression to match was anonymous;
4. the data field contains the capture (`nameserver fde9:4789:96dd:03bd::1`);
5. the match started at the first character of the input (`"s": 1`);
6. the match extended through character 34 (`"e": 34`);
7. there is one sub-match in the `subs` list, corresponding to the one named term in the anonymous expression, `net.ipv6`.


Note that Rosie accepts the `-o jsonpp` option for JSON pretty-printed output.
The `-o json` option generates more compact JSON (and is much faster).  JSON
output is a Rosie feature; the RPL language specification says nothing about how
a _match_ is represented.


## Macros and functions <a name="macros"></a> 

Rosie has a very small set of macros and functions that will expand over time.
Currently, as of Rosie v1.0.0, there is no way for users to define their own
macros or functions.  This is an area that is ready for future development, and
we welcome contributions of macros and functions themselves, as well as
proposals for how to allow users to dynamically add their own macros and functions.

### Semantics

Macros and functions are part of the RPL language syntax (see next section),
though we have only a few things to say at this point in time about their
semantics.

* Functions and macros live in the same namespace as other symbols, such as
  pattern names and package names.  (If RPL were a Lisp, it would be a
  [Lisp-1](https://en.wikipedia.org/wiki/Common_Lisp#The_function_namespace).) 
* A macro transforms its argument(s), producing a pattern.  The macro expansion
  process is left unspecified for now, except to say that it takes place during
  a syntax expansion phase prior to compilation.
* The implementation of a macro receives its pattern arguments unevaluated.
  String arguments are interpolated (to process escape sequences) and numeric
  arguments are evaluated prior to macro expansion.  But the point of the macro
  is that it receives pattern arguments as syntax objects, which it can then
  transform. 
* A function is essentially magic.  Its arguments are evaluated during
  compilation, but the function call becomes part of the pattern, to be executed
  by the matching engine during execution (i.e. when matching a pattern against
  input data).  To add a function to Rosie, the matching engine must be extended
  to include the code for the new function.

### Syntax

Macro and functions share a common syntax of in RPL, which we call (naturally) _application_:

```
fn:arg                   fn applied to a single argument
fn:(arg1, ..., argN)     fn applied to N args, N >= 0, in a tokenized context
fn:{arg1, ..., argN}     fn applied to N args, N >= 0, in an untokenized context
 
where arg is a pattern expression, a string or tag (with a # prefix), or an integer.
```

The tokenized and untokenized RPL grouping constructs are both allowed as
delimeters around an argument list.  They are equivalent except when one or more
argument is a pattern expression containing a bare sequence.  (A bare sequence
is one, like `p q r`, which is not enclosed by parentheses or braces.)  Such
sequences are evaluated as tokenized when the argument list is enclosed with
parentheses: 

  ```fn:(p q, 34, s t u)``` is equivalent to ```fn:{ (p q), 34, (s t u) }```

Note that when a sequence is the only argument, it cannot be a bare sequence,
due to the RPL syntax:

``` 
fn:(p q)     fn applied to one argument: (p q)
fn:{p q}     fn applied to one argument: {p q}
fn:p q       sequence of fn applied to p, followed by q
``` 

### Examples

In the first example, we want to search for "IBM" in a case-insensitive way.
Because we are searching, as opposed to matching starting at the beginning of
the input, we use the Rosie command `grep`.

The Rosie `grep` command will output, by default, each line that contains a
match, like the Unix grep utility does.  Here, we want Rosie to highlight the
part of the line that matched, so we set the output format to `color`.

The first command searches for `"IBM"`, which does not match.  The second command
searches for `ci:"IBM"`, which succeeds, matching "ibm", which is highlighted in
bold face.  The third command is equivalent to the second, because Rosie's
`grep` simply applies the `findall` macro to the given pattern.

<pre>
$ rosie grep -o color '"IBM"' test/resolv.conf
$ rosie grep -o color 'ci:"IBM"' test/resolv.conf
search <b>ibm</b>.com mylocaldomain.myisp.net example.com
$ rosie match 'findall:ci:"IBM"' test/resolv.conf 
search <b>ibm</b>.com mylocaldomain.myisp.net example.com
$ 
</pre>

The next example shows the difference between `findall` and `find`.  While
`findall` works like Unix grep, searching for every occurrence of the pattern,
`find` stops searching after the first match.

Because the default output format for Rosie's `match` command is `color`, we
should see the matching parts of the input highlighted in bold face.

<pre>
$ rosie match 'find:".com"' test/resolv.conf
domain abc.aus.example<b>.com</b>
search ibm<b>.com</b> mylocaldomain.myisp.net example.com
$ rosie match 'findall:".com"' test/resolv.conf
domain abc.aus.example<b>.com</b>
search ibm<b>.com</b> mylocaldomain.myisp.net example<b>.com</b>
$ 
</pre>

In the next example, we apply the `findall` macro to a more complex expression.
The expression `net.any` (from the Rosie Standard Library) matches network
addresses of various kinds, and `<".com"` matches when looking backwards at
".com".  Putting these together in sequence gives a pattern that matches a
network address ending in ".com".

Because the default highlighting for network addresses is a red font, we can see
which parts of the output were matched by `findall` by looking for the red text:

(Github markdown does not allow color text, so we have a screen capture here...)

[[images/net-dot-com-red-text.png]]

## End
