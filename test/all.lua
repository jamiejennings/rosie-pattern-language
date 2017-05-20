---- -*- Mode: Lua; -*-                                                                           
----
---- all.lua      run all tests
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- When running rosie as a module within a plain Lua instance:
--   r = require "rosie"
--   ROSIE_DEV=true
--   r.load_module("all", "test")

-- When running rosie as "rosie -D" to get a Lua prompt after rosie is already loaded:
--   dofile "test/all.lua"

import = rosie._env.import

termcolor = import("termcolor")
test = import("test")
json = require "cjson"

test.dofile(ROSIE_HOME .. "/test/api-test.lua")
test.dofile(ROSIE_HOME .. "/test/rpl-core-test.lua")
  print("\n\n*** EVAL IS NOT BEING TESTED\n\n")
  --test.dofile(ROSIE_HOME .. "/test/eval-test.lua")
  print("\n\n*** NEED TO RE-ENABLE THE GREP TESTS IN cli-test.lua\n\n")
test.dofile(ROSIE_HOME .. "/test/cli-test.lua")
test.dofile(ROSIE_HOME .. "/test/repl-test.lua")

passed = test.print_grand_total(results)

-- When running Rosie interactively (i.e. development mode), do not exit.  Otherwise, these tests
-- were launched from the command line, so we should exit with an informative status.
if not ROSIE_DEV then
   if passed then os.exit(0) else os.exit(-1); end
end
