-- There should be one line above which is inserted by the makefile during installation.  It
-- should look like this:
-- local ROSIE_HOME = "/Users/jjennings/rosie-pattern-language"
ROSIE_COMMAND = ""
loader, msg = loadfile(ROSIE_HOME .. "/lib/submodule.luac", "b")
if not loader then
   loader, msg = loadfile(ROSIE_HOME .. "/submodules/lua-modules/submodule.lua", "t")
   if not loader then error("Error loading module system: " .. msg); end
end
mod = loader(); package.loaded.submodule = mod;
rosie_mod = mod.new("rosie", ROSIE_HOME, 
		    "lib",							   -- .luac
		    "src/core;src;submodules/lua-modules;submodules/argparse/src", -- .lua
		    "lib")							   -- .so
mod.import("submodule", rosie_mod)
mod.eval('ROSIE_HOME="' .. ROSIE_HOME .. '"', rosie_mod)
rosie = mod.import("init", rosie_mod)
package.loaded.rosie = rosie
assert(type(rosie_mod)=="table", "Return value from init was not the rosie module (a table)")
return rosie
