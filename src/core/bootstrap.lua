---- -*- Mode: Lua; -*-                                                                           
----
---- bootstrap.lua      Bootstrap Rosie by using the native Lua parser to parse rpl-core
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TODO:
--
-- + ROSIE_HOME is a real global now, no need to set it e.g. lapi.home
-- How best to set ROSIE_HOME so that rosie.lua will work?  Should it be the same as DESTDIR, e.g. "/usr/local"?
-- Write a real loader that checks for .luac first
-- Return not lapi but a better rosie engine interface (in rosie.lua)
-- Change lpeg.setmaxstack() to return the current value instead of an error.
-- Prob need to change lpeg to support multiple instantiations like cjson does.



-- Ensure we can fit any current (up to 0x10FFFF) and future (up to 0xFFFFFFFF) Unicode code
-- points in a single Lua integer.
if (not math) then
   error("Internal error: math functions unavailable")
elseif (0xFFFFFFFF > math.maxinteger) then
   error("Internal error: max integer on this platform is too small")
end

-- Find the value of the environment variable "ROSIE_HOME", if it is defined
if not ((type(os)=="table") and (type(os.getenv)=="function")) then
   error("Internal error: os functions unavailable; cannot use getenv to find ROSIE_HOME")
end
local ok, value = pcall(os.getenv, "ROSIE_HOME")
if not ok then
   error("Internal error: bootstrap call to os.getenv failed")
end
if (not value) and (not ROSIE_HOME) then
   error("Cannot find ROSIE_HOME.  Exiting...")
end

-- Environment variable, when present, overrides the value of ROSIE_HOME that is calculated in the
-- shell script ('run') that launches Rosie.
SCRIPT_ROSIE_HOME = false;
if (value and not(value=="")) then
   SCRIPT_ROSIE_HOME=ROSIE_HOME
   ROSIE_HOME = value
end

-- Restrict Lua's search for modules and shared objects to just the Rosie install directory
--package.path = ROSIE_HOME .. "/bin/?.luac;" .. ROSIE_HOME .. "/src/core/?.lua;" .. ROSIE_HOME .. "/src/?.lua"
--package.cpath = ROSIE_HOME .. "/lib/?.so"

--io.stderr:write("* NOT LOADING STRICT *\n")
--require "strict"



local function print_rosie_info()
   local rosie_home_message = ((SCRIPT_ROSIE_HOME and " (from environment variable $ROSIE_HOME, which has precedence)") or
			       " (provided by the program that initialized Rosie)")
   print("Rosie run-time information:")
   print("  ROSIE_HOME = " .. ROSIE_HOME .. rosie_home_message)
   if SCRIPT_ROSIE_HOME then print("  ROSIE_HOME, as calculated in the Rosie run script, was: " .. SCRIPT_ROSIE_HOME); end
   print("  HOSTNAME = " .. (os.getenv("HOSTNAME") or ""))
   print("  HOSTTYPE = " .. (os.getenv("HOSTTYPE") or ""))
   print("  OSTYPE = " .. (os.getenv("OSTYPE") or ""))
end

module = {loaded = {}}
module.loaded.math = math
module.loaded.os = os

function require(name)
   return module.loaded[name] or error("Module " .. tostring(name) .. " not loaded")
end

local rosie_env = _ENV

-- TODO: add support for loading .luac files
function load_module(name, optional_subdir)
   local loud = false
   if loud then io.write("Loading " .. name .. "... "); end
   if module.loaded[name] then
      if loud then print("already loaded."); end
      return module.loaded[name]
   end
   optional_subdir = optional_subdir or "src/core"
   local path = ROSIE_HOME .. "/" .. optional_subdir .. "/" .. name .. ".lua"
   local thing, msg = loadfile(path, "t", rosie_env)
   if (not thing) then
      print("Error in bootstrap process: cannot load Rosie module '" .. name .. "' from " .. ROSIE_HOME)
      print("The likely cause is an improper value of the environment variable $ROSIE_HOME (see below).")
      if ROSIE_DEV then
	 print("Reported error was: " .. tostring(msg));
      else
	 print_rosie_info()
      end
      os.exit(-1)
   end -- if not ok
   module.loaded[name] = thing()
   if loud then print("done."); end
   return module.loaded[name]
