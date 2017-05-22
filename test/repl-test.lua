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
   local cmd = "echo '" .. cmd .. "' | " .. rosie_cmd .. " --rpl 'import num' repl 2>/dev/null"
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

results_num_any =
   {
'Rosie v1-tranche-3',
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
'         "type": "hex"}], ',
'     "type": "denoted_hex"}], ',
' "type": "num.any"}',
}

run('.match num.any "0x123"', results_num_any)



return test.finish()
