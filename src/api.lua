---- -*- Mode: Lua; -*- 
----
---- api.lua     Rosie API in Lua
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"
local compile = require "compile"

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



