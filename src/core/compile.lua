---- -*- Mode: Lua; -*-                                                                           
----
---- compile.lua   Compile Rosie Pattern Language to LPEG
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local string = require "string"
local coroutine = require "coroutine"
local common = require "common"
local pattern = common.pattern
local cerror = common.cerror
local lpeg = require "lpeg"

local environment = require "environment"
local lookup = environment.lookup
local bind = environment.bind

local c0 = require "c0"
local c1 = require "c1"

---------------------------------------------------------------------------------------------------
-- Launch a co-routine to compile an ast
---------------------------------------------------------------------------------------------------

-- compile(importpath or nil, ast, modtable, env) --> success, packagename or nil, messages
--   where success is boolean, packagename is a string if the ast defined a module, and
--   messages is a table of cerror records

local function make_compile(compile_ast)
   return function(importpath, ast, modtable, env)
	     assert(type(importpath)=="string" or importpath==nil)
	     assert(type(ast)=="table")
	     assert(type(modtable)=="table")
	     assert(environment.is(env))
	     local c = coroutine.create(compile_ast)
	     -- may get a new env back 
	     local no_lua_error, success, packagename, messages =
		coroutine.resume(c, importpath, ast, modtable, env)
	     if no_lua_error then
		if success then
		   assert(type(packagename)=="string" or packagename==nil)
		   assert(type(messages)=="table")
		   return success, packagename, messages -- message may contain compiler warnings
		else
		   messages = packagename	    -- error message is second return value
--		   assert(type(messages)=="string", "messages is: " .. tostring(messages))
		   assert(cerror.is(messages))
		   return false, nil, {messages}
		end
	     else
		local st = debug.traceback()
		-- in the event of an error, the next value returned is the message
		error("Internal error (compiler): " .. tostring(success) .. '\n' .. st)
	     end
	  end
end

----------------------------------------------------------------------------------------
-- Coroutine body
----------------------------------------------------------------------------------------

-- N.B. make_compile_expression produces a compiler for expressions meant for top level matching.
-- The patterns produced are guaranteed to capture something, and the top level capture will be
-- named "*" UNLESS the expression is an identifier bound to a pattern that is not an alias.  In
-- that case, the top level capture will have the name of the identifier.