end

-- TODO: Create a .so loader and add error checking
local json_loader = package.loadlib(ROSIE_HOME .. "/lib/cjson.so", "luaopen_cjson")
local initial_json = json_loader()
json = initial_json.new()
module.loaded.cjson = json
local lpeg_loader = package.loadlib(ROSIE_HOME .. "/lib/lpeg.so", "luaopen_lpeg")
lpeg = lpeg_loader()
module.loaded.lpeg = lpeg
local readline_loader = package.loadlib(ROSIE_HOME .. "/lib/readline.so", "luaopen_readline")
readline = readline_loader()
module.loaded.readline = readline


argparse = load_module("argparse", "submodules/argparse/src")
recordtype = load_module("recordtype")
util = load_module("util")
common = load_module("common")
list = load_module("list")
syntax = load_module("syntax")
parse = load_module("parse")
compile = load_module("compile")
eval = load_module("eval")
color_output = load_module("color-output")
engine = load_module("engine")

manifest = load_module("manifest")
grep = load_module("grep")
lapi = load_module("lapi");
api = load_module("api")

repl = load_module("repl")


----------------------------------------------------------------------------------------
-- Driver functions for RPL parser written in RPL
----------------------------------------------------------------------------------------



local function rosie_parse_without_error_check(str, pos, tokens)
   pos = pos or 1
   tokens = tokens or {}
   local nt, nextpos, state = ROSIE_ENGINE:match(str, pos)
   if (not nt) then return tokens; end
   local name, pos, text, subs = common.decode_match(nt)
   table.move(subs, 1, #subs, #tokens+1, tokens)    -- strip the 'rpl' off the top
   return rosie_parse_without_error_check(str, nextpos, tokens)
end


local function rosie_parse(str, pos, tokens)
   local astlist = rosie_parse_without_error_check(str, pos, tokens)
   local errlist = {};
   for _,a in ipairs(astlist) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   return list.map(syntax.top_level_transform, astlist), errlist, astlist
end

function parse_and_explain(source)
   assert(type(source)=="string", "Compiler: source argument is not a string: "..tostring(source))
   local astlist, errlist, original_astlist = rosie_parse(source)
   if #errlist~=0 then
      local msg = "Warning: syntax error reporting is limited at this time\n"
      for _,e in ipairs(errlist) do
	 msg = msg .. parse.explain_syntax_error(e, source) .. "\n"
      end
      return false, msg
   else -- successful parse
      return astlist, original_astlist
   end
end

----------------------------------------------------------------------------------------
-- Bootstrap operations
----------------------------------------------------------------------------------------

BOOTSTRAP_COMPLETE = false;
ROSIE_VERSION = nil;				    -- read from file VERSION
ROSIE_ENGINE = nil;				    -- the engine that will parse all the rpl files

function bootstrap()
   ROSIE_VERSION = common.read_version_or_die(ROSIE_HOME)
   
   -- During bootstrapping, we have to compile the rpl using the "core" compiler, and
   -- manually configure ROSIE_ENGINE without calling engine_configure.

   -- To bootstrap, we have to compile the Rosie rpl using the core parser/compiler

   -- Create a matching engine for processing Rosie Pattern Language files
   ROSIE_ENGINE = engine("RPL engine")
   compile.compile_core(ROSIE_HOME.."/src/rpl-core.rpl", ROSIE_ENGINE.env)
   local success, result = compile.compile_match_expression('rpl', ROSIE_ENGINE.env)
   if not success then error("Bootstrap error: could not compile rosie core rpl: " .. tostring(result)); end
   ROSIE_ENGINE.expression = 'rpl';
   ROSIE_ENGINE.pattern = success;
   ROSIE_ENGINE.encode = "null/bootstrap";
   ROSIE_ENGINE.encode_function = function(m) return m; end;
   -- skip the assignment below to leave the original parser in place
   if true then
      --print("In bootstrap, parse_and_explain is " .. tostring(parse_and_explain))
      compile.set_parser(parse_and_explain);
   end
   BOOTSTRAP_COMPLETE = true
end

bootstrap();
