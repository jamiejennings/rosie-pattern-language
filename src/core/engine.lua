---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TODO: a module-aware version of strict.lua that works with _ENV and not _G
--require "strict"

----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a stateful Lua object instantiated in order to match patterns
-- against input data.  An engine is the primary abstraction for using Rosie
-- programmatically in Lua.
--
-- engine.new(optional_name) creates a new engine with only a "base" environment
-- e:name() returns the engine name
-- e:id() returns the engine id
-- e:load(rpl_string) compiles rpl_string in the current engine environment
-- e:match(expression, input) compiles the string expression and applies it to input string
-- e:eval(expression, input) like match, but generates a trace output
-- e:grep(expression, input) like match, but compiles this instead: {!expression .}* expression+
-- e:output(optional_formatter) sets or returns the formatter (a function)
--   for convenience, an engine calls formatter on each successful match result
-- e:env(optional_identifier) returns the definition of optional_identifier or the entire environment
-- e:clear(optional_identifier) erases the definition of optional_identifier or the entire environment

-- Engines (now) know nothing about files.  File processing routines are defined in
-- process_input_file.lua and exposed via the rosie module.

local engine_module = {}

local json = require "cjson"
local lpeg = require "lpeg"
local recordtype = require "recordtype"
local unspecified = recordtype.unspecified;
local common = require "common"
local parse = require "parse"
local compile = require "compile"
local eval = require "eval"
local co = require "color-output"

local engine = 
   recordtype.define(
   {  _name=unspecified;			    -- for reference, debugging
      env=false;
      _id=unspecified;
      --
      encode=false;
      encode_function=false;
      expression=false;
      pattern=false;
      --
      id=false;
      lookup=false;
      clear=false;
      name=false;
      output=false;

      match_=false;

      match=false;
      eval=false;
      grep=false;
      configure=false;
      inspect=false;
      --
      compile=false;
      compile_match_exp=false;
  },
   "engine"
)

engine.tostring_function = function(orig, e)
			      return '<engine: '..tostring(e._name)..' ('.. e._id ..')>'; end

local locale = lpeg.locale()

local function engine_error(e, msg)
   error(string.format("Engine %s (%s): %s", e._name, e._id, tostring(msg)), 0)
end

local function no_pattern(e)
   engine_error(e, "no pattern configured")
end

local function no_encode(e)
   engine_error(e, "no encode configured")
end

----------------------------------------------------------------------------------------

local encode_table =
   {json = json.encode,
    color = co.color_string_from_leaf_nodes,
    nocolor = co.string_from_leaf_nodes,
    fulltext = common.match_to_text,
    [false] = function(...) return ...; end
 }

local function name_to_encode(name)
   return encode_table[name]
end

local function encode_to_name(fcn)
   for k,v in pairs(encode_table) do
      if v==fcn then return k; end
   end
   return "<unknown encode type>"
end

----------------------------------------------------------------------------------------

local function engine_configure(e, configuration)
   for k,v in pairs(configuration) do
      if k=="expression" then
	 local pat, msg = compile.compile_match_expression(v, e.env)
	 if not pat then return false, msg; end
	 e.expression = v
	 e.pattern = pat
      elseif k=="encode" then
	 local f = name_to_encode(v)
	 if type(f)~="function" then
	    return false, 'invalid value for encode: "' .. tostring(v) .. '"'
	 else
	    e.encode = v
	    e.encode_function = f
	 end
      elseif k=="name" then
	 e._name = tostring(v)
      else
	 return false, 'invalid configuration parameter: ' .. tostring(k)
      end
   end -- for each configuration key/value
   return true
end

local function engine_inspect(e)
   return {name=e._name, expression=e.expression, encode=e.encode, id=e._id}
end

local function engine_match_(e, pat, input, start)
   local result, nextpos = (pat.peg * lpeg.Cp()):match(input, start)
   if result then
      return (e.encode_function(result)), nextpos;
   else
      return false, 1;
   end
end

-- TODO: Memoize recent expressions.  But must invalidate the cache if env has changed.
-- TODO: Refactor _match, _eval, and _grep which can share code.
-- returns matches, nextpos
local function engine_match(e, expression, input, start)
   start = start or 1
   if type(expression)~="string" then error("Expression not a string: " .. tostring(expression)); end
   if type(input)~="string" then error("Input not a string: " .. tostring(input)); end
--   print("In engine_match, about to compile: " .. expression .. "\nto match: " .. input)
   local pat, msg = compile.compile_match_expression(expression, e.env)
   if not pat then error(msg); end
   return engine_match_(e, pat, input, start)
end

-- returns matches, nextpos, trace
local function engine_eval(e, expression, input, start)
   if type(expression)~="string" then error("Expression not a string: " .. tostring(expression)); end
   if type(input)~="string" then error("Input not a string: " .. tostring(input)); end
   local pat, msg = compile.compile_match_expression(expression, e.env)
   if not pat then error(msg); end
   return eval.eval(pat, input, start, e.env, false)
end

-- Having a grep function is a convenience.  It doesn't need to be here, but it's parallel in
-- function to match and eval, plus until we implement macros/functions, it saves users the typing
-- needed to do it for themselves.
-- returns matches, nextpos
local function engine_grep(e, expression, input, start)
   if type(expression)~="string" then error("Expression not a string: " .. tostring(expression)); end
   if type(input)~="string" then error("Input not a string: " .. tostring(input)); end
   local pat, msg = grep.pattern_EXP_to_grep_pattern(expression, e.env)
   if not pat then error(msg); end
   return engine_match_(e, pat, input, start)
end

----------------------------------------------------------------------------------------

local function reconstitute_pattern_definition(id, p)
   if p then
      return ( (p.original_ast and parse.reveal_ast(p.original_ast)) or
	       (p.ast and parse.reveal_ast(p.ast)) or
	        "// built-in RPL pattern //" )
   end
   error("undefined identifier: " .. id)
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
   if type(f)~="function" then error("Output encoder not a function: " .. tostring(f)); end
   en.encode_function = f
end

engine.create_function =
   function(_new, name, initial_env)
      initial_env = initial_env or common.new_env()
      -- assigning a unique instance id should be part of the recordtype module
      local params = {_name=name,
		      env=initial_env,
		      -- setting expression causes pattern to be set
		      expression="<uninitialized>",
		      pattern=false,
		      -- setting encode causes encode_function to be set
		      encode=false,
		      encode_function=name_to_encode(false),
		      -- functions
		      lookup=get_environment,
		      clear=clear_environment,
		      id=function(en) return en._id; end,
		      name=function(en) return en._name; end,
		      output=get_set_encoder_function,

		      match_=engine_match_,

		      match=engine_match,
		      grep=engine_grep,
		      eval=engine_eval,
		      configure=engine_configure,
		      inspect=engine_inspect}
      local idstring = tostring(params):match("0x(.*)") or "id/err"
      params._id = idstring
      return _new(params)
   end

-- recordtype package defines a creator function that is named after the record type name
engine_module.new = engine
engine_module.is = engine.is

return engine_module
