# Major work items

- [x] Enhance rpl file loading capability
    - [x] Provide a way for files listed in a manifest to be loaded from the
          manifest directory, no matter where that is.  This permits the ability
          to zip up a manifest and its files and send it to someone else.
    - [x] Provide a way for a file name to reference the Rosie install
          directory, so that manifests can refer to rpl files that are shipped
          with Rosie.
	- [x] Provide a way for file names to refer to an environment variable that
          contains their location in the file system. 
	- [x] Support file names with embedded spaces (as long as they are escaped
          when typed at the repl or put into a manifest file. 
	  
- [x] Support "\" as the file path separator on Windows

- [x] Support an optional ROSIE_HOME environment variable to facilitate the Rosie port to Windows.

- [ ] Create and expose a comprehensive Rosie API
    - [x] Lua API (lapi)
	- [x] External API (api) using JSON encoding
    - [x] Expose the Rosie API as a C library; make it available through libffi.
	- [ ] Provide proof-of-concept librosie-using sample programs: C, go,
          Python, Ruby, node.js, java

- [x] Enhance character expressions to include:
    - [x] Union of character sets, e.g. `[[a-f][0-9]`
    - [x] Complement of individual character set, e.g. `[^w-z]` and `[:^alpha:]`
	- [x] Complement of union, e.g. `[^[0-9][:^alpha:]]`

- [ ] Add color output management to the Rosie API so any client could leverage
      it. Support CRUD on color assignments for color output. (Need to rewrite
      color-output.lua, which was a quick hack.)

- [ ] Maybe have an option to output the entire line containing a match, in
      order to make Rosie an alternative to grep.  This would be useful for
      "playing" with Rosie to understand how rpl expressions ("rosex"?) differ
      from regex, and maybe for use in shell scripts as well.

- [x] Use syntax transformation (on ASTs) instead of current code for:
    - [x] repetition syntax with one bound, e.g. {5} (meaning {5,5})
    - [x] tokenization ("cooked" expressions)
	- [x] top-level check for boundary after a cooked top-level expression

- [ ] Maybe add an AST transform for quantified expressions to eliminate the
      code that handles them today?

- [ ] Allow specification of Unicode code points (utf-8 encoding) as part of character expressions

- [ ] Enhance debugging
    - [ ] Enhance syntax error reporting (do this AFTER the syntax transformation work is done)

- [x] Change the REPL to incrementally parse the input line (dispatch on the first token, then parse the rest)

- [ ] Implement post-match instructions, based on prototype work; consider
      JSON-to-JSON transforms as well

- [ ] Module system
    - [ ] Enforce package namespaces, with import/export declarations
    - [ ] Store environment pointer with patterns (explicit closures) and update
          eval and reveal (more?) to reference those environments.  Note: RPL
          compilation is lexically scoped in the sense that an expression is
          closed over the environment in which it is defined.  But "eval" (the
          interpreter function used for debugging) is ACCIDENTALLY dynamically
          scoped. See doc/eval-scope-note.txt.
	- [ ] Eliminate MANFIFEST file; add an environment variable containing the
          default file to load instead

- [ ] Source references
    - [ ] Store a source ref with each match; for efficient output, maybe output
          it separately from the matches themselves?
    - [ ] Add a .where command to the repl to reveal where a pattern came from

- [ ] Expose testing functionality via the API so that the user can code up a
      set of tests for their own patterns, and Rosie will run the tests and
      summarize the results.

- [ ] Support arbitrary versions and dialects of RPL with a simple declaration,
      e.g. `.interpreter "rpl/0.92"`, which will load that version/dialect of
      RPL and use it for the (remainder of) the definitions in that file.
      (Implementation will introduce a lexical scope to facilitate future
      addition of block structure to RPL.)

- [ ] Optimizations (back burner, because performance is v good now)
    - [ ] Profiling
        - [ ] If profiling suggests it would help, try LuaJIT
		- [ ] Save a compiled env so that we don't have to re-compile always
		- [ ] Approach: de/serialize a rosie engine's environment
		- [x] Will luac be helpful as well?
    - [x] Tune the run-time matching loop
	- [ ] RPL Compiler
        - [ ] Remove unnecessary assertions (which are VERY slow in Lua)
        - [ ] Simplify each AST, e.g. by removing sequences of boundaries (checking for idempotence first)
        - [ ] Avoid multiple table indexing by assigning to a local
        - [ ] Within modules, by assigning imported values to locals
        - [ ] Within functions

