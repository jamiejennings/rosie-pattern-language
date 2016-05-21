---- -*- Mode: Lua; -*-                                                                           
----
---- lua_api.lua     Rosie API in Lua, for Lua programs
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local common = require "common"
local compile = require "compile"
require "engine"
local manifest = require "manifest"
local json = require "cjson"
local eval = require "eval"
require "color-output"

-- temporary:
require "grep"
lpeg = require "lpeg"
Cp = lpeg.Cp

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

--
--    Consolidated Rosie API
--
--      - Managing the environment
--        + Obtain/destroy/ping a Rosie engine
--        - Enable/disable informational logging and warnings to stderr
--            (Need to change QUIET to logging level, and make it a thread-local
--            variable that can be set per invocation of the parser/compiler/etc.)
--
--      + Rosie engine functions
--        + RPL related
--          + RPL statement (incremental compilation)
--          + RPL file compilation
--          + RPL manifest processing
--          + Get a copy of the engine environment
--          + Get identifier definition (human readable, reconstituted)
--
--        + Match related
--          + match pattern against string
--          + match pattern against file
--          + eval pattern against string
--          + eval pattern against file
--
--        - Human interaction / debugging
--          - CRUD on color assignments for color output?
-- 

----------------------------------------------------------------------------------------
-- Note: NARGS is the number of args to pass to each api function

local lua_api = {API_VERSION = "0.96 alpha",	    -- api version
                 RPL_VERSION = "0.96",		    -- language version
                 ROSIE_VERSION = ROSIE_VERSION,	    -- code revision level
	         ROSIE_HOME = ROSIE_HOME,	    -- install directory
	         NARGS = {}} 			    -- number of args for each api call
----------------------------------------------------------------------------------------

engine_list = {}

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

local function engine_from_id(id)
   if type(id)~="string" then
      arg_error("engine id not a string")
   end
   local en = engine_list[id]
   if (not engine.is(en)) then
      arg_error("invalid engine id")
   end
   return en
end

local function pcall_wrap(f)
   return function(...)
	     return pcall(f, ...)
	  end
end

function lua_api.version(verbose)
   if (not verbose) then
      return lua_api.API_VERSION
   else
      local info = {}
      for k,v in pairs(lua_api) do
	 if (type(k)=="string") and (type(v)=="string") then
	    info[k] = v
	 end
      end -- loop
      return info
   end -- switch on verbose
end

----------------------------------------------------------------------------------------
-- Managing the environment (engine functions)
----------------------------------------------------------------------------------------

function lua_api.delete_engine(id)
   if type(id)~="string" then
      arg_error("engine id not a string")
   end
   engine_list[id] = nil;
end

function lua_api.inspect_engine(id)
   local en = engine_from_id(id)
   local name, config = en:inspect()
   config.encoder = encoder_to_name(config.encoder)
   return name, config
end

function lua_api.new_engine(optional_name)	    -- optional manifest? file list? code string?
   optional_name = (optional_name and tostring(optional_name)) or "<anonymous>"
   local en = engine(optional_name, compile.new_env())
   if engine_list[en.id] then
      error("Internal error: duplicate engine ids: " .. en.id)
   end
   engine_list[en.id] = en
   return en.id
end

function lua_api.get_env(id)
   local en = engine_from_id(id)
   return compile.flatten_env(en.env)
end

function lua_api.clear_env(id)
   local en = engine_from_id(id)
   en.env = compile.new_env()
end

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

function lua_api.load_manifest(id, manifest_file)
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end		    -- en is a message in this case
   local ok, full_path = pcall(common.compute_full_path, manifest_file)
   if not ok then return false, full_path; end	    -- full_path is a message
   local result, msg = manifest.process_manifest(en, full_path)
   if result then
      return true, full_path
   else
      return false, msg
   end
end

function lua_api.load_file(id, path)
   -- paths not starting with "." or "/" are interpreted as relative to rosie home directory
   local en = engine_from_id(id)
   local full_path = common.compute_full_path(path)
   local result, msg = compile.compile_file(full_path, en.env)
   if result then
      return true, full_path
   else
      return false, msg
   end
end

function lua_api.load_string(id, input)
   local en = engine_from_id(id)
   local ok, msg = compile.compile(input, en.env)
   if ok then
      return true, msg				    -- msg may contain warnings
   else 
      return false, msg
   end
end

-- get a human-readable definition of identifier (reconstituted from its ast)
function lua_api.get_definition(engine_id, identifier)
   local en = engine_from_id(engine_id)
   if type(identifier)~="string" then
      arg_error("identifier argument not a string")
   end
   local val = en.env[identifier]
   if not val then
      error("undefined identifier", 0)
   else
      if pattern.is(val) then
	 return common.reconstitute_pattern_definition(identifier, val)
      else
	 error("Internal error: object in environment not a pattern: " .. tostring(val))
      end
   end
end

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

local encoder_table =
   {json = json.encode,
    color = color_string_from_leaf_nodes,
    text = function(t) local k,v = next(t); assert(type(v)=="table"); return (v and v.text) or ""; end,
 }

function name_to_encoder(name)
   return encoder_table[name]
end

function encoder_to_name(fcn)
   for k,v in pairs(encoder_table) do
      if v==fcn then return k; end
   end
   return "<unknown>"
end

function lua_api.configure(id, c)
   local en = engine_from_id(id)
   if type(c)~="table" then
      arg_error("configuration not a table: " .. tostring(c)); end
   c.encoder_function = name_to_encoder(c.encoder)
   if not c.encoder_function then
      arg_error("invalid encoder: " .. tostring(c.encoder));
   end
   return pcall(en.configure, en, c)
end

function lua_api.match(id, input_text, start)
   local result, nextpos = (engine_from_id(id)):match(input_text, start)
   return result, (#input_text - nextpos + 1)
end

function lua_api.match_file(id, infilename, outfilename, errfilename)
   return (engine_from_id(id)):match_file(infilename, outfilename, errfilename)
end

function lua_api.eval_(id, input_text, start)
   local en = engine_from_id(id)
   if type(input_text)~="string" then arg_error("input text not a string"); end
   local result, nextpos, trace = en:eval(input_text, start)
   local leftover = 0;
   if nextpos then leftover = (#input_text - nextpos + 1); end
   return result, leftover, trace
end

local function eval_file(id, infilename, outfilename, errfilename)
   local en = engine_from_id(id)
   return en:eval_file(infilename, outfilename, errfilename)
end

lua_api.eval_file, lua_api.NARGS.eval_file = pcall_wrap(eval_file)

local function set_match_exp_grep_TEMPORARY(id, pattern_exp)
   local en = engine_from_id(id)
   if type(pattern_exp)~="string" then arg_error("pattern expression not a string"); end
   en:configure({ pattern = pattern_EXP_to_grep_pattern(pattern_exp, en.env) })
end   

lua_api.set_match_exp_grep_TEMPORARY, lua_api.NARGS.set_match_exp_grep_TEMPORARY = pcall_wrap(set_match_exp_grep_TEMPORARY)

-- pcall_wrap will fill in the number of args that each api function takes, but (obviously) only
-- for the wrapped functions.  This loop catches the rest:

for name, thing in pairs(lua_api) do
   if type(thing)=="function" then
      if not lua_api.NARGS[name] then
	 local info = debug.getinfo(thing, "u")
	 if info.isvararg=="true" then
	    error("Error loading api: vararg function found: " .. name)
	 else
	    lua_api.NARGS[name] = info.nparams
	 end
      end -- no NARGS entry
   end -- for each function
end

return lua_api
