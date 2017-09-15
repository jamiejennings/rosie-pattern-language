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

rosie = rosie or require("rosie")
import = rosie.import
ROSIE_HOME = rosie.env.ROSIE_HOME

termcolor = import("termcolor")
test = import("test")
json = require "cjson"

test.dofile(ROSIE_HOME .. "/test/lib-test.lua")
test.dofile(ROSIE_HOME .. "/test/rpl-core-test.lua")
test.dofile(ROSIE_HOME .. "/test/rpl-mod-test.lua")
test.dofile(ROSIE_HOME .. "/test/rpl-appl-test.lua")

test.dofile(ROSIE_HOME .. "/test/trace-test.lua")

test.dofile(ROSIE_HOME .. "/test/cli-test.lua")
test.dofile(ROSIE_HOME .. "/test/repl-test.lua")

test.dofile(ROSIE_HOME .. "/test/utf8-test.lua")

passed = test.print_grand_total()


print("\nTESTING TODO LIST:")
print("- macros")
print("- input data with nulls")
print("- new api")
print("- more repl tests")
print("- more trace tests")
print()


-- When running Rosie interactively (i.e. development mode), do not exit.  Otherwise, these tests
-- were launched from the command line, so we should exit with an informative status.
if not ROSIE_DEV then
   if passed then os.exit(0) else os.exit(-1); end
end
