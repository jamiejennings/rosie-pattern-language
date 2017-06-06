-- -*- Mode: Lua; -*-                                                                             
--
-- expand.lua   macro-expansion
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- In RPL 1.1, parsing Rosie Pattern Language source (i.e. pattern bindings and expression) is
-- achieved by matching either 'rpl_expression' or 'rpl_statements' (defined in rpl_1_1.rpl)
-- against input text.  (Pre-parsing to look for an RPL language declaration is a separate phase
-- that happens before parsing.)  The result is a single parse tree.
--
-- The parse tree is searched for nodes named 'syntax_error'.  If found, the error is encoded in a
-- cerror data structure which is returned with an indication that the parse failed.
--
-- A successful parse produces a parse tree.
-- 
-- A parse tree is converted to an AST representation, in which: 
--     - Expressions of all kinds are right associative
--     - Sequences and choices are n-ary, not binary
--     - Assignments, aliases, and grammars are encoded as 'bind' ast nodes
--     - Quantified expressions have a uniform representation parameterized by (min, max)
--     - Character set unions and intersections are n-ary, not binary
--     - Each 'cexp' reflects an explicit [...] construct in the source
--     - Each 'cooked' reflects an explicit (...) construct in the source
--     - Each 'raw' reflects an explicit {...} construct in the source
--     - A block contains a package decl (optional), import decls (optional), and zero or more
--       bindings.

-- Syntax expansion is interleaved with package instantiation, because macros (both user-defined
-- and built-in) are packaged in modules.  A package is the run-time instantiation of a module.
--
-- Packages are currently instantiated by compiling module source (written in RPL) and providing
-- access to the module's exported bindings for use in subsequent compilation of other RPL code.
-- (In the future, packages will be instantiated by reading a representation of the
-- already-compiled module.)

-- Syntax expansion steps for a 'block':
--   1. Validate the block structure, e.g. declarations occur before bindings.
--   2. If the block defines a package, create a fresh environment for it (else use top level)
--   2. For each import in the block environment: parse, expand, compile, make exports accessible
--   3. Expand each binding in the block, in order of appearance

-- Syntax expansion steps for a 'binding':
--   1. Introduce explicit cooked groups where they are implied, e.g. rhs of assignments
--   2. Expand the expression on the right hand side

-- Syntax expansion steps for an expression:
--   1. Apply user-defined and built-in macro expansions
--   2. Remove cooked groups by interleaving references to the boundary identifier, ~.

local ast = require "ast"

local expand = {}








return expand
