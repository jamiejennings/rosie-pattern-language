---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TODO: a module-aware version of strict.lua that works with _ENV and not _G
--require "strict"

-- The two principle use case categories for Rosie may be characterized as Interactive and
-- Production, where the latter includes big data scenarios in which performance is paramount and
-- functions like compiling, tracing, and generating human-readable output are not needed.

-- Type of use   | In Lua          | In API
-- ------------- | --------------- | --------------
-- Interactive   | 
-- Production    | 

----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a stateful Lua object instantiated in order to match patterns
-- against input data.  An engine is the primary abstraction for using Rosie
-- programmatically in Lua.
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
-- e:match(expression, input, optional_flavor, optional_start)
--   behaves like: r=e:compile(expression, optional_flavor); r:match(input, optional_start)
--   API only: expression can be an rplx id, in which case that compiled expression is used
--   returns matches, leftover;
--   raises error if expression fails to compile
-- 
-- e:tracematch(expression, input, optional_flavor, optional_start) like match, with tracing (was eval)
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

-- Engines (now) know nothing about files.  File processing routines are defined in
-- process_input_file.lua and exposed via the rosie module.

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

local json = require "cjson"
local lpeg = require "lpeg"
local recordtype = require "recordtype"
local unspecified = recordtype.unspecified;
local common = require "common"
local parse = require "parse"
local compile = require "compile"
local eval = require "eval"
local grep = require "grep"

