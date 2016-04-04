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

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

--
--    Consolidated Rosie API
--
--      - Managing the environment
--        - Obtain/destroy/ping a Rosie engine
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

local api = {}

local engine_list = {}

local function arg_error(msg)
   return nil, "Argument error: " .. msg
end

function api.new_engine(optional_name)		    -- optional manifest? file list? code string?
   if optional_name and (not type(optional_name)=="string") then
      return arg_error("optional engine name not a string")
   end
   local en = engine(optional_name, compile.new_env())
   table.insert(engine_list, en.id, en)
   return en.id
end



