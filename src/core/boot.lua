return function(home)
	  assert(type(home)=="string", "ROSIE_HOME not set.  Exiting...")
	  local loader = loadfile(home .. "/lib/submodule.luac", "b")
	              or loadfile(home .. "/submodules/lua-modules/submodule.lua", "t")
	  assert(loader, "Submodule system not found.  Exiting...")
	  local mod = loader()
	  package.loaded.submodule = mod
	  local rosie_mod = mod.new("rosie", home, 
				    "lib",	    -- .luac
				    "src/core;src;submodules/lua-modules;submodules/argparse/src", -- .lua
				    "lib")	    -- .so
	  mod.import("submodule", rosie_mod)
	  -- TODO: implement mod.set, mod.get
	  mod.eval('ROSIE_HOME="' .. home .. '"', rosie_mod)
	  mod.eval('ROSIE_COMMAND="' .. '"', rosie_mod)
	  rosie = mod.import("init", rosie_mod)
	  package.loaded.rosie = rosie
	  assert(type(rosie_mod)=="table", "Init failed.  Exiting...")
	  return rosie
       end
