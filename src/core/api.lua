---- -*- Mode: Lua; -*-                                                                           
----
---- api.lua     Rosie API for external use via C library and libffi
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local engine = require "engine"
local common = require "common"			    -- MOVE clear_env functionality into engine

local manifest = require "manifest"
local json = require "cjson"
local list = require "list"

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

-- One engine per Lua state, in order to be thread-safe.  Also, engines sharing a Lua state do not
-- share anything, so what is the benefit (beyond a small-ish savings of memory)?
default_engine = nil

----------------------------------------------------------------------------------------

local api = {ROSIE_VERSION = ROSIE_VERSION,	    -- code revision level
	     ROSIE_HOME = ROSIE_HOME,		    -- install directory
             HOSTNAME = os.getenv("HOSTNAME"),
             HOSTTYPE = os.getenv("HOSTTYPE"),
             OSTYPE = os.getenv("OSTYPE"),
	     SIGNATURE = {}} 			    -- args and return types for each api call

-- If we wanted to do what the Makefile does, in order to report the same result (e.g. "Darwin" vs
-- "darwin15"), we could use this:
-- 
-- result, status code = util.os_execute_capture("/bin/bash -c '(uname -o || uname -s) 2> /dev/null'")
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
   
local hidden = {}
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

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

local function reconstitute_pattern_definition(id, p)
   if p then
      return ( --((p.alias and "alias ") or "") .. id .. " = " ..
	       ((p.original_ast and parse.reveal_ast(p.original_ast)) or
	        (p.ast and parse.reveal_ast(p.ast)) or
	      "// built-in RPL pattern //"))
   else
      error("undefined identifier: " .. id)
   end
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
-- Managing the environment
----------------------------------------------------------------------------------------

local function initialize()
   if default_engine then error("Engine already created", 0); end
   default_engine = engine.new("<anonymous>")
   return default_engine._id			    -- may be useful for client-side logging?
end

api.initialize = api_wrap_only(initialize, "string")

local function finalize(id)
   default_engine = nil;
end

api.finalize = api_wrap_only(finalize)

local function inspect_engine()
   if not engine.is(default_engine) then arg_error("not an engine: " .. tostring(default_engine)); end
   local info = default_engine:inspect()
   -- sanity check on what we are returning externally
   if type(info)~="table" then
      error("Internal error: invalid response from engine inspection: " .. tostring(info), 0)
   end
   return json.encode(info)
end

api.inspect_engine = api_wrap(inspect_engine, "object")

-- INEFFICIENT
local function get_env(optional_identifier)
   local en = default_engine
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local ok, identifier = pcall(json.decode, optional_identifier)
   if (not ok) then
      arg_error("could not decode argument (not json format): " .. tostring(optional_identifier))
   elseif (identifier==json.null) then
      identifier = nil
   elseif type(identifier)~="string" then
      arg_error("identifier not a json string (or json null)")
   end
   local env = common.flatten_env(en.env)
   for id, info in pairs(env) do
      local val = en.env[id]
      if not(pattern.is(val)) then
	 error("Internal error: object in environment not a pattern: " .. tostring(val))
      end
      info.binding = reconstitute_pattern_definition(id, val)
   end -- for every id in the flattened env
   local e
   if identifier then e = env[identifier]; else e = env; end
   if e and (type(e)~="table") then
      error("Internal error: invalid response from engine env: " .. tostring(e), 0)
   end
   return json.encode(e)
end

api.get_environment = api_wrap(get_env, "object")

local function clear_env(optional_identifier)
   local en = default_engine
   local retval = false
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local ok, identifier = pcall(json.decode, optional_identifier)
   if (not ok) then
      arg_error("identifier not a json string (or json null)")
   elseif (identifier==json.null) then
      identifier = nil
   elseif type(identifier)~="string" then
      arg_error("identifier not a json string (or json null)")
   end
   if identifier then
      if en.env[identifier] then
	 en.env[identifier] = nil
	 retval = true
      end
   else
      -- clear the entire environment
      en.env = common.new_env()
      retval = true
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
   return full_path, table.unpack(messages)
end

api.load_manifest = api_wrap(load_manifest, "string", "string*")

local function load_file(path)
   local en = default_engine
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end

   -- MOVE THIS TO ENGINE
   local retvals
   if type(path)~="string" then arg_error("path not a string: " .. tostring(path)); end
   local full_path, msg = common.compute_full_path(path, nil, ROSIE_HOME)
   if not full_path then
      retvals = { false, msg };
   else
      local input, msg = util.readfile(full_path)
      if not input then
	 retvals = { false, msg };
      else
	 local result, messages = compile.compile_source(input, en.env)
	 retvals = { result, common.compact_messages(messages), full_path }
      end
   end
   local ok, messages, full_path = table.unpack(retvals)
   check_results(ok, messages, full_path)
   return full_path, table.unpack(messages)
end

api.load_file = api_wrap(load_file, "string", "string*")

local function load_string(input)
   local en = default_engine
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end

   if type(input)~="string" then
      arg_error("input not a string")
   end

   local results, messages = compile.compile_source(input, en.env)
   messages = common.compact_messages(messages)

   check_results(results, messages, "dummy")
   return table.unpack(messages)
end

