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

-- One engine per Lua state, in order to be thread-safe.  Also, engines sharing a Lua state do not
-- share anything, so what is the benefit (beyond a small-ish savings of memory)?
local default_engine;

----------------------------------------------------------------------------------------

local api = {API_VERSION = "0.99b",		    -- api version
	     RPL_VERSION = "0.99a",		    -- language version
	     VERSION = ROSIE_VERSION,		    -- code revision level
	     HOME = ROSIE_HOME,			    -- install directory
             BUILD_HOSTNAME = os.getenv("HOSTNAME"),
             BUILD_HOSTTYPE = os.getenv("HOSTTYPE"),
             BUILD_OSTYPE = os.getenv("OSTYPE"),
	     BUILD_TIME = os.date(),
	     SIGNATURE = {}} 			    -- args and return types for each api call

----------------------------------------------------------------------------------------

local function get_arglist(f)
   local info = debug.getinfo(f, "u")
   local n, vararg = info.nparams, info.isvararg
   local arglist = {}
   for i=1,n do
      arglist[i] = debug.getlocal(f, i)
   end
   return arglist
end
   
local enumeration_counter = 681;
local function api_wrap(f, ...)
   local returns = {...}
   local newf = function(...)
		   return { pcall(f, ...) }
		end
   api.SIGNATURE[newf] = {args=get_arglist(f), returns=returns, code=enumeration_counter}
   enumeration_counter = enumeration_counter + 1;
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

-- engine_list = {}

-- local function engine_from_id(id)
--    return engine_list[id] or arg_error("invalid engine id: " .. tostring(id))
-- end

local function delete_engine(id)
   --   engine_list[id] = nil;
   default_engine = nil;
end

api.delete_engine = api_wrap(delete_engine)

local function inspect_engine()
   local info = lapi.inspect_engine(default_engine)
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

   if default_engine then error("Engine already created", 0); end

   local en = engine("<anonymous>")
   -- local id = en.id
   -- if engine_list[id] then
   --    en.id = en.id .. os.tmpname():sub(-6)
   --    if engine_list[en.id] then
   -- 	 error("Internal error: duplicate engine ids: " .. en.id, 0)
   --    else
   -- 	 util.warn("duplicate engine ids: " .. id .. " --> " .. en.id)
   --    end
   -- end

   -- -- TEMPORARY: !@#  Making sure the C api will handle strings with nulls in them.
   -- en.id = en.id:sub(1,4) .. string.char(0) .. en.id:sub(5)
   -- engine_list[en.id] = en

   if (c_table~=json.null) then
      ok, msg = lapi.configure_engine(en, c_table)
      if not ok then arg_error(msg); end
   end
   default_engine = en;
   return en.id					    -- may be useful for client-side logging?
end

api.new_engine = api_wrap(new_engine, "string")

local function get_env(optional_identifier)
   local en = default_engine
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

local function clear_env(optional_identifier)
   local en = default_engine
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
   return retval
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

local function load_manifest(manifest_file)
   local en = default_engine
   -- N.B. process_manifest does the compute_full_path calculation
   if type(manifest_file)~="string" then
      arg_error("manifest filename not a string")
   end
   local ok, messages, full_path = manifest.process_manifest(en, manifest_file)
   check_results(ok, messages, full_path)
   return full_path, (messages and table.unpack(messages)) or nil
end

api.load_manifest = api_wrap(load_manifest, "string", "string*")

local function load_file(path)
   local en = default_engine
   local ok, messages, full_path = lapi.load_file(en, path)
   check_results(ok, messages, full_path)
   return full_path, (messages and table.unpack(messages)) or nil
end

api.load_file = api_wrap(load_file, "string", "string*")

local function load_string(input)
   local en = default_engine
   if type(input)~="string" then
      arg_error("input not a string")
   end
   local results, messages = lapi.load_string(en, input)
   check_results(results, messages, "dummy")
   return (messages and table.unpack(messages)) or nil
