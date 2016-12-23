---- -*- Mode: Lua; -*-                                                                           
----
---- rosie.lua    Usage: rosie = require "rosie"
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TEMPORARY

--Announce new globals 
setmetatable(_G, {__newindex=function(self, newindex, val) print("NEW GLOBAL: ", newindex); rawset(self, newindex, val); end})

ROSIE_HOME = "/Users/jjennings/Work/Dev/public/rosie-pattern-language"
env = setmetatable({}, {__index=_G})
x = loadfile(ROSIE_HOME.."/src/core/bootstrap.lua", "t", env)
x()
--env.lapi = env.load_module("lapi")
--env.load_module("repl")

print("\nContents of env:")
for k,v in pairs(env) do print(k,v); end

print()
--env.e = env.lapi.new_engine()
--env.repl(env.e)