local engine = 
   recordtype.define(
   {  _name=unspecified;			    -- for reference, debugging
      env=false;
      _id=unspecified;
      --
--      encode=false;
      encode_function=function(...) return ... end;
--      expression=false;
--      pattern=false;
      --
      id=false;
      lookup=false;
      clear=false;
      name=false;
      output=false;

      load=false;
      compile=false;

      match=false;
      eval=false;
      grep=false;

      _match=false;

      _error=false;

--      configure=false;
--      inspect=false;

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

-- local locale = lpeg.locale()

local function engine_error(e, msg)
   error(string.format("Engine %s: %s", tostring(e), tostring(msg)), 0)
end

-- local function no_pattern(e)
--    engine_error(e, "no pattern configured")
-- end

-- local function no_encode(e)
--    engine_error(e, "no encode configured")
-- end

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

-- local encode_table =
--    {json = json.encode,
--     color = co.color_string_from_leaf_nodes,
--     nocolor = co.string_from_leaf_nodes,
--     fulltext = common.match_to_text,
--     [false] = function(...) return ...; end
--  }

-- local function name_to_encode(name)
--    return encode_table[name]
-- end

-- local function encode_to_name(fcn)
--    for k,v in pairs(encode_table) do
--       if v==fcn then return k; end
--    end
--    return "<unknown encode type>"
-- end

-- ----------------------------------------------------------------------------------------

-- local function engine_configure(e, configuration)
--    for k,v in pairs(configuration) do
--       if k=="expression" then
-- 	 local pat, msg = compile.compile_match_expression(v, e.env)
-- 	 if not pat then return false, msg; end
-- 	 e.expression = v
-- 	 e.pattern = pat
--       elseif k=="encode" then
-- 	 local f = name_to_encode(v)
-- 	 if type(f)~="function" then
-- 	    return false, 'invalid value for encode: "' .. tostring(v) .. '"'
-- 	 else
-- 	    e.encode = v
-- 	    e.encode_function = f
-- 	 end
--       elseif k=="name" then
-- 	 e._name = tostring(v)
--       else
-- 	 return false, 'invalid configuration parameter: ' .. tostring(k)
--       end
--    end -- for each configuration key/value
--    return true
-- end

-- local function engine_inspect(e)
--    return {name=e._name, expression=e.expression, encode=e.encode, id=e._id}
-- end

local function _engine_match(e, pat, input, start)
   --start = start or 1
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
   return function(e, expression, input, start)
	     if type(input)~="string" then engine_error(e, "Input not a string: " .. tostring(input)); end
	     local pat, msg
	     if rplx.is(expression) then
		return processing_fcn(e, rplx._pattern, input, start)
	     elseif type(expression)=="string" then -- expression has not been compiled
		-- pat = cache(expression)
		-- if not pat then
		   pat, msg = compile.compile_match_expression(expression, e.env)
		   if not pat then engine_error(e, msg); end
		--    cache(expression, pat)
		-- end
		return processing_fcn(e, pat, input, start)
	     else
		engine_error(e, "Expression not a string or rplx: " .. tostring(expression));
	     end
	  end  -- matcher function
end

-- returns matches, leftover
local engine_match = make_matcher(_engine_match)

-- returns matches, leftover, trace
local engine_eval = make_matcher(function(e, pat, input, start)
				    return eval.eval(pat, input, start, e.env, false)
				 end)

-- Having a grep function is a convenience.  It doesn't need to be here, but it's parallel in
-- function to match and eval, plus until we implement macros/functions, it saves users the typing
-- needed to do it for themselves.
-- returns matches, leftover
local engine_grep = make_matcher(grep.pattern_EXP_to_grep_pattern, _engine_match)

local function engine_compile(en, expression, flavor)
   flavor = flavor or "match"
   if type(expression)~="string" then engine_error(en, "Expression not a string: " .. tostring(expression)); end
   if type(flavor)~="string" then engine_error(en, "Flavor not a string: " .. tostring(flavor)); end
   local pat, msg
   if flavor=="match" then
      pat, msg = compile.compile_match_expression(expression, en.env)
   elseif flavor=="search" then
      pat, msg = grep.pattern_EXP_to_grep_pattern(expression, en.env)
   else
      engine_error(en, "Unknown flavor: " .. flavor)
   end
   if not pat then error(msg, 0); end
   return rplx(en, pat)
end
   

----------------------------------------------------------------------------------------

local function load_string(en, input)
   local results, messages = compile.compile_source(input, en.env)
   if not results then engine_error(e, messages); end -- messages is a string in this case
   return common.compact_messages(messages)	    -- return a list of zero or more strings
end

----------------------------------------------------------------------------------------

local function reconstitute_pattern_definition(id, p)
   if p then
      return ( (p.original_ast and parse.reveal_ast(p.original_ast)) or
	       (p.ast and parse.reveal_ast(p.ast)) or
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
function get_environment(en, identifier)
   if identifier then
      local val =  en.env[identifier]
      return val and pattern_properties(identifier, val)
   end
   local flat_env = common.flatten_env(en.env)
   -- Rewrite the flat_env table, replacing the pattern with a table of properties
   for id, pat in pairs(flat_env) do flat_env[id] = pattern_properties(id, pat); end
   return flat_env
end

local function clear_environment(en, identifier)
   if identifier then
      if en.env[identifier] then
	 en.env[identifier] = nil
	 return true
      else
	 return false
      end
   else -- no identifier arg supplied, so wipe the entire env
      en.env = common.new_env()
      return true
   end
end

local function get_set_encoder_function(en, f)
   if not f then return en.encode_function; end
   if type(f)~="function" then engine_error(e, "Output encoder not a function: " .. tostring(f)); end
   en.encode_function = f
end

rplx.create_function =
   function(_new, engine, pattern)
--      print("New rplx.  engine="..tostring(engine)..", pattern="..tostring(pattern))
      local params = {
	 _engine=engine,
	 _pattern=pattern,
	 match=function(self, ...) return engine._match(engine, pattern, ...); end,
      }
      local idstring = tostring(params):match("0x(.*)") or "id/err"
      params._id = idstring
      return _new(params)
   end


engine.create_function =
   function(_new, name, initial_env)
      initial_env = initial_env or common.new_env()
      -- assigning a unique instance id should be part of the recordtype module
      local params = {_name=name,
		      env=initial_env,
		      -- setting expression causes pattern to be set
--		      expression="<uninitialized>",
--		      pattern=false,
		      -- setting encode causes encode_function to be set
--		      encode=false,
--		      encode_function=name_to_encode(false),
		      -- functions
		      lookup=get_environment,
		      clear=clear_environment,
		      id=function(en) return en._id; end,
		      name=function(en) return name; end,
		      output=get_set_encoder_function,

		      match=engine_match,
		      grep=engine_grep,
		      eval=engine_eval,
		      load=load_string,
		      compile=engine_compile,

		      _match=_engine_match,

		      _error=engine_error,

		      -- configure=engine_configure,
		      -- inspect=engine_inspect
		   }
      local idstring = tostring(params):match("0x(.*)") or "id/err"
      params._id = idstring
      return _new(params)
   end

-- recordtype package defines a creator function that is named after the record type name
engine_module.new = engine
engine_module.is = engine.is

engine_module.rplx = rplx			    -- debugging

return engine_module
