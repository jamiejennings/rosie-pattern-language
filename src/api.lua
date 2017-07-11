---- -*- Mode: Lua; -*-                                                                           
----
---- api.lua     Rosie API for external use via C library and libffi
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- To support the external foreign function API, this file is the only thing loaded into the Lua
-- environment.  Consequently, we can set a number of globals to facilitate development and
-- debugging.  Only the functions that end up in the api table (returned by this code) will become
-- part of the external API.

io = require "io"
debug = require "debug"

rosie = require "rosie"


recordtype = require "recordtype"
lpeg = require "lpeg"
json = require "cjson"

ROSIE_INFO = rosie.info()
ROSIE_HOME = ROSIE_INFO.ROSIE_HOME
ROSIE_LIB = ROSIE_INFO.ROSIE_LIB

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")
assert(ROSIE_LIB, "The path to the Rosie standard library, ROSIE_LIB, is not set")

----------------------------------------------------------------------------------------

local api = {SIGNATURE = {}} 			    -- args and return types for each api call

-- If we wanted to do what the Makefile does, in order to report the same result (e.g. "Darwin" vs
-- "darwin15"), we could use this:
-- 
-- result, status code = util.os_execute_capture("/bin/bash -c '(uname -o || uname -s) 2> /dev/null'")

-- One engine per Lua state, in order to be thread-safe.  Also, engines sharing a Lua state do not
-- share anything, so what is the benefit (beyond a small-ish savings of memory)?
api.ENGINE = nil

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
   
local hidden = {}	    -- names of functions that are wrapped but hidden from the visible API

local function api_wrap_f(f)
   return function(...)
	     return { pcall(f, ...) }
	  end
end

local function api_wrap_only(f)
   local newf = api_wrap_f(f)
   hidden[newf] = true;
   return newf
end

local function api_wrap(f, ...)
   local returns = {...}
   local newf = api_wrap_f(f)
   api.SIGNATURE[newf] = {args=get_arglist(f), returns=returns}
   return newf
end

-- TODO: Fix the many inefficiencies here:
local function default_engine_method_caller(method)
   return function(...)
	     if not api.ENGINE then error("rosie api not initialized", 0); end
	     local retvals = {api.ENGINE[method](api.ENGINE, ...)}
	     for i=1,#retvals do
		local v = retvals[i]
		if type(v)=="userdata" then v = lpeg.getdata(v); end
		if type(v)~="string" and type(v)~="boolean" then retvals[i]= json.encode(v); end
	     end
	     return table.unpack(retvals)
	  end
end

local function call_with_default_engine(fcn)
   return function(...)
	     if not api.ENGINE then error("rosie api not initialized", 0); end
	     return fcn(api.ENGINE, ...)
	  end
end

----------------------------------------------------------------------------------------
-- Rosie info
----------------------------------------------------------------------------------------

local function info()
   local info = rosie.info()
   -- Clear out the numeric indices, leaving just the string keys & values
   for i=1,#info do info[i]=nil; end
   return json.encode(info)
end

api.info = api_wrap(info, "object")

----------------------------------------------------------------------------------------
-- Managing the environment
----------------------------------------------------------------------------------------

-- TODO: Stash functions like default_engine:match in local variables so that we can use those
-- variables within default_engine_method_caller and call_with_default_engine.  Those functions
-- currently look up strings like "match" in the default_engine table on EVERY CALL.
local function initialize()
   if api.ENGINE then error("Engine already created", 0); end
   api.ENGINE = rosie.engine.new()
   api.ENGINE:output(rosie.encoders.json)	    -- always json, at least for now
   return api.ENGINE:id()			    -- may be useful for client-side logging?
end

api.initialize = api_wrap_only(initialize, "string")

local function finalize(id)
   api.ENGINE = nil;
end

api.finalize = api_wrap_only(finalize)

local function make_env_accessor(method)
   return function(encoded_identifier)
	     if not api.ENGINE then error("rosie api not initialized", 0); end
	     local ok, identifier = pcall(json.decode, encoded_identifier)
	     if not ok then error("argument not a json-encoded string: " .. tostring(encoded_identifier),0); end
	     if identifier==json.null then identifier = nil; end
	     return json.encode(api.ENGINE[method](api.ENGINE, identifier))
	  end
end

api.engine_lookup = api_wrap(make_env_accessor("lookup"), "object")
api.engine_clear = api_wrap(make_env_accessor("clear"), "boolean")

----------------------------------------------------------------------------------------
-- Loading files, strings
----------------------------------------------------------------------------------------

