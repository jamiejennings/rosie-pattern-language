---- -*- Mode: Lua; -*-                                                                           
----
---- api.lua     Rosie API for external use via C library and libffi
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local lapi = require "lapi"
local manifest = require "manifest"
local json = require "cjson"
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

local api = {API_VERSION = "0.99b",		    -- api version
	     RPL_VERSION = "0.99a",		    -- language version
	     ROSIE_VERSION = ROSIE_VERSION,	    -- code revision level
	     ROSIE_HOME = ROSIE_HOME,		    -- install directory
             HOSTNAME = os.getenv("HOSTNAME"),
             HOSTTYPE = os.getenv("HOSTTYPE"),
             OSTYPE = os.getenv("OSTYPE"),
	     SIGNATURE = {}} 			    -- args and return types for each api call


----------------------------------------------------------------------------------------

-- local function encode_retvals(success, ...)
--    return success, json.encode({...})
-- end
-- local function encode_retvals(...)
--    return json.encode({...})
-- end
-- local function encode_retvals(...)
--    return map(tostring, {...})
-- end

local function get_arglist(f)
   local info = debug.getinfo(f, "u")
   local n, vararg = info.nparams, info.isvararg
   local arglist = {}
   for i=1,n do
      arglist[i] = debug.getlocal(f, i)
   end
   return arglist
end
   
local function api_wrap(f, ...)
   local returns = {...}
   local newf = function(...)
		   return { pcall(f, ...) }
		end
   api.SIGNATURE[newf] = {args=get_arglist(f), returns=returns}
   return newf
end

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

----------------------------------------------------------------------------------------
-- API info, including version information
----------------------------------------------------------------------------------------

local function info()
   local info = {}
   for k,v in pairs(api) do
      if (type(k)=="string") and (type(v)=="string") then
	 info[k] = v
      end
   end -- loop
   return json.encode(info)
end

api.info = api_wrap(info, "object")

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
   local info = lapi.inspect_engine(engine_from_id(id))
   -- sanity check on what we are returning externally
   if type(info)~="table" then
      error("Internal error: invalid response from engine inspection: " .. tostring(info), 0)
   end
   return json.encode(info)
end

api.inspect_engine = api_wrap(inspect_engine, "object")

local function new_engine(config_obj)
   if type(config_obj)~="string" then
      arg_error("engine configuration not a json-encoded object")
   end
   local ok, c_table = pcall(json.decode, config_obj)
   if not ok then
      arg_error("engine configuration not a valid json object")
   end
   local en = engine("<anonymous>")
   local id = en.id
   if engine_list[id] then
      en.id = en.id .. os.tmpname():sub(-6)
      if engine_list[en.id] then
	 error("Internal error: duplicate engine ids: " .. en.id, 0)
      else
	 util.warn("duplicate engine ids: " .. id .. " --> " .. en.id)
      end
   end

   -- TEMPORARY: !@#  Making sure the C api will handle strings with nulls in them.
   en.id = en.id:sub(1,4) .. string.char(0) .. en.id:sub(5)

   engine_list[en.id] = en
   if (c_table~=json.null) then
      ok, msg = lapi.configure_engine(en, c_table)
      if not ok then arg_error(msg); end
   end
   return en.id
end

api.new_engine = api_wrap(new_engine, "string")

local function get_env(id, optional_identifier)
   local en = engine_from_id(id)
   local ok, identifier = pcall(json.decode, optional_identifier)
   if (not ok) then
      arg_error("identifier not a json string (or json null)")
   elseif (identifier==json.null) then
      identifier = nil
   elseif type(identifier)~="string" then
      arg_error("identifier not a json string (or json null)")
   end
   local e = lapi.get_environment(en, identifier)
   if e and (type(e)~="table") then
      error("Internal error: invalid response from engine env: " .. tostring(e), 0)
   end
   return json.encode(e)
end

api.get_environment = api_wrap(get_env, "object")

local function clear_env(id, optional_identifier)
   local en = engine_from_id(id)
   local ok, identifier = pcall(json.decode, optional_identifier)
   if (not ok) then
      arg_error("identifier not a json string (or json null)")
   elseif (identifier==json.null) then
      identifier = nil
   elseif type(identifier)~="string" then
      arg_error("identifier not a json string (or json null)")
   end
   local retval = lapi.clear_environment(en, identifier)
   if type(retval)~="boolean" then
      error("Internal error: invalid response from clear env: " .. tostring(retval), 0)
   end
   return json.encode(retval)
end

