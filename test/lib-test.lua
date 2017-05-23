---- -*- Mode: Lua; -*-                                                                           
----
---- lib-test.lua      run some tests on the standard library
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

test.start(test.current_filename())

-- These tests are designed to run in the Rosie development environment, which is entered with: bin/rosie -D
assert(ROSIE_HOME, "ROSIE_HOME is not set?")
assert(type(rosie)=="table", "rosie package not loaded as 'rosie'?")
import = rosie._env.import
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

libdir = ROSIE_HOME .. "/rpl"

test.heading("Running self-tests on standard library")
cmd = rosie_cmd .. " test " .. libdir .. "/*.rpl 2>/dev/null"
print()
print(cmd)
results, status, code = util.os_execute_capture(cmd, nil, "l")
if not results then error("Run failed: " .. tostring(status) .. ", " .. tostring(code)); end
check(code==0, "Self test failed on the standard library")


return test.finish()
