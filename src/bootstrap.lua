---- -*- Mode: Lua; -*- 
----
---- bootstrap.lua      Bootstrap Rosie by using the native Lua parser to parse rosie-core.rpl
----
---- (c) 2015, Jamie A. Jennings
----

-- Restrict Lua's search for modules and shared objects to just the Rosie install directory
package.path = ROSIE_HOME .. "/src/?.lua"
package.cpath = ROSIE_HOME .. "/lib/?.so"

local compile = require "compile"
local common = require "common"
require "engine"
require "os"

-- ROSIE_HOME should be set before entry to this code
if not ROSIE_HOME then error("ROSIE_HOME not set.  Exiting..."); os.exit(-1); end

-- Create a matching engine for processing Rosie Pattern Language files
ROSIE_ENGINE = engine("RPL engine", {}, compile.new_env())

BOOTSTRAP_COMPLETE = false;

function bootstrap()
   local vfile = io.open(ROSIE_HOME.."/VERSION")
   if not vfile then
      io.stderr:write("Installation error: File "..tostring(ROSIE_HOME).."/VERSION does not exist or is not readable\n")
      os.exit(-3)
   end
   
   ROSIE_VERSION = vfile:read("l"); vfile:close();
   compile.compile_core(ROSIE_HOME.."/src/rosie-core.rpl", ROSIE_ENGINE.env)
   ROSIE_ENGINE.program = { compile.core_compile_command_line_expression('rpl', ROSIE_ENGINE.env) }
   BOOTSTRAP_COMPLETE = true
end

