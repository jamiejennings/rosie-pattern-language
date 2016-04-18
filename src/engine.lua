---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a Lua object that has state as follows:
--   env: environment of defined patterns
--   config: various configuration settings, including the default pattern to match
--   id: a string meant to be a unique identifier (currently unique in the Lua state)

local compile = require "compile"
local recordtype = require("recordtype")
local unspecified = recordtype.unspecified;

engine = 
   recordtype.define(
   {  name=unspecified;				    -- for reference, debugging
      env=false;
      config=false;
      id=unspecified;
      --
      match=false;
      configure=false;
      inspect=false;
      match_using_exp=false;
  },
   "engine"
)

engine.tostring_function = function(orig, e)
			      return '<engine: '..tostring(e.name)..' ('.. e.id ..')>'; end

local locale = lpeg.locale()

local function identity_function(...) return ...; end

local function engine_error(e, msg)
   error(string.format("Engine %s (%s): %s", e.name, e.id, tostring(msg)), 0)
end

local function engine_configure(e, configuration)
   assert(type(configuration)=="table", "engine configuration not a table: " .. tostring(configuration))
   if configuration.expression then
      e.config.expression = configuration.expression
      local pat, msg = compile.compile_command_line_expression(configuration.expression, e.env)
      if not pat then engine_error(msg); end
      e.config.pattern = pat
   end
   if configuration.encoder then
      e.config.encoder = configuration.encoder
   end
end

local function engine_inspect(e)
   return e.name, copy_table(e.config)
end

local function engine_match(e, input, start)
   start = start or 1
   local encode = e.config.encoder or identity_function
   if not e.config.pattern then engine_error(e, "no pattern configured"); end
   local result, nextpos = compile.match_peg(e.config.pattern.peg, input, start)
   if result then return (encode(result)), nextpos;
   else return false, 0; end
end

local function engine_match_using_exp(e, exp, input, start, encoder_fn)
   engine_configure(e, {expression=exp, encoder=encoder_fn})
   start = start or 1
   local encode = e.config.encoder or identity_function
   local result, nextpos = compile.match_peg(e.config.pattern.peg, input)
   if result then return (encode(result)), nextpos;
   else return false, 0; end
end

engine.create_function =
   function(_new, name, initial_env)
      initial_env = initial_env or compile.new_env()
      -- assigning a unique instance id should be part of the recordtype module
      local id = tostring({}):match("0x(.*)") or "id/err"
      return _new{name=name,
		  env=initial_env,
		  id=id,
		  config={},
		  match=engine_match,
		  configure=engine_configure,
		  inspect=engine_inspect,
		  match_using_exp=engine_match_using_exp}
   end

