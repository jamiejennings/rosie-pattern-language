---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TODO: a module-aware version of strict.lua that works with _ENV and not _G
--require "strict"

-- The two principle use case categories for Rosie may be characterized as Interactive and
-- Production, where the latter includes big data scenarios in which performance is paramount and
-- functions like compiling, tracing, and generating human-readable output are not needed.
-- Support for matching using compiled patterns is the focus of "Production" use.

----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a stateful Lua object instantiated in order to match patterns
-- against input data.  An engine is the primary abstraction for using Rosie
-- programmatically in Lua.  (Recall that the REPL, CLI, and API are written in Lua.)
--
-- engine.new(optional_name) creates a new engine with only a "base" environment
--   returns id which is a string;
--   never raises error (unless for internal rosie bug)
-- e:name() returns the engine name (a string) or nil if not set
--   never raises error (unless for internal rosie bug)
-- e:id() returns the engine id
--   never raises error (unless for internal rosie bug)
-- 
-- e:load(rpl_string) compiles rpl_string in the current engine environment
--   the rpl_string has file semantics
--   returns messages where messages is a table of strings
--   raises error if rpl_string fails to compile
-- 
-- e:compile(expression, flavor) compiles the rpl expression
--   returns an rplx object and messages
--   raises error if expression fails to compile
--   API only: returns the (string) id of an rplx object with indefinite extent;
--   The flavor argument, if nil or "match" compiles expression unmodified.  Otherwise:
--     flavor=="search" compiles {{!expression .}* expression}+
--     and more flavors can be added later, e.g.
--     flavor==n, for integer n, compiles {{!expression .}* expression}{0,n}
--   The flavor feature is a convenience function that is a stopgap until we have macros/functions 
--
-- r:match(input, optional_start) like e:match but r is a compiled rplx object
--   returns matches, leftover;
--   never raises an error (unless for internal rosie bug)
--
-- e:match(expression, input, optional_start, optional_flavor)
--   behaves like: r=e:compile(expression, optional_flavor); r:match(input, optional_start)
--   API only: expression can be an rplx id, in which case that compiled expression is used
--   returns matches, leftover;
--   raises error if expression fails to compile
-- 
-- e:tracematch(expression, input, optional_start, optional_flavor) like match, with tracing (was eval)
--   API only: expression can be an rplx id, in which case that compiled expression is used
--   returns matches, leftover, trace;
--   raises error if expression fails to compile
-- 
-- e:output(optional_formatter) sets or returns the formatter (a function)
--   an engine calls formatter on each successful match result;
--   raises error if optional_formatter is not a function
-- e:lookup(optional_identifier) returns the definition of optional_identifier or the entire environment
--   never raises an error (unless for internal rosie bug)
-- e:clear(optional_identifier) erases the definition of optional_identifier or the entire environment
--   never raises an error (unless for internal rosie bug)

-- FUTURE:
--
-- e:trace(id1, ... | nil) trace the listed identifiers, or if nil return the identifiers being traced
-- e:traceall(flag) trace all identifiers if flag is true, or no indentifiers if flag is false
-- e:untrace(id1, ...) untrace the listed identifiers
-- e:tracesearch(identifier, input, optional_start) like search, but generates a trace output (was eval)
--
-- e:stats() returns number of patterns bound, some measure of env size (via lua collectgarbage), more...
--
-- e:match and e:search return a third argument which is the (user) cpu time that it took to match/search


local engine_module = {}

local lpeg = require "lpeg"
local recordtype = require "recordtype"
local unspecified = recordtype.unspecified;
local common = require "common"
local writer = require "writer"
local compile = require "compile"
local cinternals = compile.cinternals
local eval = require "eval"

local engine = 
   recordtype.define(
   {  _name=unspecified;			    -- for reference, debugging
      _rpl_parser=false;
      _rpl_version=false;
      _env=false;
      _id=unspecified;

      encode_function=function(...) return ... end;

      id=false;
      lookup=false;
      clear=false;
      name=false;
      output=false;

      load=false;
      compile=false;

      match=false;
      tracematch=false;

      _error=false;
  },
   "engine"
)

engine.tostring_function =
   function(orig, e)
      local name = ""
      if e._name~=unspecified then name = tostring(e._name) .. " / "; end
      name = name .. e._id
      return '<engine ' .. name .. '>'
   end

local function engine_error(e, msg)
   error(string.format("Engine %s: %s", tostring(e), tostring(msg)), 0)
end

----------------------------------------------------------------------------------------

local rplx = 
   recordtype.define(
   { _pattern=unspecified;
     _engine=unspecified;
     _id=unspecified;
      --
      match=false;
  },
   "rplx"
)

rplx.tostring_function = function(orig, r) return '<rplx ' .. tostring(r._id) .. '>'; end

----------------------------------------------------------------------------------------

