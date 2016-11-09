---- -*- Mode: Lua; -*-                                                                           
----
---- bootstrap.lua      Bootstrap Rosie by using the native Lua parser to parse rpl-core
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

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
local SCRIPT_ROSIE_HOME
if (value and not(value=="")) then
   SCRIPT_ROSIE_HOME=ROSIE_HOME
   ROSIE_HOME = value
end

-- Restrict Lua's search for modules and shared objects to just the Rosie install directory
package.path = ROSIE_HOME .. "/bin/?.luac;" .. ROSIE_HOME .. "/src/core/?.lua;" .. ROSIE_HOME .. "/src/?.lua"
package.cpath = ROSIE_HOME .. "/lib/?.so"

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

local function load_module(name)
   local ok, thing = pcall(require, name)
   if (not ok) then
      print("Error in bootstrap process: cannot load Rosie module '" .. name .. "' from " .. ROSIE_HOME)
      print("The likely cause is an improper value of the environment variable $ROSIE_HOME (see below).")
      --print("Reported error was: " .. tostring(thing))
      print_rosie_info()
      os.exit(-1)
   end
   return thing
end

parse = load_module("parse")
syntax = load_module("syntax")
compile = load_module("compile")
common = load_module("common")
load_module("engine")
load_module("os")


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
   return map(syntax.top_level_transform, astlist), errlist, astlist
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

function bootstrap()
   ROSIE_VERSION = common.read_version_or_die()
   
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
      compile.parser = parse_and_explain;
   end
   BOOTSTRAP_COMPLETE = true
end

bootstrap();
