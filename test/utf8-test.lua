---- -*- Mode: Lua; -*-                                                                           
----
---- utf8-test.lua
----
---- © Copyright IBM Corporation 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

test = rosie.import "test"
test.start(test.current_filename())

-- These tests are designed to run in the Rosie development environment, which is entered with: bin/rosie -D
assert(ROSIE_HOME, "ROSIE_HOME is not set?")
assert(type(rosie)=="table", "rosie package not loaded as 'rosie'?")
import = rosie.import
if not test then
   test = import("test")
end

list = import("list")
util = import "util"
check = test.check

rosie_cmd = ROSIE_HOME .. "/bin/rosie"
local try = io.open(rosie_cmd, "r")
if try then
   try:close()					    -- found it.  will use it.
else
   local tbl, status, code = util.os_execute_capture("which rosie")
   if code==0 and tbl and tbl[1] and type(tbl[1])=="string" then
      rosie_cmd = tbl[1]:sub(1,-2)			    -- remove lf at end
   else
      error("Cannot find rosie executable")
   end
end
print("Found rosie executable: " .. rosie_cmd)

rplfile = "utf8-in-rpl.rpl"
test.heading("Running self-tests on " .. rplfile)
cmd = rosie_cmd .. " test --verbose " .. "test/" .. rplfile .. " 2>/dev/null"
print()
print(cmd)
results, status, code = util.os_execute_capture(cmd)
if not results then error("Run failed: " .. tostring(status) .. ", " .. tostring(code)); end
if code~=0 then print("Status code was: ", code); end
check(code==0, "UTF8 tests failed")


return test.finish()
