-- There should be one line above which is inserted by the makefile during installation.  It
-- should look like this:
-- local home = "/Users/jjennings/rosie-pattern-language"
local rosie_init = home.."/src/core/init.lua"
local env = setmetatable({ROSIE_HOME=home}, {__index=_G})
local loader, msg = loadfile(rosie_init, "t", env)
if not loader then error("Error loading " .. rosie_init .. ": " .. msg); end
local ok, rosie = pcall(loader)
if not ok then error("Error initializing rosie: " .. rosie); end
return rosie