api.loadfile = api_wrap(default_engine_method_caller("loadfile"), "string*")
api.load = api_wrap(default_engine_method_caller("load"), "string*")

----------------------------------------------------------------------------------------
-- Compiling expressions
----------------------------------------------------------------------------------------

-- bind pat to a new unique id in engine en
local function gensym_bind(en, id_component, pat)
   local try
   repeat
      try = "G" .. id_component .. string.format("%04x", math.random(0xFFFF))
   until not lookup(en._env, try)
   bind(en._env, try, pat)
   pat.alias = false				    -- this is an assignment, not an alias
   return try
end

local function compile(expression, flavor)
   if not api.ENGINE then error("rosie api not initialized", 0); end
   -- compile method will throw an error if expression does not compile
   local r = api.ENGINE:compile(expression, flavor)
   -- Put the id into the environment
   return gensym_bind(api.ENGINE, recordtype.id(r), r._pattern)
end

api.compile = api_wrap(compile, "string")

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

-- TODO: ensure argument checking is being done correctly in the C api

-- TODO: add encoder arg
api.match = api_wrap(default_engine_method_caller("match"), "string", "int")
api.matchfile = api_wrap(default_engine_method_caller("matchfile"), "int", "int", "int")

api.tracematch = api_wrap(default_engine_method_caller("tracematch"), "string", "int", "string")
api.tracematchfile = api_wrap(default_engine_method_caller("tracematchfile"), "int", "int", "int")

---------------------------------------------------------------------------------------------------
-- Generate C code for librosie
----------------------------------------------------------------------------------------

local function gen_version(api)
   local str = ""
   for k,v in pairs(api) do
      if (type(k)=="string") and (type(v)=="string") then
	 str = str .. string.format("#define ROSIE_%s %q\n", k, v)
      end
   end
   return str
end

local function gen_prototype(name, spec)
   local p = "struct stringArray " .. name .. "("
   local arglist = "void *L"
   for _,arg in ipairs(spec.args) do
      arglist = arglist .. ", struct string *" .. arg
   end
   return p .. arglist .. ")"
end

local function gen_top_message()
   local info = debug.getinfo(2, "n")
   local caller = info.name or "'anonymous function'"
   local fmt = [=[/* The code below was auto-generated by %s in api.lua.  DO NOT EDIT!
 * © Copyright IBM Corporation 2016, 2017.
 * LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
 * AUTHOR: Jamie A. Jennings
 */

]=]
   return string.format(fmt, caller)
end
      
local function gen_C_HEADER(api)
   local str = gen_top_message()
   str = str .. gen_version(api) .. "\n"
   for k,v in pairs(api.SIGNATURE) do str = str .. gen_prototype(k,v) .. ";\n"; end
   str = str .. "\n/* end of generated code */\n"
   return str
end

local function write_C_HEADER(basefilename)
   local h, err = io.open(basefilename..".h", "w")
   if not h then error(err); end
   h:write(gen_C_HEADER(api))
   h:close()
end

-- struct stringArray configure_engine(void *L, struct string *config) {
--      prelude(L, "configure_engine");
--      push(L, config);
--      return call_api(L, "configure_engine", 1);
-- }

local function gen_C_function(name, spec)
   local str = gen_prototype(name, spec) .. "{\n"
   str = str .. string.format("    prelude(L, %q);\n", name)
   for _,arg in ipairs(spec.args) do
      str = str .. string.format("    push(L, %s);\n", arg)
   end
   str = str .. string.format("    return call_api(L, %q, %d);\n}\n\n",
			      name,
			      #spec.args)
   return str
end

local function gen_C_FUNCTIONS(api)
   local str = gen_top_message()
   for name, spec in pairs(api.SIGNATURE) do
      str = str .. gen_C_function(name, spec)
   end
   str = str .. "\n/* end of generated code */\n"
   return str
end

local function write_C_FUNCTIONS(basefilename)
   local h, err = io.open(basefilename..".c", "w")
   if not h then error(err); end
   h:write(gen_C_FUNCTIONS(api))
   h:close()
end

function api.write_C_FILES()
   local fn = "librosie_gen"
   write_C_HEADER(fn)
   write_C_FUNCTIONS(fn)
end
hidden[api.write_C_FILES] = true;

---------------------------------------------------------------------------------------------------

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
      elseif not hidden[thing] then
	 error("Unwrapped function in external api: " .. name)
      end
   end -- for each function
end

return api
