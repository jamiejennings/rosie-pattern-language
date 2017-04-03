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

termcolor = load_module("termcolor", "submodules/lua-modules")
test = load_module("test", "submodules/lua-modules")
json = require "cjson"

-- local results = {}

-- function do_test(fn)
--    local doer, err = loadfile(fn, "t", _ENV)
--    if not doer then error("Error loading test file: " .. tostring(err)); end
--    table.insert(results, {fn, doer()})
-- end		   
      
test.dofile(ROSIE_HOME .. "/test/api-test.lua")
test.dofile(ROSIE_HOME .. "/test/rpl-core-test.lua")
test.dofile(ROSIE_HOME .. "/test/eval-test.lua")
test.dofile(ROSIE_HOME .. "/test/cli-test.lua")
test.dofile(ROSIE_HOME .. "/test/repl-test.lua")

passed = test.print_grand_total(results)

-- When running Rosie interactively (i.e. development mode), do not exit.  Otherwise, these tests
-- were launched from the command line, so we should exit with an informative status.
if not ROSIE_DEV then
   if passed then os.exit(0) else os.exit(-1); end
end
