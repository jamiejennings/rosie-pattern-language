In RPL 1.1, parsing Rosie Pattern Language source (i.e. pattern bindings and expression) is
achieved by matching either 'rpl_expression' or 'rpl_statements' (defined in rpl_1_1.rpl)
against input text.  (Pre-parsing to look for an RPL language declaration is a separate phase
that happens before parsing.)  The result is a single parse tree.

The parse tree is searched for nodes named 'syntax_error'.  If found, the error is encoded in a
violation object which is returned with an indication that the parse failed.

A successful parse produces a parse tree.

A parse tree is converted to an AST representation, in which: 
    - Expressions of all kinds are right associative
    - Sequences and choices are n-ary, not binary
    - Assignments, aliases, and grammars are encoded as 'bind' ast nodes
    - Quantified expressions have a uniform representation parameterized by (min, max)
    - Character set unions and intersections are n-ary, not binary
    - Each 'bracket' reflects an explicit [...] construct in the source that is
      not a simple character set (named, list, range)
    - Each 'cooked' reflects an explicit (...) construct in the source
    - Each 'raw' reflects an explicit {...} construct in the source
    - A block contains a language decl (optional), package decl (optional),
      import decls (optional), and zero or more bindings.

Syntax expansion is interleaved with package instantiation, because macros (both user-defined
and built-in) are packaged in modules.  A package is the run-time instantiation of a module.

Packages are currently instantiated by compiling module source (written in RPL)
and providing access to the module's exported bindings for use in subsequent
compilation of other RPL code.  (In the future, packages will be instantiated by
reading a representation of the already-compiled module.)


Syntax expansion for a 'block' is the last step before compiling an RPL block:

  1. Validate the block structure, e.g. declarations occur before bindings.

  2. a. If the block defines a package, create a fresh environment identical to
        the "prelude" environment (which in future may be custom, but currently
        is fixed).  This is the current environment.
	 b. If the block does not define a package, then there must be an
		environment into which it is being loaded.  This is the current
		environment.

  3. For each import declaration in the block: recursively instantiate each
     imported module in the engine's global package table; then bind the
     resulting package name in the current environment.

  4. Expand each binding in the block.  
  