-- Grep searches a line for all occurrences of a given pattern.  For Rosie to search a line for
-- all occurrences of pattern p, we want to transform p into:  {{!p .}* p}+
-- E.g.
--    bash-3.2$ ./run '{{!int .}* int}+' /etc/resolv.conf 
--    10 0 1 1 
--    2606 000 1120 8152 2 7 6 4 1 
--
-- Flavors are RPL "macros" hand-coded in Lua, used in Rosie v1.0 as a very limited kind of macro
-- system that we can extend in versions 1.x without losing backwards compatibility (and without
-- introducing a "real" macro facility.
-- N.B. Macros are transformations on ASTs, so they leverage the (rough and in need of
-- refactoring) syntax module.

local function compile_search(en, pattern_exp)
   local rpl_parser, env = en._rpl_parser, en._env
   local env = common.new_env(env)		    -- new scope, which will be discarded
   -- First, we compile the exp in order to give an accurate message if it fails
   -- TODO: do something with leftover?
   local astlist, orig_astlist, warnings, leftover = rpl_parser(pattern_exp)
   if not astlist then return warnings; end	    -- warnings contains errors in this case
   assert(type(astlist)=="table" and astlist[1] and (not astlist[2]))
   local pat, msg = compile.compile_expression(astlist, orig_astlist, pattern_exp, env)
   if not pat then return nil, msg; end
   local replacement = pat.ast
   -- Next, transform pat.ast
   local astlist, orig_astlist = rpl_parser("{{!e .}* e}+")
   assert(type(astlist)=="table" and astlist[1] and (not astlist[2]))
   local template = astlist[1]
   local grep_ast = syntax.replace_ref(template, "e", replacement)
   assert(type(grep_ast)=="table", "syntax.replace_ref failed")
   local pat, msg = compile.compile_expression({grep_ast}, orig_astlist, "SEARCH(" .. pattern_exp .. ")", env)
   if not pat then return nil, msg; end
   assert(pat.peg)
   return pat, {}
end

local function compile_match(en, source)
   local rpl_parser, env = en._rpl_parser, en._env
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))
   -- TODO: do something with leftover?
   local astlist, original_astlist, warnings, leftover = rpl_parser(source)
   if (not astlist) then
      return false, warnings			    -- warnings contains errors in this case
   end
   return compile.compile_expression(astlist, original_astlist, source, env)
end

local function engine_compile(en, expression, flavor)
   flavor = flavor or "match"
   if type(expression)~="string" then engine_error(en, "Expression not a string: " .. tostring(expression)); end
   if type(flavor)~="string" then engine_error(en, "Flavor not a string: " .. tostring(flavor)); end
   local pat, msgs
   if flavor=="match" then
      pat, msgs = compile_match(en, expression)
   elseif flavor=="search" then
      pat, msgs = compile_search(en, expression)
   else
      engine_error(en, "Unknown flavor: " .. flavor)
   end
   if not pat then error(table.concat(msgs, '\n'), 0); end
   return rplx(en, pat), msgs
end

