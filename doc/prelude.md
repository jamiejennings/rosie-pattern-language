<!--  -*- Mode: GFM; -*-                                                       -->
<!--                                                                           -->
<!--  prelude.md                                                               -->
<!--                                                                           -->
<!--  © Copyright Jamie A. Jennings 2018.                                      -->
<!--  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  -->
<!--  AUTHOR: Jamie A. Jennings                                                -->

# The Rosie Pattern Language Prelude

## Background

Blah blah Haskell.

Blah blah Go built-in packages.

Blah blah Allowing more extensive user customization of Rosie.

Blah blah Opening the door, perhaps, to supporting other character encodings
beyond UTF-8.


## Starting up

Loading an RPL file compiles it in the user (top level) environment.

When Rosie starts, it creates the user environment, which is initially empty.

If there is no `prelude` directive in effect, either from the command line or
the startup file, then the _standard prelude_ is used.

Otherwise, the `prelude` directive refers to an RPL file.  That file is
functioning here as a prelude, but it is in most respects an ordinary RPL
module.

The directive `prelude <p>` is processed as if `import <p> as .` were executed
in an empty environment.  The standard prelude is processed in the identical
way. 

The remainder of this discussion applies to a prelude `<p>`, which may be the
standard prelude or a custom one.

The prelude may import RPL libraries, and create RPL bindings.  In fact, the
purpose of the prelude is to create bindings that in the top level (user)
environment.  As with any imported library, the bindings imported into `<p>`
will _not_ be visible in the user environment after the prelude is imported.

The standard prelude defines:

.
$
^
~
ci
error
find
findall
halt
keepto
message
_and the posix character classes_

The user receives this environment.


## Importing a package

Suppose the user imports a package.  Importing a package creates a new
environment into which the package bindings will be loaded.  This environment,
which is initially empty, is also prepared using a prelude before it is used.

In this case, a prelude directive must come from within the package being
imported.  In the absence of such a directive, the standard prelude is
processed, just as with the Rosie startup environment.


## Custom prelude

What must a custom prelude do?

It must provide a base set of bindings that can be used by RPL code which is
subsequently compiled, loaded, or imported.

Ordinarily, RPL code expects the definitions that are made available by the
standard prelude.  If you write a custom prelude and later use RPL code that was
written for the standard prelude, two complications may arise:

1. missing bindings
2. unexpected behavior, perhaps contrary to the intentions of the RPL code
author

In either case, the RPL code in use may no longer pass its own unit tests.

More likely use cases are (1) that you write a custom prelude to strictly add to the
base set of available bindings for your own RPL code; or (2) your custom prelude
changes the default behavior of Rosie to suit a particular use case, such as
parsing binary data.

An alternative to case (1): Put your most used definitions into a library file,
and always import this file when writing RPL files.  This will make it easier to
share your RPL code with other people.

A note about case (2): In a running instance of Rosie, the packages used do not
need to rely on the same prelude.  Indeed, it is possible to write a collection
of libraries that depend on one prelude, while other libraries depend on a
different one, and still others use the standard one.


## Writing a custom prelude

How can I define anything in my custom prelude, if I start with an empty
environment?

You can import RPL packages, because they will depend on their own prelude,
custom or otherwise.

You can import built-in RPL packages, which have no external dependencies.

You can compose new definitions using imported bindings and primitive
expressions like character sets and string literals.


## Built-in packages

What are built-in packages?

RPL functionality that cannot be written in RPL itself is implemented in code
(in Lua and C) but organized as if it was written in a module.  That makes this
functionality available to users through the normal RPL `import` facility.

Examples of built-in capabilities are:

- detect the start or end of the input (bound by default to `^` and `$`)
- the `halt` pattern, which matches the empty string and aborts the match
- RPL functions such as `message` and `error`
- RPL macros such as `ci`, `find`, and `findall`


If I can import built-in packages as if they were ordinary packages, then what
are their import paths?

In the Rosie distribution, the directory `rpl/builtin` contains a file for each
built-in package.  These RPL files are not processed by Rosie in the usual way,
of course, since built-in functionality by definition cannot be written in RPL.
The files are there to document the built-in packages.