api.clear_environment = api_wrap(clear_env, "boolean")

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

local function check_results(ok, messages, full_path)
   if not ok then error(messages, 0); end
   if messages and (type(messages)~="table") then
      error("Internal error: invalid messages returned: " .. tostring(messages), 0)
   elseif (type(full_path)~="string") then
      error("Internal error: invalid path returned: " .. tostring(full_path), 0)
   end
end

local function load_manifest(id, manifest_file)
   local en = engine_from_id(id)
   -- N.B. process_manifest does the compute_full_path calculation
   if type(manifest_file)~="string" then
      arg_error("manifest filename not a string")
   end
   local ok, messages, full_path = manifest.process_manifest(en, manifest_file)
   check_results(ok, messages, full_path)
   return full_path, table.unpack(messages)
end

api.load_manifest = api_wrap(load_manifest, "string", "[string]*")

local function load_file(id, path)
   local en = engine_from_id(id)
   local ok, messages, full_path = lapi.load_file(en, path)
   check_results(ok, messages, full_path)
   return full_path, table.unpack(messages)
end

api.load_file = api_wrap(load_file, "string", "[string]*")

local function load_string(id, input)
   local en = engine_from_id(id)
   if type(input)~="string" then
      arg_error("input not a string")
   end
   local results, messages = lapi.load_string(en, input)
   check_results(results, messages, "dummy")
   return table.unpack(messages)
end

api.load_string = api_wrap(load_string, "[string]*")

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

local function configure_engine(id, config_obj)
   local en = engine_from_id(id)
   if type(config_obj)~="string" then
      arg_error("configuration argument not a string")
   end
   local ok, c_table = pcall(json.decode, config_obj)
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
   local m, leftover = lapi.match(en, input_text, start)
   return json.encode(m), tostring(leftover)
end

api.match = api_wrap(match, "string", "int")	    -- string depends on encoder function

local function match_file(id, infilename, outfilename, errfilename, wholefileflag)
   if (wholefileflag and type(json.decode(wholefileflag))~="boolean") then
      arg_error("whole file flag not a boolean: " .. json.decode(wholefileflag))
   end
   local i,o,e = lapi.match_file((engine_from_id(id)), infilename, outfilename, errfilename, wholefileflag)
   return tostring(i), tostring(o), tostring(e)
end

api.match_file = api_wrap(match_file, "int", "int", "int")

local function eval_(id, input_text, start)
   local en = engine_from_id(id)
   if type(input_text)~="string" then
      arg_error("input argument not a string")
   end
   local result, leftover, trace = lapi.eval(en, input_text, start)
   if (type(leftover)~="number") then
      error("Internal error: invalid return from eval (leftover): " .. tostring(leftover), 0)
   elseif (type(trace)~="string") then
      error("Internal error: invalid return from eval (trace): " .. tostring(trace), 0)
   end
   return json.encode(result), tostring(leftover), trace
end

api.eval = api_wrap(eval_, "string", "int", "string")

local function eval_file(id, infilename, outfilename, errfilename, wholefileflag)
   if (wholefileflag and type(json.decode(wholefileflag))~="boolean") then
      arg_error("whole file flag not a boolean: " .. json.decode(wholefileflag))
   end
   local i,o,e = lapi.eval_file(engine_from_id(id), infilename, outfilename, errfilename, wholefileflag)
   return tostring(i), tostring(o), tostring(e)
end

api.eval_file = api_wrap(eval_file, "int", "int", "int")

local function set_match_exp_grep_TEMPORARY(id, pattern_exp)
   return lapi.set_match_exp_grep_TEMPORARY(engine_from_id(id), pattern_exp)
end   

api.set_match_exp_grep_TEMPORARY = api_wrap(set_match_exp_grep_TEMPORARY)

-- api_wrap will fill in the number of args that each api function takes, but api_wrap does not
-- know the name of the function it is wrapping.  The loop below converts from function to name of
-- the function.  This loop also catches non-wrapped functions.

for name, thing in pairs(api) do
   if type(thing)=="function" then
      local info = debug.getinfo(thing, "u")
      if info.isvararg=="true" then
	 error("Error loading api: vararg function found: " .. name)
      end
      if api.SIGNATURE[thing] then
	 api.SIGNATURE[name] = api.SIGNATURE[thing]	    -- copy value set by api_wrap
	 api.SIGNATURE[thing] = nil
      else
	 --api.SIGNATURE[name] = get_arglist(thing)
	 error("Unwrapped function in external api: " .. name)
      end
   end -- for each function
end

return api
