![./CHANGELOG](https://img.shields.io/badge/version-1.0.0--alpha-ff79b4.svg)
[![Build Status](https://travis-ci.org/jamiejennings/rosie-pattern-language.svg?branch=master)](https://travis-ci.org/jamiejennings/rosie-pattern-language)

# Rosie Pattern Language

Rosie is an alternative to modern Regular Expressions (regex) that is designed
to scale to big data, many developers, and large collections of patterns.  Rosie
Pattern Language:

* Looks like a programming language, and plays well with development tools
* Comes with a library of dozens of useful patterns (timestamps, network addresses, and more)
* Has development tools: tracing, REPL, color-coded match output
* Produces JSON output (and other formats)

<blockquote>
<table>
<tr>
    <td><img src="doc/images/p1.gif" width="600"></td>
</tr>
</table>
</blockquote>

## Contents

- [Features](#features)
- [Building](#building)
- [Using Rosie's CLI](#using-the-cli)
- [Using Rosie's REPL](#using-the-repl)
- [Using Rosie API](#using-the-api)

- [Project Roadmap](#project-roadmap)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)

See also:
- The new [Rosie Pattern Language blog](http://tiny.cc/rosie), which has news
and examples, and will eventually contain posts on the usage and design of
Rosie.
- Twitter: [@jamietheriveter](https://twitter.com/jamietheriveter)
- [Other sources](#other-sources)


## Features

- Small: the Rosie compiler/runtime/libraries take up less than 600KB of disk
- Good performance: **what to say, specifically?**
- Extensible pattern library
- Packages of patterns are easy to share
- Rosie is fluent in UTF-8, ASCII, and the binary language of moisture
'vaporators (arbitrary byte-encoded data)

## Building

Platforms: OS X, Linux, and probably that Ubuntu-on-Windows thing

1. `make`
2. `make install`  (optional)

## Using the CLI

- Examples
- Link to man page

## Using the REPL

- Examples
- Link to full reference?

## Using the API

...Rosie in your own programs...

- Language coverage
- Building librosie
- Link to full api documentation

## API

- Describe librosie
- Link to full api doc

## Project roadmap

### Releases
- [x] Change to semantic versioning
- [x] v1.0.0-alpha release
- [ ] v1.0.0-beta release
- [ ] v1.0.0 release

### Installation
- [ ] Brew installer for OS X
- [ ] RPM and debian packages

### API and language support
- [ ] API (C)
- [ ] Python module
- [ ] C, Go modules
- [ ] Ruby, node.js modules

### Packages
- [ ] Dependency tool to identify dependencies of a set of packages, and to make
it easy to upload/download those dependencies.
- [ ] Source code parsing patterns (based on work done at NCSU, Raleigh, NC USA)

### Features
- [ ] Unicode character classes
- [ ] Support JSON output for trace, config, list, and other commands
- [ ] Customize color assignments
- [ ] Customize initial environment
- [ ] Generate patterns automatically from locale data
- [ ] Toolkit for user-developed macros
- [ ] Toolkit for user-developed output encoders
- [ ] Compiler optimizations
- [ ] Additions to standard library


<hr>

## Contributing

### Write new patterns!

We are happy to add more patterns to the initial library we've started in the
[rpl directory](rpl), whether they build on what we have or are entirely new.

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

### Wanted: new tools

Because RPL is designed like a programming language (and it has an accessible
parser, [rpl_1_1.rpl](rpl/rosie/rpl_1_1.rpl), new tools are relatively easy to
write.  Here are some ideas:

- [ ] **Package doc:** Given a package name, display the exported pattern names
      and, for each, a summary of the strings accepted and rejected.

- [ ] **Improved trace:** The current trace output could be improved,
  particularly to make it more compact.  A trace is represented internally as a
  table which could easily be rendered as JSON.  And since this data structure
  represents a complete trace, it is the right input to a new algorithm that
  produces a compact summary.  Or an animated output.

- [ ] **Linter:** Users of most programming languages are aided by a linting
	tool, in part because of correct expressions that are not, in fact, what the
	programmer wanted.  For example, the character set `[_-.]` is a range in
	RPL, but it is an empty range.  Probably the author meant to write a set of
	3 characters, like `[._-]`.

- [ ] **Notebook:** A Rosie kernel for a notebook would be useful to many
  people.  So would adding Rosie capabilities to a general notebook environment
  (e.g. [Jupyter](http://jupyter.org)).
  
- [ ] **Pattern generators:** A number of techniques hold promise for
automatically generating RPL patterns, for example:
  * Convert a format string to pattern, e.g. a `printf` format string, or the
    posix locale structure's fields that specify how to format numbers,
    dates/times, and monetary amounts.
  * Infer the format of each field in a CSV (or JSON, HTML, XML) file using
  analytics techniques such as statistics and machine learning.
  * Convert a regular expression to an RPL pattern.


## Acknowledgements

In addition to the people listed in the CONTRIBUTORS file, we wish to thank:

-  Roberto Ierusalimschy, Waldemar Celes, and Luiz Henrique de Figueiredo,
    the creators of [the Lua language](http://www.lua.org) (MIT License);

-  the Lua community (at large);

-  Mark Pulford, the author of
   [lua-cjson](http://www.kyne.com.au/%7Emark/software/lua-cjson.php) (MIT
   License); 

-  Brian Nash, the author of
   [lua-readline](https://github.com/bcnjr5/lua-readline) (MIT License); 

-  Peter Melnichenko, the author of
   [argparse](https://github.com/mpeterv/argparse) (MIT License);

- and again Roberto Ierusalimschy, for his
    [lpeg library](http://www.inf.puc-rio.br/~roberto/lpeg), which has been
    critical to implementing Rosie (MIT License).


## Other sources

Rosie on IBM developerWorks Open:
* [Rosie blogs and talks](https://developer.ibm.com/open/category/rosie-pattern-language/)
* Including:
    * [Project Overview](https://developer.ibm.com/open/rosie-pattern-language/)
    * [Introduction](https://developer.ibm.com/open/2016/02/20/world-data-science-needs-rosie-pattern-language/)
    * [Parsing Spark logs](https://developer.ibm.com/open/2016/04/26/develop-test-rosie-pattern-language-patterns-part-1-parsing-log-files/)
    * [Parsing CSV files](https://developer.ibm.com/open/2016/10/14/develop-test-rosie-pattern-language-patterns-part-2-csv-data/)

For an introduction to Rosie and explanations of the key concepts, see
[Rosie's _raison d'etre_](doc/raisondetre.md).

Rosie's internal components, as well as the utilities needed to build Rosie are
listed [here](doc/arch.md).

I wrote some [notes](doc/geek.md) on Rosie's design and theoretical foundation
for my fellow PL and CS enthusiasts.
