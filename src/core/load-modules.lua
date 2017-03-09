-- -*- Mode: Lua; -*-                                                                             
--
-- load-modules.lua   Custom loader for Rosie modules
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- TODO: Create a proper .so loader and add error checking

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
-- Custom module loader: each module is loaded into its own environment
----------------------------------------------------------------------------------------

module = {loaded = {}}
module.loaded.math = math
module.loaded.os = os

-- We intentionally redefine Lua's require, and use it in Rosie source files.
function require(name)
   return module.loaded[name] or error("Module " .. tostring(name) .. " not loaded")
end

local function load_module1(name, optional_subdir)
   -- First try loading compiled version from lib directory
   local path = ROSIE_HOME .. "/lib/" .. name .. ".luac"
   local thing, msg = loadfile(path, "b", _ENV)
   if thing then return thing, msg; end
   if VERBOSE then io.write("no compiled version, looking for source... "); end
   -- Otherwise, load from source
   optional_subdir = optional_subdir or "src/core"
   local path = ROSIE_HOME .. "/" .. optional_subdir .. "/" .. name .. ".lua"
   local thing, msg = loadfile(path, "t", _ENV)
   return thing, msg
end

function load_module(name, optional_subdir)
   if VERBOSE then io.write("Loading " .. name .. "... "); end
   if module.loaded[name] then
      if VERBOSE then print("already loaded."); end
      return module.loaded[name]
   end
   local thing, msg = load_module1(name, optional_subdir)
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

----------------------------------------------------------------------------------------
-- Load the modules that make up the entire Rosie world...
----------------------------------------------------------------------------------------

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

-- These MUST have a partial order so that dependencies can be loaded first
recordtype = load_module("recordtype")
util = load_module("util")
common = load_module("common")
list = load_module("list")
writer = load_module("writer")
syntax = load_module("syntax")
parse = load_module("parse")
c0 = load_module("c0")
compile = load_module("compile")
eval = load_module("eval")
color_output = load_module("color-output")
engine = load_module("engine")

-- manifest code requires a working engine, so we initialize the engine package here
assert(parse.core_parse, "error while initializing: parse module not loaded?")
assert(syntax.transform, "error while initializing: syntax module not loaded?")
local function rpl_parser(source)
   local astlist, msgs, leftover = parse.core_parse(source)
   if not astlist then
      return nil, nil, msgs, leftover
   else
      return syntax.transform(astlist), astlist, msgs, leftover
   end
end

engine._set_defaults(rpl_parser, compile.compile0, 0, 0);
manifest = load_module("manifest")

process_input_file = load_module("process_input_file")
process_rpl_file = load_module("process_rpl_file")

argparse = load_module("argparse", "submodules/argparse/src") -- FIXME

