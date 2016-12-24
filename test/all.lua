---- -*- Mode: Lua; -*-                                                                           
----
---- all.lua      run all tests
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TODO: use load_module
local loader = loadfile(ROSIE_HOME.."/src/test-functions.lua", "t")
test = loader()
module.loaded["test-functions"] = test
json = require "cjson"

local results = {}

function do_test(fn)
   table.insert(results, {fn, dofile(fn)})
end		   
      
do_test(ROSIE_HOME .. "/test/api-test.lua")
do_test(ROSIE_HOME .. "/test/rpl-core-test.lua")
do_test(ROSIE_HOME .. "/test/cli-test.lua")
do_test(ROSIE_HOME .. "/test/eval-test.lua")

passed = test.print_grand_total(results)

-- When running Rosie interactively (i.e. development mode), do not exit.  Otherwise, these tests
-- were launched from the command line, so we should exit with an informative status.
if not ROSIE_DEV then
   if passed then os.exit(0) else os.exit(-1); end
end