local function make_compile_expression(expression_p, compile_ast)
   return function(importpath, ast, modtable, env)
	     assert(type(importpath)=="string" or importpath==nil, "importpath was: " .. tostring(importpath))
	     assert(type(ast)=="table", "ast is: " .. tostring(ast))
	     assert(ast.type=="rpl_expression" or ast.type=="core")
	     assert(type(modtable)=="table")
	     assert(environment.is(env))

	     local modname
	     if importpath then
		modname, env = common.modtableref(modtable, importpath)
		if not env then return false, nil, {"Error: no loaded module " .. importpath}; end
	     end
	     
	     local astlist = ast.subs
	     assert(#astlist==1)

	     if not expression_p(astlist[1]) then return false, nil, {"Error: not an expression"}; end

	     local c = coroutine.create(compile_ast)
	     local no_lua_error, pat, message = coroutine.resume(c, astlist[1], env)
	     if no_lua_error then
		if pat then
		   if not pattern.is(pat) then
		      return false, nil, {"Error: expression not a pattern: " .. tostring(pat)}
		   end
		   local typ, pos, text, subs = common.decode_match(astlist[1])
		   if (typ~="ref" and typ~="extref") or pat.alias then
		      pat.peg = common.match_node_wrap(pat.peg, "*") -- anonymous expression
		      pat.alias = false
		   end
		   return true, pat, {message}
		else -- compilation failed
		   return false, nil, {message}
		end
	     else -- lua error (a bug)
		local st = debug.traceback()
		error("Internal error (compiler): " .. tostring(pat))
	     end
	  end
end

----------------------------------------------------------------------------------------
-- Compiler interface
----------------------------------------------------------------------------------------

-- Relationship between engine and compiler:
--
-- Until now, the compiler did not know anything about engines.  The engine kept an environment,
-- which was passed to the compiler.  The engine recently acquired a parser (now that there can be
-- several, instead of a single "universal" rpl parser), and it used its parser on source, passing
-- the resulting ast forest to the compiler.
--
-- With the creation of rpl 1.1, the engine acquired its own compiler as well (instead of one
-- "universal" compiler).  For a brief time, there was, by necessity, a uniform set of interfaces
-- enabling an engine to orchestrate: parse -> syntax-expand -> compile (with appropriate error
-- handling between).
--
-- But rpl 1.1 supports modules, which means that while compiling a unit of rpl code, we may need
-- to find, read, parse, and compile another unit of rpl (i.e. an imported module).  In the
-- future, it will be possible to load a module that has already been compiled, but that is not
-- the case today.
--
-- With rpl 1.1 and its modules, the following scenarios need to be supported:
--
--   Common    Find a file of module code in the filesystem
--             get_file(importpath, ROSIE_PATH) --> fullpath, file contents
--   Engine    Match a pattern against an input string
--             match(rplx, input, encoder) --> encoded result or nil, bytes leftover, time in microsec
--             match(source, input, encoder, importpath/nil) where source parses to an expression
--                and importpath specifies an environment via the modtable (this is for pattern testing)
--   Compiler  Load source into an environment (modules into their own fresh environment)
--             load(importpath/nil, source/ast, modtable, env) --> packagename/nil, list of bindings created
--   Compiler  Import an already-loaded module into an environment
--             import(importpath, prefix, env) --> success/failure
--   Compiler  Compile an expression, producing a compiled expression object
--             compile_expression(source/ast, importpath/nil) --> rplx object
--                where importpath specifies an environment via the modtable (useful for testing)
--   Parser    Calculate the dependencies for top-level or a module
--             parse_deps(source/ast, modtable) --> list of dep where dep = {importpath, prefix}
-- X Tester    USE ENGINE'S MATCH INTERFACE AND SUPPLY THE IMPORTPATH
--             Run a lightweight pattern test for top-level code
--             Create an engine.  Load the code.
--             test(engine, nil, name, input, encoder) --> same as match function
-- X Tester    USE ENGINE'S MATCH INTERFACE AND SUPPLY THE IMPORTPATH
--             Run the lightweight pattern tests for a module (via special api?)
--             Create an engine.  Load the module code.
--             test(engine, importpath, name, input, encoder) --> same as match function
--   Parser    Look for and parse the (1) optional BOM, (2) optional rpl language level
--             declaration. 
--             preparse(source) --> major, minor, nextpos, bom -OR- nil, nil, 1, bom
--                where bom is nil, "UTF-8", "UTF-16BE", "UTF16-LE", "UTF-32BE", or "UTF-32LE"
--   Parser    Extract a list of prefixes used in the given expressions or statements
--             prefixes_ast(ast) --> list of packagenames
--             prefixes_source(source) --> list of packagenames

-- !!! When we re-do the AST representation, we need a slot in each AST node record for the rpl
-- !!! version in which this feature appeared.  That way we can detect mislabeled `rpl x.y`
-- !!! declarations and abort compilation.

-- Maybe: Create a thread-level message queue when we create the compiler coroutine, so that
-- warnings and other messages can be enqueued there via a function call, and not by directly
-- manipulating a table of strings.


----------------------------------------------------------------------------------------
-- Top-level interface to compilers
----------------------------------------------------------------------------------------

local compile1 = make_compile(c1.load)

return {compile0 = {compile = compile1,
		    compile_expression=make_compile_expression(c0.expression_p, c1.compile_ast)},
	compile1 = {compile = compile1,
		    compile_expression=make_compile_expression(c0.expression_p, c1.compile_ast),
		    deps = deps,
--		    compile_module=c1.compile_module, -- remove?
--		    read_module=c1.read_module	    -- TODO: factor into find_module and read_module?
		 }
     }
