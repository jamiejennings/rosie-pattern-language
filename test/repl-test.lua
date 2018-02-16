---- -*- Mode: Lua; -*-                                                                           
----
---- repl-test.lua      sniff test for the repl
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

assert(TEST_HOME, "TEST_HOME is not set")

test.start(test.current_filename())

list = import("list")
util = import "util"
check = test.check

rosie_cmd = ROSIE_HOME .. "/bin/rosie"
local try = io.open(rosie_cmd, "r")
if try then
   try:close()					    -- found it.  will use it.
else
   local tbl, status, code = util.os_execute_capture("command -v rosie")
   if code==0 and tbl and tbl[1] and type(tbl[1])=="string" then
      rosie_cmd = tbl[1]:sub(1,-2)			    -- remove lf at end
   else
      error("Cannot find rosie executable")
   end
end
print("Found rosie executable: " .. rosie_cmd)

function run(cmd, expectations)
   test.heading(cmd)
   local cmd = "echo '" .. cmd .. "' | " .. rosie_cmd .. " --rpl 'import num,all' repl 2>&1"
   print(); print("Command:", cmd)
   local results, status, code = util.os_execute_capture(cmd, nil, "l")
   if not results then error("Run failed: " .. tostring(status) .. ", " .. tostring(code)); end
   local mismatch_flag = false;
   local offset = 0
   if expectations then
      for i=2, math.max(#expectations, #results) do
	 -- On linux, the first line of the output, after the greeting (Rosie version), is the
	 -- repl prompt, followed by the .match command.  On OS X, this line is not present.
	 if not results[i] then break; end
	 if (results[i]:sub(1,6) == "Rosie>") or (results[i]:sub(1,7)=="Exiting") then
	    offset = offset - 1
	 else
	    if results[i]~=expectations[i+offset] then
	       print(string.format("Mismatch:\n  Expected %q\n  Received %q",
				   tostring(expectations[i+offset]),
				   tostring(results[i])))
	       mismatch_flag = true
	    end
	 end -- if there was an expectation
      end -- for
      if mismatch_flag then
	 print("Result: MISMATCHED OUTPUT WAS FOUND");
      else
	 print("Result: ok");
      end
      if (not ((#results+offset)==#expectations)) then
	 print(string.format("********** Mismatched number of results (%d) versus expectations (%d) **********", (#results+offset), #expectations))
      end
      check((not mismatch_flag), "Mismatched output compared to expectations", 1)
      check(((#results+offset)==#expectations), "Mismatched number of results compared to expectations", 1)
   end -- if expectations
   output = table.concat(results, '\n')
   local lua_error = output:find("traceback")
   check(not lua_error)
   if lua_error then print(output); end
   return output
end

results_num_any =
   {
'Rosie v1-tranche-3',
'{"data": "0x123", ',
' "e": 6, ',
' "s": 1, ',
' "subs": ',
'   [{"data": "0x123", ',
'     "e": 6, ',
'     "s": 1, ',
'     "subs": ',
'       [{"data": "123", ',
'         "e": 6, ',
'         "s": 3, ',
'         "type": "num.hex"}], ',
'     "type": "num.denoted_hex"}], ',
' "type": "num.any"}',
}

run('.match num.any "0x123"', results_num_any)

output = run('rpl 1.0')
check(output)
check(output:find('Empty input'))
output = run('rpl 1.1')
check(output)
check(output:find('Empty input'))

output = run('rpl 1.99')
check(output)
check(output:find('rpl declaration requires version 1.99'))

output = run('rpl 2.0')
check(output)
check(output:find('rpl declaration requires version 2.0'))

output = run('rpl 1.')
check(output)
check(output:find('syntax error while reading statement'))

output = run('.load test/ok.rpl')
check(output)
check(output:find('Loaded test/ok.rpl'))

output = run('.load test/synerr.rpl')
check(output)
check(output:find('syntax error'))
check(output:find('synerr.rpl'))

output = run('all.things')
check(output)
check(output:find("grammar"))
check(output:find("in\nalias find"))


return test.finish()
