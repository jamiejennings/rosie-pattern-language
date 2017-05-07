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

-- local function make_compile(compile_astlist)
--    return function(astlist, original_astlist, source, env)
-- 	     assert(type(astlist)=="table", "Internal error: compile: astlist not a table")
-- 	     assert(type(original_astlist)=="table", "Internal error: compile: original_astlist not a table")
-- 	     assert(type(source)=="string", "Internal error: compile: source not a string")
-- 	     assert(type(env)=="table", "Internal error: compile: env not a table")
-- 	     local c = coroutine.create(compile_astlist)
-- 	     local no_lua_error, results, messages = coroutine.resume(c, astlist, source, env)
-- 	     if no_lua_error then
-- 		-- Return results and compilation messages
-- 		if results then
-- 		   assert(type(messages)=="table")
-- 		   for i, pat in ipairs(results) do
-- 		      pat.original_ast = original_astlist[i];
-- 		   end
-- 		   return results, messages		    -- message may contain compiler warnings
-- 		else
-- 		   assert(type(messages)=="string")
-- 		   return false, {messages}		    -- message is a string in this case
-- 		end
-- 	     else
-- 		error("Internal error (compiler): " .. tostring(results))
-- 	     end
-- 	  end
-- end

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

--local compile0 = make_compile(make_compile_astlist(c0.compile_ast))
local compile1 = make_compile(c1.compile_module)

return {compile0 = {compile = compile1,
		    compile_expression=make_compile_expression(c0.expression_p, compile1)},
	compile1 = {compile = compile1,
		    compile_expression=make_compile_expression(c0.expression_p, compile1),
--		    compile_module=c1.compile_module, -- remove?
		    read_module=c1.read_module	    -- TODO: factor into find_module and read_module?
		 }
     }
