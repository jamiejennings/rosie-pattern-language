-- -*- Mode: Lua; -*-                                                                             
--
-- loadpkg.lua   load an RPL module, which instantiates a run-time package
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
--   2. If the block defines a package, create a fresh environment (else use top level) to be the
--      current environment
--   3. For each import in the block environment: recursively instantiate the imported module; then
--      bind the resulting package name in the current environment
--   4. Expand each binding in the block, in order of appearance

-- Syntax expansion steps for a 'binding':
--   1. Introduce explicit cooked groups where they are implied, e.g. rhs of assignments
--   2. Expand the expression on the right hand side

-- Syntax expansion steps for an expression:
--   1. Apply user-defined and built-in macro expansions
--   2. Remove cooked groups by interleaving references to the boundary identifier, ~.

local ast = require "ast"
local engine_module = require "engine_module"
local engine = engine_module.engine
local environment = require "environment"
local common = require "common"

--local c2 = require "c2"
c2 = {}
c2.compile_block = function(...)
		      print("load: dummy compile_block called")
		      return true
		   end


local load = {}

-- 'validate_block' enforces the structure of an rpl module:
--     rpl_module = language_decl? package_decl? import_decl* statement* ignore
--
-- We could parse a module using that pattern, but we can give better error messages this way.
-- Returns: success, table of messages
-- Side effects: fills in block.pdecl, block.ideclist; removes decls from block.stmts
local function validate_block(a)
   assert(ast.block.is(a))
   local stmts = a.stmts
   if not stmts[1] then
      return true, {cerror.new("warning", a, "Empty input")}
   elseif ast.pdecl.is(stmts[1]) then
      a.pdecl = table.remove(stmts, 1)
      common.note("load: in package " .. a.pdecl.name)
   end
   if not stmts[1] then
      return true, {cerror.new("warning", a, "Empty module (nothing after package declaration")}
   elseif not ast.ideclist.is(stmts[1]) then
      return true, {cerror.new("info", a, "Module consists only of import declarations")}
   end
   a.ideclist = table.remove(stmts, 1)
   for _, s in ipairs(stmts) do
      if not ast.binding.is(s) then
	 return false, {cerror.new("error", s, "Declarations must appear before assignments")}
      end
   end -- for
   return true, {}
end

local function parse(e, src, messages)
   assert(engine.is(e))
   assert(type(src)=="string")
   assert(type(messages)=="table")
   local parser = e.compiler.parser
   local pt, original_pt, warnings, leftover = parser.parse_statements(src)
   assert(type(warnings)=="table")
   if not pt then
      table.insert(messages, cerror.new("syntax", {}, table.concat(warnings, "\n")))
      return false
   end
   table.move(warnings, 1, #warnings, #messages+1, messages)
   assert(type(pt)=="table")
   return ast.from_parse_tree(pt)
end
   
-- Returns pkgname, pkgenv
local function compile(e, a, pkgenv, messages)
   -- we call the compiler with the import declarations already processed, and the imported
   -- bindings accessible in pkgenv
   local pkgname = a.pdecl and a.pdecl.name
   if not c2.compile_block(a, e._pkgtable, pkgenv, messages) then
      common.note(string.format("load: FAILED TO COMPILE %s", pkgname or "<top level>"))
      return false
   end
   if (not pkgname) then
      local msg = (a.importpath or "<top level>") .. " is not a module (no package declaration found)"
      table.insert(messages, cerror.new("error", a, msg))
      return false
   end
   common.note(string.format("load: compiled %s", pkgname or "<top level>"))
   return pkgname, pkgenv
end

local function expand(e, a, env, messages)
   -- ... TODO ...
   print("load: dummy expand function called")
   return true
end

function load.module(e, src, importpath, fullpath, messages)
   local pkgenv = environment.new()
   local a = parse(e, src, messages)
   if not a then return false; end
   a.importpath = importpath
   a.filename = fullpath
   if not validate_block(a) then return false; end
   -- Via side effects, a.pdecl and a.ideclist are now filled in.
   -- With a mutually recursive call to load.imports, we can load the dependencies in a.ideclist. 
   if not load.imports(e, importpath, a.ideclist, pkgenv, messages) then return false; end
   if not expand(e, a, pkgenv, messages) then return false; end
   return compile(e, a, pkgenv, messages) 
end

local function import_from_source(e, importpath, decl, messages)
   local fullpath, source = common.get_file(decl.importpath, e.searchpath)
   if not fullpath then
      local err = ("load: cannot find module source for '" .. decl.importpath ..
		   "' needed by module '" .. (importpath or "<top level>") .. "'")
      table.insert(messages, cerror.new("error", decl, err))
      return false
   end
   common.note("load: loading ", decl.importpath, " from ", fullpath)
   return load.module(e, src, importpath, fullpath, messages)
end

local function import(e, importpath, decl, messages)
   assert(type(decl.importpath)=="string")
   -- First, look in the engine's pkgtable to see if this pkg has been loaded already
   local pkgname, pkgenv = e:pkgtableref(decl.importpath)
   if pkgname then return pkgname, pkgenv; end
   common.note("load: looking for ", decl.importpath)
   -- FUTURE: Next, look for a compiled version of the file to load
   -- ...
   -- Finally, look for a source file to compile and load
   return import_from_source(e, importpath, decl, messages)
end

-- 'load.imports' recursively loads each import in ideclist.
-- Returns success; side-effects the messages argument.
function load.imports(pkgtable, importpath, ideclist, target_env, messages)
   assert(engine.is(e))
   assert(environment.is(target_env))
   assert(ast.ideclist.is(ideclist))
   assert(type(messages)=="table")
   for _, decl in ipairs(ideclist.idecls) do
      local pkgname, pkgenv = import(e, importpath, decl, messages)
      if not pkgname then
	 common.note("FAILED to import from path " ..
		     tostring(decl.importpath) ..
		     " required by " .. (importpath or "top level"))
	 return false
      end
   end
   return true
end

-- The load procedure compiles in a fresh environment (creating new bindings there) UNLESS
-- importpath is nil, which indicates "top level" loading into env.  Each dependency must already
-- be compiled and have an entry in pkgtable, else the compilation will fail.
--
-- importpath: a relative filesystem path to the source file, or nil
-- ast: the already preparsed, parsed, and expanded input to be compiled
-- pkgtable: the global package table (one per engine) because packages can be shared
-- 









return load