api.load_string = api_wrap(load_string, "string*")

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

local function configure_engine(config_obj)
   local en = default_engine
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(config_obj)~="string" then
      arg_error("configuration argument not a string")
   end
   local ok, c_table = pcall(json.decode, config_obj)
   if (not ok) or type(c_table)~="table" then
      arg_error("configuration argument not a JSON object")
   end
   
   local ok, msg = en:configure(c_table)
   if not ok then error(msg, 0); end
   return nil
end

api.configure_engine = api_wrap(configure_engine)
   
local function match(input_text, optional_start)
   local en = default_engine
   if type(input_text)~="string" then
      arg_error("input argument not a string")
   end
   if optional_start then
      optional_start = tonumber(optional_start)
      if not optional_start then
	 arg_error("start position argument not coercible to a number")
      end
   end
   local result, nextpos = en:match(input_text, optional_start)
   return result, tostring(#input_text - nextpos + 1)
end

api.match = api_wrap(match, "string", "int")	    -- string depends on encoder function

local function match_file(infilename, outfilename, errfilename, wholefileflag)
   local en = default_engine
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if (wholefileflag and type(json.decode(wholefileflag))~="boolean") then
      arg_error("whole file flag not a boolean: " .. json.decode(wholefileflag))
   end
   local i,o,e = en:match_file(infilename, outfilename, errfilename, wholefileflag)
   if (not i) then error(o,0); end
   return json.encode{i, o, e}
end

api.match_file = api_wrap(match_file, "int", "int", "int")

local function eval_(input_text, start)
   local en = default_engine
   if type(input_text)~="string" then
      arg_error("input argument not a string")
   end

   local result, nextpos, trace = en:eval(input_text, start)
   local leftover = 0;
   if nextpos then leftover = (#input_text - nextpos + 1); end
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
   local en = default_engine
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local i,o,e = en:eval_file(infilename, outfilename, errfilename, wholefileflag)
   if (not i) then error(o,0); end
   return json.encode{i, o, e}
end

api.eval_file = api_wrap(eval_file, "int", "int", "int")

local function set_match_exp_grep_TEMPORARY(pattern_exp)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(pattern_exp)~="string" then arg_error("pattern expression not a string"); end
   local pat, msg = grep.pattern_EXP_to_grep_pattern(pattern_exp, en.env);
   if pattern.is(pat) then
      en.expression = "grep(" .. pattern_exp .. ")"
      en.pattern = pat
      return en:configure_engine({encode=encoder_name})
   else
      arg_error(msg)
   end
end   

api.set_match_exp_grep_TEMPORARY = api_wrap(set_match_exp_grep_TEMPORARY)

---------------------------------------------------------------------------------------------------
-- Generate C code for librosie

function gen_version(api)
   local str = ""
   for k,v in pairs(api) do
      if (type(k)=="string") and (type(v)=="string") then
	 str = str .. string.format("#define ROSIE_%s %q\n", k, v)
      end
   end
   return str
end

-- function gen_constant(name, spec)
--    -- #define ROSIE_API_name code
--    local const = "ROSIE_API_" .. name
--    assert(type(spec.code)=="number")
--    return "#define " .. const .. " " .. tostring(spec.code)
-- end

local function prefix(str) return "rosieL_"..str; end
   
function gen_prototype(name, spec)
   local p = "struct rosieL_stringArray " .. prefix(name) .. "("
   local arglist = "void *L"
   for _,arg in ipairs(spec.args) do
      arglist = arglist .. ", struct rosieL_string *" .. arg
   end
   return p .. arglist .. ")"
end

function gen_top_message()
   local info = debug.getinfo(2, "n")
   local caller = info.name or "'anonymous function'"
   local fmt = [=[/* The code below was auto-generated by %s in api.lua.  DO NOT EDIT!
 * © Copyright IBM Corporation 2016.
 * LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
 * AUTHOR: Jamie A. Jennings
 */

]=]
   return string.format(fmt, caller)
end
      
function gen_C_HEADER(api)
   local str = gen_top_message()
   -- str = str .. gen_constant("FIRST_CODE", {code=enumeration_counter}) .. "\n";
   -- for k,v in pairs(signature) do str = str .. gen_constant(k,v) .. "\n"; end
   -- str = str .. "\n"
   str = str .. gen_version(api) .. "\n"
   for k,v in pairs(api.SIGNATURE) do str = str .. gen_prototype(k,v) .. ";\n"; end
   str = str .. "\n/* end of generated code */\n"
   return str
end

function write_C_HEADER(basefilename)
   local h, err = io.open(basefilename..".h", "w")
   if not h then error(err); end
   h:write(gen_C_HEADER(api))
   h:close()
end

-- struct rosieL_stringArray configure_engine(void *L, struct rosieL_string *config) {
--      prelude(L, "configure_engine");
--      push(L, config);
--      return call_api(L, "configure_engine", 1);
-- }

function gen_C_function(name, spec)
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

function gen_C_FUNCTIONS(api)
   local str = gen_top_message()
   for name, spec in pairs(api.SIGNATURE) do
      str = str .. gen_C_function(name, spec)
   end
   str = str .. "\n/* end of generated code */\n"
   return str
end

function write_C_FUNCTIONS(basefilename)
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
