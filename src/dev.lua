---- -*- Mode: Lua; -*- 
----
---- dev.lua    Load this code with 'require("dev")' to set up a development environment
----
---- (c) 2015, Jamie A. Jennings
----

ROSIE_HOME = "/Users/jjennings/Work/Dev/rosie-dev"

common = require "common"
require "bootstrap"
bootstrap()
compile = require "compile"
eval = require "eval"

require "color-output"
require "manifest"
json = require "cjson"

require "repl"

io.stderr:write("This is Rosie v" .. ROSIE_VERSION .. "\n")

QUIET = false					    -- for development, want to see everything

assert(engine.is(ENGINE))			    -- default engine to use
--local n = #do_manifest(ENGINE, ROSIE_HOME.."/MANIFEST")
--print(n .. " patterns loaded into matching engine named '" .. ENGINE.name .. "'")




