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
local lpeg = require "lpeg"
local writer = require "writer"

local environment = require "environment"
local lookup = environment.lookup
local bind = environment.bind

local c0 = require "c0"
local c1 = require "c1"

---------------------------------------------------------------------------------------------------
-- Launch a co-routine to compile an astlist
---------------------------------------------------------------------------------------------------

local function make_compile(compile_astlist)
   return function(parser, source, env, modtable, importpath)
	     assert(type(parser)=="function", "Internal error: compile: parser not a function")
	     assert(type(source)=="string", "Internal error: compile: source not a string")
	     assert(type(env)=="table", "Internal error: compile: env not a table")
	     assert(type(modtable)=="table" or modtable==nil)
	     assert(type(importpath)=="string" or importpath==nil)
	     local c = coroutine.create(compile_astlist)
	     local no_lua_error, results, messages =
		coroutine.resume(c, parser, source, env, modtable, importpath)
	     if no_lua_error then
		-- Return results and compilation messages
		if results then
		   assert(type(messages)=="table")
		   for i, pat in ipairs(results) do
-- TODO: syntax-expand should save each original_ast as part of the new ast (or something)
--		      if common.pattern.is(pat) then pat.original_ast = original_astlist[i]; end
		   end
		   return results, messages		    -- message may contain compiler warnings
		else
		   assert(type(messages)=="string")
		   return false, {messages}		    -- message is a string in this case
		end
	     else
		error("Internal error (compiler): " .. tostring(results))
	     end
	  end
end

----------------------------------------------------------------------------------------
-- Coroutine body
----------------------------------------------------------------------------------------

local function make_compile_astlist(compile_ast)
   return function(astlist, source, env)
	     assert(type(astlist)=="table", "Compiler: first argument not a list of ast's: "..tostring(astlist))
	     assert(type(source)=="string")
	     local results, messages = {}, {}
	     for i,a in ipairs(astlist) do
		results[i], messages[i] = compile_ast(a, source, env)
		if not messages[i] then messages[i] = false; end -- keep messages a proper list: no nils
	     end
	     return results, messages
	  end
end

----------------------------------------------------------------------------------------
-- Top-level interface to compilers
----------------------------------------------------------------------------------------

local function make_compile_expression(expression_p, compile)
   return function(parser, source, env)
	     assert(type(parser)=="function", "Internal error: compile: parser not a function")
	     assert(type(source)=="string")
	     assert(type(env)=="table")
	     local astlist, original_astlist, messages = parser(source)

	     if not astlist then return nil, messages; end
	     assert(type(astlist)=="table")
	     assert(type(original_astlist)=="table")

	     -- After adding support for semi-colons to end statements, can change this
	     -- restriction to allow arbitrary statements, followed by an expression, like
	     -- scheme's 'begin' form.
	     if (#astlist~=1) then
		local msgs = {"Error: source did not produce a single pattern: " .. source}
		for i, a in ipairs(astlist) do
		   table.insert(msgs, "Pattern " .. i .. ": " .. writer.reveal_ast(a))
		end
		return false, msgs
	     end
	     assert(astlist[1] and original_astlist[1], 
		    "Internal error: missing astlist/original_astlist in compile_expression")
	     if not expression_p(astlist[1]) then
		local msgs = {"Error: not an expression: " .. source}
		return false, msgs
	     end
	     -- Check to see if the expression is a reference
	     local name, pos, text, subs = common.decode_match(astlist[1])
	     local pat
	     if (name=="ref") then
		pat = lookup(env, text)
	     end
	     -- Compile the expression
	     local results, msgs = compile(parser, source, env)
	     if (type(results)~="table") or (not pattern.is(results[1])) then -- compile-time error
		return false, msgs
	     end
	     local result = results[1]
	     if pat then result.alias = pat.alias; end
	     if not (pat and (not pat.alias)) then
		-- If the user entered an identifier, then we are all set, unless it is an alias,
		-- which by itself may capture nothing and thus should be handled like any other
		-- kind of expression.
		-- If the user entered an expression other than an identifier, we should treat it
		-- like it is the RHS of an assignment statement.  Need to give it a name, so we
		-- label it "*" since that can't be an identifier name.
		result.peg = common.match_node_wrap(result.peg, "*")
	     end
	     return result, {}				    -- N.B. returns a single pattern and messages
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
--   Engine    Find a file of module code in the filesystem
--             find_file(importpath, ROSIE_PATH) --> file contents
--   Engine    Match a pattern against an input string
--             match(rplx, input, encoder) --> encoded result or nil, bytes leftover, time in microsec
--             match(source, input, encoder, importpath/nil) where source parses to an expression
--                and importpath specifies an environment via the modtable (this is for pattern testing)
--   Compiler  Load source into an environment (modules into their own fresh environment)
--             load_astlist(importpath/nil, astlist, modtable, env) --> packagename/nil, list of bindings (names) created
--             load_source(importpath/nil, source, modtable, env)
--   Compiler  Import an already-loaded module into an environment
--             import(importpath, prefix, env) --> success/failure
--   Compiler  Compile an expression, producing a compiled expression object
--             compile_expression_astlist(astlist, importpath/nil) --> rplx object
--             compile_expression_source(source, importpath/nil)
--                where importpath specifies an environment via the modtable (useful for testing)
--   Compiler  Calculate the dependencies for top-level or a module
--             deps_astlist(astlist, modtable) --> list of dep where dep = {importpath, prefix, fullpath/error}
--             deps_source(source, modtable)
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
--             prefixes_ast(astlist) --> list of packagenames
--             prefixes_source(source) --> list of packagenames

-- !!! The modtable is going to need to store a ref to the top-level engine env, so that we can
-- !!! pass nil into the above API in the (default, usual) case of compiling in the top level
-- !!! environment.

-- !!! When we re-do the AST representation, we need a slot in each AST node record for the rpl
-- !!! version in which this feature appeared.  That way we can detect mislabeled `rpl x.y`
-- !!! declarations and abort compilation.



--local compile0 = make_compile(make_compile_astlist(c0.compile_ast))
local compile1 = make_compile(c1.compile_module)

return {compile0 = {compile = compile1,
		    compile_expression=make_compile_expression(c0.expression_p, compile1)},
	compile1 = {compile = compile1,
		    compile_expression=make_compile_expression(c0.expression_p, compile1),
--		    compile_module=c1.compile_module, -- remove?
--		    read_module=c1.read_module	    -- TODO: factor into find_module and read_module?
		 }
     }
