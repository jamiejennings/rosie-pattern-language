-- -*- Mode: Lua; -*-                                                                             
--
-- load-modules.lua   Custom loader for Rosie modules
--
-- © Copyright IBM Corporation 2016.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- TODO: add support for loading .luac files
-- TODO: Create a .so loader and add error checking

----------------------------------------------------------------------------------------
-- Check for prerequisite conditions before loading any code
----------------------------------------------------------------------------------------
assert(type(ROSIE_HOME)=="string", "Error in load-modules: ROSIE_HOME is not set")

local os = require "os"
local math = require "math"

-- Ensure we can fit any current (up to 0x10FFFF) and future (up to 0xFFFFFFFF) Unicode code
-- points in a single Lua integer.
if (not math) then
   error("Internal error: math functions unavailable")
elseif (0xFFFFFFFF > math.maxinteger) then
   error("Internal error: max integer on this platform is too small")
end

----------------------------------------------------------------------------------------
-- Load modules
----------------------------------------------------------------------------------------

module = {loaded = {}}
module.loaded.math = math
module.loaded.os = os

-- We intentionally redefine Lua's require, and use it in Rosie source files.
function require(name)
   return module.loaded[name] or error("Module " .. tostring(name) .. " not loaded")
end

function load_module(name, optional_subdir)
   if VERBOSE then io.write("Loading " .. name .. "... "); end
   if module.loaded[name] then
      if VERBOSE then print("already loaded."); end
      return module.loaded[name]
   end
   optional_subdir = optional_subdir or "src/core"
   local path = ROSIE_HOME .. "/" .. optional_subdir .. "/" .. name .. ".lua"
   local thing, msg = loadfile(path, "t", _ENV)
   if (not thing) then
      print("Error while initializing: cannot load Rosie module '" .. name .. "' from " .. ROSIE_HOME)
      if ROSIE_DEV then
	 error(msg, 0);
      else
	 os.exit(-1)
      end -- if DEV mode
   end -- if loadfile failed
   module.loaded[name] = thing()
   if VERBOSE then print("done."); end
   return module.loaded[name]
end

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

recordtype = load_module("recordtype")
util = load_module("util")
common = load_module("common")
list = load_module("list")
syntax = load_module("syntax")
parse = load_module("parse")
compile = load_module("compile")
eval = load_module("eval")
color_output = load_module("color-output")
grep = load_module("grep")
engine = load_module("engine")

manifest = load_module("manifest")
--lapi = load_module("lapi");
--api = load_module("api")

process_input_file = load_module("process_input_file")
process_rpl_file = load_module("process_rpl_file")

argparse = load_module("argparse", "submodules/argparse/src") -- FIXME

-- Do this in run.lua if needed
--repl = load_module("repl")


