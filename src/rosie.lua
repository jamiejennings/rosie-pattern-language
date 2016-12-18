---- -*- Mode: Lua; -*-                                                                           
----
---- rosie.lua    Usage: rosie = require "rosie"; rosie.initialize()
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TODO: Large overlap with bootstrap.lua, so reconcile these, and then devise a proper api for
-- the result of 'require "rosie"'.

os = require "os"

rosie = {}

local function load_module(name)
   local ok, thing = pcall(require, name)
   if (not ok) then
      print("Error in bootstrap process: cannot load Rosie module '" .. name .. "' from " .. ROSIE_HOME .. "/src")
      print("Reported error was: " .. tostring(thing))
      print_rosie_info()
      error()
   else
      return thing
   end
end

local function print_rosie_info()
   print("Rosie run-time information:")
   print("  ROSIE_HOME = " .. ROSIE_HOME)
   print("  HOSTNAME = " .. (os.getenv("HOSTNAME") or ""))
   print("  HOSTTYPE = " .. (os.getenv("HOSTTYPE") or ""))
   print("  OSTYPE = " .. (os.getenv("OSTYPE") or ""))
end

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

local function HOSTED_parse_and_explain(source)
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
      compile.parser = HOSTED_parse_and_explain;
   end
   BOOTSTRAP_COMPLETE = true
end


function rosie.initialize(optional_rosie_home)
   optional_rosie_home = optional_rosie_home or os.getenv("ROSIE_HOME")
   if not optional_rosie_home then
      error("Rosie: ROSIE_HOME not defined in environment, nor supplied as argument to initialize")
   end
   ROSIE_HOME = optional_rosie_home

   -- Add to Lua's search paths 
   package.path = ROSIE_HOME .. "/bin/?.luac;" .. ROSIE_HOME .. "/src/?.lua;" .. package.path
   package.cpath = ROSIE_HOME .. "/lib/?.so;" .. package.cpath

   parse = load_module("parse")
   syntax = load_module("syntax")
   compile = load_module("compile")
   common = load_module("common")
   load_module("engine")
   lapi = load_module("lapi")

   bootstrap();
   for k,v in pairs(lapi) do rosie[k] = v; end
end


return rosie

