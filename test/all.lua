---- -*- Mode: Lua; -*-                                                                           
----
---- all.lua      run all tests
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- See Makefile for how these tests are run using the undocumented "-D" option to rosie, which
-- enters development mode after startup.

assert(rosie)
import = rosie.import
ROSIE_HOME = rosie.env.ROSIE_HOME
TEST_HOME = "./test"

json = import "cjson"

package.path = "./submodules/lua-modules/?.lua"
termcolor = assert(require("termcolor"))
test = assert(require("test"))

test.dofile(TEST_HOME .. "/lib-test.lua")
test.dofile(TEST_HOME .. "/rpl-core-test.lua")
test.dofile(TEST_HOME .. "/rpl-mod-test.lua")
test.dofile(TEST_HOME .. "/rpl-appl-test.lua")

test.dofile(TEST_HOME .. "/trace-test.lua")

test.dofile(TEST_HOME .. "/cli-test.lua")
test.dofile(TEST_HOME .. "/repl-test.lua")

test.dofile(TEST_HOME .. "/utf8-test.lua")

passed = test.print_grand_total()


print("\nMORE AUTOMATED TESTS ARE NEEDED IN THESE CATEGORIES:")
print("- extreme patterns (many choices, deep nesting, many different capture names)")
print("- input data with nulls")
print("- more repl tests")
print("- more trace tests")
print()


-- When running Rosie interactively (i.e. development mode), do not exit.  Otherwise, these tests
-- were launched from the command line, so we should exit with an informative status.
if not ROSIE_DEV then
   if passed then os.exit(0) else os.exit(-1); end
end