-- N.B. This code is duplicated (for speed) in process_input_file.lua
-- There's still room for optimizations, e.g.
--   Combine with lpeg.Cp() and store that "final" match-able pattern.
--   Create a closure over the encode function to avoid looking it up in e.
--   Close over lpeg.match to avoid looking it up via the peg.
--   Close over the peg itself to avoid looking it up in pat.
local function _engine_match(e, pat, input, start)
   local result, nextpos = (pat.peg * lpeg.Cp()):match(input, start)
   if result then
      return (e.encode_function(result)), (#input - nextpos + 1);
   else
      return false, 1;
   end
end

-- TODO: Maybe cache expressions?
-- returns matches, leftover
local function make_matcher(processing_fcn)
   return function(e, expression, input, start, flavor)
	     if type(input)~="string" then engine_error(e, "Input not a string: " .. tostring(input)); end
	     if start and type(start)~="number" then engine_error(e, "Start position not a number: " .. tostring(start)); end
	     if flavor and type(flavor)~="string" then engine_error(e, "Flavor not a string: " .. tostring(flavor)); end
	     if rplx.is(expression) then
		return processing_fcn(e, expression._pattern, input, start)
	     elseif type(expression)=="string" then -- expression has not been compiled
		-- If we cache, look up expression in the cache here.
		local r = e:compile(expression, flavor)
		return processing_fcn(e, r._pattern, input, start)
	     else
		engine_error(e, "Expression not a string or rplx object: " .. tostring(expression));
	     end
	  end  -- matcher function
end

-- returns matches, leftover
local engine_match = make_matcher(_engine_match)

-- returns matches, leftover, trace
local engine_tracematch = make_matcher(function(e, pat, input, start)
				    local m, left = _engine_match(e, pat, input, start)
				    local _,_,trace = eval.eval(pat, input, start, e._env, false)
				    return m, left, trace
				 end)

----------------------------------------------------------------------------------------

-- load rpl into the engine.  the rpl input has "file scope".
-- returns a possibly-empty table of messages; throws an error if compilation fails.
-- rpl_parser contract:
--   parse source to produce original_astlist;
--   transform original_astlist as needed (e.g. syntax expand); 
--   return the result (astlist), original_astlist, table of messages, leftover count
--   if any step fails, generate useful error messages and return nil, nil, msgs, leftover

local function load_string(e, input)
   local astlist, original_astlist, warnings, leftover = e._rpl_parser(input)
   if not astlist then
      engine_error(e, table.concat(warnings, '\n')) -- in this case, warnings contains errors
   end
   local results, messages = compile.compile(astlist, original_astlist, input, e._env)
   if results then
      assert(type(messages)=="table")
      for i,w in ipairs(warnings) do table.insert(messages, i, w); end
      return common.compact_messages(messages) 
   else
      assert(type(messages)=="table")
      table.move(messages, 1, #messages, #warnings+1, warnings)
      engine_error(e, table.concat(warnings, '\n'))
   end
end

----------------------------------------------------------------------------------------

local function reconstitute_pattern_definition(id, p)
   if p then
      return ( (p.original_ast and writer.reveal_ast(p.original_ast)) or
	       (p.ast and writer.reveal_ast(p.ast)) or
	        "// built-in RPL pattern //" )
   end
   engine_error(e, "undefined identifier: " .. id)
end

local function pattern_properties(name, pat)
   local kind = (pat.alias and "alias") or "definition"
   local color = (co and co.colormap and co.colormap[item]) or ""
   local binding = reconstitute_pattern_definition(name, pat)
   return {type=kind, color=color, binding=binding}
end

-- Lookup an identifier in the engine's environment, and get a human-readable definition of it
-- (reconstituted from its ast).  If identifier is null, return the entire environment.
local function get_environment(en, identifier)
   if identifier then
      local val =  en._env[identifier]
      return val and pattern_properties(identifier, val)
   end
   local flat_env = common.flatten_env(en._env)
   -- Rewrite the flat_env table, replacing the pattern with a table of properties
   for id, pat in pairs(flat_env) do flat_env[id] = pattern_properties(id, pat); end
   return flat_env
end

local function clear_environment(en, identifier)
   if identifier then
      if en._env[identifier] then en._env[identifier] = nil; return true
      else return false; end
   else -- no identifier arg supplied, so wipe the entire env
      en._env = common.new_env()
      return true
   end
end

local function get_set_encoder_function(en, f)
   if not f then return en.encode_function; end
   if type(f)~="function" then engine_error(e, "Output encoder not a function: " .. tostring(f)); end
   en.encode_function = f
end

rplx.create_function =
   function(_new, en, pattern)
      local params = {
	 _engine=en,
	 _pattern=pattern,
	 match=function(self, ...) return _engine_match(en, pattern, ...); end,
      }
      local idstring = tostring(params):match("0x(.*)") or "id/err"
      params._id = idstring
      return _new(params)
   end

local default_rpl_parser = function(...) error("default_rpl_parser not initialized"); end
local default_rpl_version
local function set_default_rpl_parser(parse_expand_explain, major, minor)
   if type(parse_expand_explain)~="function" then
      error("default_rpl_parser not a function: " .. tostring(default_rpl_parser))
   elseif type(major)~="number" then
      error("major version not a number: " .. tostring(major))
   elseif type(minor)~="number" then
      error("minor version not a number: " .. tostring(minor))
   end
   local vt = {major=major, minor=minor}
   default_rpl_parser = parse_expand_explain
   default_rpl_version = setmetatable({}, {__index=vt,
					   __newindex=function(...) error("read-only table") end,
					   __tostring=function(self) return tostring(vt.major).."."..tostring(vt.minor); end,
					})
end

engine.create_function =
   function(_new, name, initial_env)
      initial_env = initial_env or common.new_env()
      -- assigning a unique instance id should be part of the recordtype module
      local params = {_name=name,
		      _rpl_parser=default_rpl_parser;
		      _rpl_version=default_rpl_version;
		      _env=initial_env,

		      lookup=get_environment,
		      clear=clear_environment,
		      id=function(en)
			    if engine.is(en) then return en._id;
			    else error("Arg to id function is not an engine: " .. tostring(en))
			    end
			 end,
		      name=function(en)
			      -- checking the unused arg for consistency with other engine functions
			      if engine.is(en) then return name;
			      else error("Arg to name function is not an engine: " .. tostring(en))
			      end
			   end,
		      output=get_set_encoder_function,

		      match=engine_match,
		      tracematch=engine_tracematch,
		      load=load_string,
		      compile=engine_compile,

		      _error=engine_error,
		   }
      local idstring = tostring(params):match("0x(.*)") or "id/err"
      params._id = idstring
      return _new(params)
   end

-- recordtype package defines a creator function that is named after the record type name
engine_module.new = engine
engine_module.is = engine.is
engine_module._set_default_rpl_parser = set_default_rpl_parser

engine_module.rplx = rplx			    -- debugging

return engine_module
