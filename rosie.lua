---- -*- Mode: Lua; -*-                                                                           
----
---- rosie.lua    Usage: rosie = require "rosie"
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local rosie = {}

-- TEMPORARY

--Announce new globals 
setmetatable(_G, {__newindex=function(self, newindex, val) print("NEW GLOBAL: ", newindex); rawset(self, newindex, val); end})

setmetatable(rosie, {__index=_G})
rosie.ROSIE_HOME = "/Users/jjennings/Work/Dev/public/rosie-pattern-language"
local loader = loadfile(rosie.ROSIE_HOME.."/src/core/bootstrap.lua", "t", rosie)
loader()
--rosie.lapi = rosie.load_module("lapi")
--rosie.load_module("repl")

print("\nContents of rosie:")
for k,v in pairs(rosie) do print(k,v); end

print()
--env.e = env.lapi.new_engine()
--env.repl(env.e)

return rosie
