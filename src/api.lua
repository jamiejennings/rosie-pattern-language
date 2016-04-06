---- -*- Mode: Lua; -*- 
----
---- api.lua     Rosie API in Lua
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"
local compile = require "compile"
require "engine"
local manifest = require "manifest"
local json = require "cjson"

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

--
--    Consolidated Rosie API
--
--      - Managing the environment
--        - Obtain/destroy/ping a Rosie engine
--        - Get a copy of the engine environment
--
--      - Rosie engine functions
--        - RPL related
--          - RPL statement (incremental compilation)
--          - RPL file compilation
--          - RPL manifest processing
--
--        - Match related
--          - match pattern against string
--          - match pattern against file
--          - eval pattern against string
--
--        - Post-processing transformations
--          - ???
--
--        - Human interaction / debugging
--          - list patterns
--          - CRUD on color assignments for color output?
--          - help?
--          - debug?

local api = {VERSION="0.9 alpha"}

local engine_list = {}

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

local function pcall_wrap(f)
   return function(...)
	     return pcall(f, ...)
	  end
end

local function delete_engine(id)
   if (not type(id)=="string") then
      arg_error("engine id not a string")
   end
   engine_list[id] = nil;
end

api.delete_engine = pcall_wrap(delete_engine)

local function ping_engine(id)
   if (not type(id)=="string") then
      arg_error("engine id not a string")
   end
   local en = engine_list[id]
   if en then
      return en.name
   else
      arg_error("invalid engine id")
   end
end

api.ping_engine = pcall_wrap(ping_engine)

local function new_engine(optional_name)	    -- optional manifest? file list? code string?
   if optional_name and (not type(optional_name)=="string") then
      arg_error("optional engine name not a string")
   end
   local en = engine(optional_name, compile.new_env())
   engine_list[en.id] = en
   -- !@# more to do !@#
   return en.id
end

api.new_engine = pcall_wrap(new_engine)

local function engine_from_id(id)
   if (not type(id)=="string") then
      arg_error("engine id not a string")
   end
   local en = engine_list[id]
   if (not engine.is(en)) then
      arg_error("invalid engine id")
   end
   return en
end

local function get_env(id)
   local en = engine_from_id(id)
   local env = compile.flatten_env(en.env)
   return json.encode(env)
end

api.get_env = pcall_wrap(get_env)

function api.load_manifest(id, manifest_file)
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end
   return manifest.process_manifest(en, manifest_file)
end

function api.load_file(id, path, relative_to_rosie_home)
   -- default is relative to rosie home directory for paths not starting with "." or "/"
   relative_to_rosie_home = (relative_to_rosie_home==nil) or relative_to_rosie_home
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end
   local full_path
   if path:sub(1,1)=="." or path:sub(1,1)=="/" then -- WILL BREAK ON WINDOWS
      -- absolute path
      full_path = path
   else
      if relative_to_rosie_home then
	 -- construct a path relative to ROSIE_HOME
	 full_path = ROSIE_HOME .. "/" .. path
      else
	 full_path = path
      end
      full_path = full_path:gsub("\\ ", " ")	    -- unescape a space in the name
   end
   local result, msg = compile.compile_file(full_path, en.env)
   return (not (not result)), msg
end

function api.load_string(id, input)
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end
   local result, msg = compile.compile(input, en.env)
   return (not (not result)), msg
end



return api