end

api.load_string = api_wrap(load_string, "string*")

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

local function configure_engine(config_obj)
   local en = default_engine
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
   
local function match(input_text, start)
   local en = default_engine
   if type(input_text)~="string" then
      arg_error("input argument not a string")
   end
   local m, leftover = lapi.match(en, input_text, start)
   return m, tostring(leftover)
end

api.match = api_wrap(match, "string", "int")	    -- string depends on encoder function

local function match_file(infilename, outfilename, errfilename, wholefileflag)
   if (wholefileflag and type(json.decode(wholefileflag))~="boolean") then
      arg_error("whole file flag not a boolean: " .. json.decode(wholefileflag))
   end
   local i,o,e = lapi.match_file((default_engine), infilename, outfilename, errfilename, wholefileflag)
   if (not i) then error(o,0); end
   return json.encode{i, o, e}
end

api.match_file = api_wrap(match_file, "int", "int", "int")

local function eval_(input_text, start)
   local en = default_engine
   if type(input_text)~="string" then
      arg_error("input argument not a string")
   end
   local result, leftover, trace = lapi.eval(en, input_text, start)
   if (type(leftover)~="number") then
      error("Internal error: invalid return from eval (leftover): " .. tostring(leftover), 0)
   elseif (type(trace)~="string") then
      error("Internal error: invalid return from eval (trace): " .. tostring(trace), 0)
   end
   return result, tostring(leftover), trace
end

api.eval = api_wrap(eval_, "string", "int", "string")

local function eval_file(infilename, outfilename, errfilename, wholefileflag)
   if (wholefileflag and type(json.decode(wholefileflag))~="boolean") then
      arg_error("whole file flag not a boolean: " .. json.decode(wholefileflag))
   end
   local i,o,e = lapi.eval_file(default_engine, infilename, outfilename, errfilename, wholefileflag)
   if (not i) then error(o,0); end
   return json.encode{i, o, e}
end

api.eval_file = api_wrap(eval_file, "int", "int", "int")

local function set_match_exp_grep_TEMPORARY(pattern_exp)
   return lapi.set_match_exp_grep_TEMPORARY(default_engine, pattern_exp)
end   

---------------------------------------------------------------------------------------------------
-- Generate C code for librosie

function gen_version(api)
   local str = false
   for k,v in pairs(api) do
      if (type(k)=="string") and (type(v)=="string") then
	 if str then str = str .. "\n" else str="" end
	 str = str .. string.format("#define ROSIE_%s %q", k, v)
      end
   end
   return str
end

function gen_constant(name, spec)
   -- #define ROSIE_API_name code
   local const = "ROSIE_API_" .. name
   assert(type(spec.code)=="number")
   return "#define " .. const .. " " .. tostring(spec.code)
end

function gen_prototype(name, spec)
   -- struct stringArray name(...)
   local p = "struct stringArray " .. name .. "("
   local arglist = ""
   for _,arg in ipairs(spec.args) do
      if arglist~="" then arglist = arglist .. ", "; end
      arglist = arglist .. "struct string *" .. arg
   end
   return p .. arglist .. ");"
end

top_message = [=[
/* The code below was auto-generated by api.lua.  DO NOT EDIT!
 * © Copyright IBM Corporation 2016.
 * LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
 * AUTHOR: Jamie A. Jennings
 */

]=]
      
function gen_HEADER(api)
   local str = top_message
   for k,v in pairs(api) do str = str .. gen_constant(k,v) .. "\n"; end
   str = str .. "\n"
   for k,v in pairs(api) do str = str .. gen_prototype(k,v) .. "\n"; end
   str = str .. "\n/* end */\n"
   return str
end

--   local h, err = io.open(filename, "w")
--   if not h then error(err); end
--   h:write(gen_HEADER(api.SIGNATURE)); h:close()


---------------------------------------------------------------------------------------------------

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
