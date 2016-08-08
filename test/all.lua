---- -*- Mode: Lua; -*-                                                                           
----
---- all.lua      run all tests
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

test = require "test-functions"
json = require "cjson"

local results = {}

function do_test(fn)
   table.insert(results, {fn, dofile(fn)})
end		   
      
do_test(ROSIE_HOME .. "/test/api-test.lua")
do_test(ROSIE_HOME .. "/test/rpl-core-test.lua")
do_test(ROSIE_HOME .. "/test/cli-test.lua")
do_test(ROSIE_HOME .. "/test/eval-test.lua")

test.print_grand_total(results)
