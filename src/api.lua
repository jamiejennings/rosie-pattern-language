---- -*- Mode: Lua; -*-                                                                           
----
---- api.lua     Rosie API for external use via C library and libffi
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local lapi = require "lapi"
local manifest = require "manifest"
require "list"

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

--
--  Rosie API:
--
--      - Managing the environment
--        + Obtain/destroy/ping a Rosie engine
--        - FUTURE: Enable/disable informational logging and warnings to stderr
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
--  FUTURE:
--        - Human interaction / debugging
--          - CRUD on color assignments for color output?
-- 

----------------------------------------------------------------------------------------
-- Note: NARGS is the number of args to pass to each api function

local api = {API_VERSION = "0.99a",		    -- api version
	     RPL_VERSION = "0.99a",		    -- language version
	     ROSIE_VERSION = ROSIE_VERSION,	    -- code revision level
	     ROSIE_HOME = ROSIE_HOME,		    -- install directory
             HOSTNAME = os.getenv("HOSTNAME"),
             HOSTTYPE = os.getenv("HOSTTYPE"),
             OSTYPE = os.getenv("OSTYPE"),
	     NARGS = {}} 			    -- number of args for each api call


----------------------------------------------------------------------------------------

-- SLOW due to table manipulation??   !@#
local function api_wrap(f)
   api.NARGS[f] = debug.getinfo(f, "u").nparams	    -- number of args for f
   return function(...)
	     local retvals = { pcall(f, ...) }
	     if #retvals<=2 then
		return retvals[1], json.encode(retvals[2])
	     else
		return retvals[1], json.encode({ table.unpack(retvals, 2) })
	     end
	  end
end

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

----------------------------------------------------------------------------------------
-- API and other version information

local function version()
   local info = {}
   for k,v in pairs(api) do
      if (type(k)=="string") and (type(v)=="string") then
	 info[k] = v
      end
   end -- loop
   return info
end


api.version = api_wrap(version)

----------------------------------------------------------------------------------------
-- Managing the environment (collection of engines)
----------------------------------------------------------------------------------------

engine_list = {}

local function engine_from_id(id)
   return engine_list[id] or arg_error("invalid engine id: " .. tostring(id))
end

local function delete_engine(id)
   engine_list[id] = nil;
end

api.delete_engine = api_wrap(delete_engine)

local function inspect_engine(id)
   return lapi.inspect_engine(engine_from_id(id))
end

api.inspect_engine = api_wrap(inspect_engine)

local function new_engine(name)			    -- optional manifest? file list? code string?
   if type(name)~="string" then
      arg_error("engine name not a string")
   end
   local en = engine(name)
   if engine_list[en.id] then
      error("Internal error: duplicate engine ids: " .. en.id)
   end
   engine_list[en.id] = en
   return en.id
end

api.new_engine = api_wrap(new_engine)

local function get_env(id)
   return compile.flatten_env((engine_from_id(id)).env)
end

api.get_environment = api_wrap(get_env)

local function clear_env(id)
   (engine_from_id(id)).env = compile.new_env()
end

api.clear_environment = api_wrap(clear_env)

local function get_binding(id, identifier)
   return lapi.get_binding(engine_from_id(id), identifier)
end

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

local function load_manifest(id, manifest_file)
   local en = engine_from_id(id)
   -- N.B. process_manifest does the compute_full_path calculation
   if type(manifest_file)~="string" then
      arg_error("manifest filename not a string")
   end
   local ok, msg = manifest.process_manifest(en, manifest_file)
   if not ok then error(msg, 0)
   else return msg				    -- msg may contain warnings
   end
end

api.load_manifest = api_wrap(load_manifest)

local function load_file(id, path)
   local en = engine_from_id(id)
   if type(path)~="string" then
      arg_error("path not a string")
   end
   local full_path = common.compute_full_path(path)
   local result, msg = compile.compile_file(full_path, en.env)
   if result then
      return full_path
   else
      error(msg,0)
   end
end

api.load_file = api_wrap(load_file)

local function load_string(id, input)
   local en = engine_from_id(id)
   if type(input)~="string" then
      arg_error("input not a string")
   end
   local pat, msg = compile.compile(input, en.env)
   if not pat then error(msg, 0)
   else return msg				    -- msg could contain warnings
   end
end

api.load_string = api_wrap(load_string)

-- return a human-readable definition of identifier (reconstituted from its ast)
local function get_binding(id, identifier)
   local en = engine_from_id(id);
   if type(identifier)~="string" then
      arg_error("identifier argument not a string")
   end
   return lapi.get_binding(en, identifier)
end

api.get_binding = api_wrap(get_binding)

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

local encoder_table =
   {json = json.encode,
    color = color_string_from_leaf_nodes,
    text = function(t) local k,v = next(t); assert(type(v)=="table"); return (v and v.text) or ""; end,
 }

local function name_to_encoder(name)
   return encoder_table[name]
end

local function encoder_to_name(fcn)
   for k,v in pairs(encoder_table) do
      if v==fcn then return k; end
   end
   return "<unknown>"
end

local function configure_engine(id, c_string)
   local en = engine_from_id(id)
   if type(c_string)~="string" then
      arg_error("configuration argument not a string")
   end
   local ok, c_table = pcall(json.decode, c_string)
   if (not ok) or type(c_table)~="table" then
      arg_error("configuration argument not a JSON object")
   end
   local ok, msg = lapi.configure_engine(en, c_table)
   if not ok then error(msg, 0); end
   return nil
end

api.configure_engine = api_wrap(configure_engine)
   
local function match(id, input_text, start)
   local en = engine_from_id(id)
   if type(input_text)~="string" then
      arg_error("input argument not a string")
   end
   return lapi.match(en, input_text, start)
end

api.match = api_wrap(match)

local function match_file(id, infilename, outfilename, errfilename)
   return lapi.match_file((engine_from_id(id)), infilename, outfilename, errfilename)
end

api.match_file = api_wrap(match_file)

local function eval_(id, input_text, start)
   local en = engine_from_id(id)
   if type(input_text)~="string" then
      arg_error("input argument not a string")
   end
   return lapi.eval(en, input_text, start)
end

api.eval = api_wrap(eval_)

local function eval_file(id, infilename, outfilename, errfilename)
   return lapi.eval_file(engine_from_id(id), infilename, outfilename, errfilename)
end

api.eval_file = api_wrap(eval_file)

local function set_match_exp_grep_TEMPORARY(id, pattern_exp)
   return lapi.set_match_exp_grep_TEMPORARY(engine_from_id(id), pattern_exp)
end   

api.set_match_exp_grep_TEMPORARY = api_wrap(set_match_exp_grep_TEMPORARY)

-- api_wrap will fill in the number of args that each api function takes, but (obviously) only
-- for the wrapped functions.  This loop catches the rest:

for name, thing in pairs(api) do
   if type(thing)=="function" then
      if not api.NARGS[thing] then
	 local info = debug.getinfo(thing, "u")
	 if info.isvararg=="true" then
	    error("Error loading api: vararg function found: " .. name)
	 else
	    api.NARGS[thing] = info.nparams
	 end
      end -- no NARGS entry
   end -- for each function
end

return api
