---- -*- Mode: Lua; -*-                                                                           
----
---- repl-test.lua      sniff test for the repl
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

function run(cmd, expectations)
   test.heading(cmd)
   local cmd = "echo '" .. cmd .. "' | " .. rosie_cmd .. " repl"
   print(cmd)
   local results, status, code = util.os_execute_capture(cmd, nil, "l")
   if not results then error("Run failed: " .. tostring(status) .. ", " .. tostring(code)); end
   for _,s in ipairs(results) do print("* " .. s); end
   local mismatch_flag = false;
   if expectations then
      for i=2, #expectations do 		    -- skip 1st line which is greeting
	 print(results[i])
	 if expectations then
	    if results[i]~=expectations[i] then print("Mismatch"); mismatch_flag = true; end
	 end
      end -- for
      if mismatch_flag then
	 print("********** SOME MISMATCHED OUTPUT WAS FOUND. **********");
      else
	 print("END ----------------- All output matched expectations. -----------------");
      end
      if (not (#results==#expectations)) then
	 print(string.format("********** Mismatched number of results (%d) versus expectations (%d) **********", #results, #expectations))
      end
      check((not mismatch_flag), "Mismatched output compared to expectations", 1)
      check((#results==#expectations), "Mismatched number of results compared to expectations", 1)
   end -- if expectations
   return results
end

results_common_number =
   {
'Rosie v1-tranche-2',
'{"data": "0x123", ',
' "end": 6.0, ',
' "pos": 1.0, ',
' "subs": ',
'   [{"data": "0x123", ',
'     "end": 6.0, ',
'     "pos": 1.0, ',
'     "subs": ',
'       [{"data": "123", ',
'         "end": 6.0, ',
'         "pos": 3.0, ',
'         "type": "common.hex"}], ',
'     "type": "common.denoted_hex"}], ',
' "type": "common.number"}',
}

run('.match common.number "0x123"', results_common_number)
--run("common.word", nil, results_common_word)

-- ok, msg = pcall(run, "foo = common.word", nil, nil)
-- check(ok)
-- check(msg[1]:find("not an expression"))

-- ok, msg = pcall(run, "foo = common.word", true, nil)
-- check(ok)
-- check(msg[1]:find("not an expression"))

-- print("\nChecking that the command line expression can contain [[...]] per Issue #22")
-- cmd = rosie_cmd .. " patterns -r 'lua_ident = {[[:alpha:]] / \"_\" / \".\" / \":\"}+'"
-- print(cmd)
-- results, status, code = util.os_execute_capture(cmd, nil)
-- check(results, "Expression on command line can contain [[.,.]]") -- command succeeded
-- check(code==0, "Return code is zero")
-- check(results[#results]:sub(-9):find("patterns")==1)

-- -- The last two output lines explain the test failures in our sample input file
-- local function split(s, sep)
--    sep = lpeg.P(sep)
--    local elem = lpeg.C((1 - sep)^0)
--    local p = lpeg.Ct(elem * (sep * elem)^0)
--    return lpeg.match(p, s)
-- end
-- lines = split(results[1], "\n")
-- check(lines[#lines]=="")
-- check(lines[#lines-1]:find("FAIL"))
-- check(lines[#lines-2]:find("FAIL"))

return test.finish()
