---- -*- Mode: Lua; -*-                                                                           
----
---- cli-test.lua      sniff test for the CLI
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

assert(TEST_HOME, "TEST_HOME is not set")

test.start(test.current_filename())

lpeg = import "lpeg"
list = import "list"
util = import "util"
violation = import "violation"
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

infilename = TEST_HOME .. "/resolv.conf"

-- N.B. grep_flag does double duty:
-- false  ==> use the match command
-- true   ==> use the grep command
-- string ==> use the grep command and add this string to the command (e.g. to set the output encoder)
function run(import, expression, grep_flag, expectations)
   test.heading(expression)
   test.subheading((grep_flag and "Using grep command") or "Using match command")
   local verb = (grep_flag and "Grepping for") or "Matching"
   local import_option = ""
   if import then import_option = " --rpl '" .. import .. "' "; end
   local grep_extra_options = type(grep_flag)=="string" and (" " .. grep_flag .. " ") or ""
   local cmd = rosie_cmd .. grep_extra_options .. import_option ..
      (grep_flag and " grep" or " match") .. " '" .. expression .. "' " .. infilename
   cmd = cmd .. " 2>&1"
   local results, status, code = util.os_execute_capture(cmd, nil, "l")
   if not results then
      print(cmd)
      print("\nTesting " .. verb .. " '" .. expression .. "' against fixed input ")
      error("Run failed: " .. tostring(status) .. ", " .. tostring(code)); end
   local mismatch_flag = false;
   if expectations then
      if results[1]=="Loading rosie from source" then
	 table.remove(results, 1)
      end
      for i=1, #expectations do 
	 if expectations then
	    if results[i]~=expectations[i] then
	       print(results[i])
	       print("Mismatch")
	       mismatch_flag = true
	    end
	 end
      end -- for
      if mismatch_flag then
	 print(cmd)
	 io.write("\nTesting " .. verb .. " '" .. expression .. "' against fixed input: ")
	 print("SOME MISMATCHED OUTPUT WAS FOUND.");
      end
      if (not (#results==#expectations)) then
	 print(cmd)
	 io.write("\nTesting " .. verb .. " '" .. expression .. "' against fixed input: ")
	 print(string.format("Received %d results, expected %d", #results, #expectations))
      end
      check((not mismatch_flag), "Mismatched output compared to expectations", 1)
      check((#results==#expectations), "Mismatched number of results compared to expectations", 1)
   end -- if expectations
   return results
end

---------------------------------------------------------------------------------------------------
test.heading("Match and grep commands")
---------------------------------------------------------------------------------------------------

-- results_basic_matchall = 
--    {"\27[30m#\27[0m ",
--     "\27[30m#\27[0m \27[33mThis\27[0m \27[33mfile\27[0m \27[33mis\27[0m \27[33mautomatically\27[0m \27[33mgenerated\27[0m \27[33mon\27[0m \27[36mOSX\27[0m \27[30m.\27[0m ",
--     "\27[30m#\27[0m ",
--     "\27[33msearch\27[0m \27[31mnc.rr.com\27[0m ",
--     "\27[33mnameserver\27[0m \27[31m10.0.1.1\27[0m ",
--     "\27[33mnameserver\27[0m \27[4m2606\27[0m \27[30m:\27[0m \27[4ma000\27[0m \27[30m:\27[0m \27[4m1120\27[0m \27[30m:\27[0m \27[4m8152\27[0m \27[30m:\27[0m \27[4m2f7\27[0m \27[30m:\27[0m \27[4m6fff\27[0m \27[30m:\27[0m \27[4mfed4\27[0m \27[30m:\27[0m \27[4mdc1f\27[0m ",
--     "\27[32m/usr/share/bin/foo\27[0m ",
--     "\27[31mjjennings@us.ibm.com\27[0m "}

results_all_things = 
   {"[39;1m#[0m",
    "[39;1m#[0m [33mThis[0m [33mis[0m [33man[0m [33mexample[0m [33mfile[0m[39;1m,[0m [36mhand-generated[0m [33mfor[0m [33mtesting[0m [33mrosie[0m[39;1m.[0m",
    "[39;1m#[0m [33mLast[0m [33mupdate[0m[39;1m:[0m [34mWed[0m [34mJun[0m [34m28[0m [1;34m16[0m:[1;34m58[0m:[1;34m22[0m [1;34mEDT[0m [34m2017[0m",
    "[39;1m#[0m ",
    "[33mdomain[0m [31mabc.aus.example.com[0m",
    "[33msearch[0m [31mibm.com[0m [31mmylocaldomain.myisp.net[0m [31mexample.com[0m",
    "[33mnameserver[0m [31m192.9.201.1[0m",
    "[33mnameserver[0m [31m192.9.201.2[0m",
    "[33mnameserver[0m [31;4mfde9:4789:96dd:03bd::1[0m"
 }

results_common_word =
   {"[33mdomain[0m abc.aus.example.com",
    "[33msearch[0m ibm.com mylocaldomain.myisp.net example.com",
    "[33mnameserver[0m 192.9.201.1",
    "[33mnameserver[0m 192.9.201.2",
    "[33mnameserver[0m fde9:4789:96dd:03bd::1"
 }

results_common_word_grep = 
   {"# This is an example file, hand-generated for testing rosie.",
    "# Last update: Wed Jun 28 16:58:22 EDT 2017",
    "domain abc.aus.example.com",
    "search ibm.com mylocaldomain.myisp.net example.com",
    "nameserver 192.9.201.1",
    "nameserver 192.9.201.2",
    "nameserver fde9:4789:96dd:03bd::1",
    }

results_common_word_grep_matches_only = 
   {"This",
    "is",
    "an",
    "example",
    "file",
    "hand",
    "generated",
    "for",
    "testing",
    "rosie",
    "Last",
    "update",
    "Wed",
    "Jun",
    "EDT",
    "domain",
    "abc",
    "aus",
    "example",
    "com",
    "search",
    "ibm",
    "com",
    "mylocaldomain",
    "myisp",
    "net",
    "example",
    "com",
    "nameserver",
    "nameserver",
    "nameserver",
    }

results_word_network = 
   {"[33mdomain[0m [31mabc.aus.example.com[0m",
    "[33msearch[0m [31mibm.com[0m mylocaldomain.myisp.net example.com",
    "[33mnameserver[0m [31m192.9.201.1[0m",
    "[33mnameserver[0m [31m192.9.201.2[0m",
    "[33mnameserver[0m [31;4mfde9:4789:96dd:03bd::1[0m"
 }

results_number_grep =
   {" 28 ",
    "16",
    "58",
    "22 ",
    " 2017",
    " abc",
    " 192.9",
    "201.1",
    " 192.9",
    "201.2",
    " fde9",
    "4789",
    "96dd",
    "03bd",
    "1",
    }

run("", "all.things", false, results_all_things)

run("import word", "word.any", false, results_common_word)
run("import word", "word.any", true, results_common_word_grep)
run("import word, net", "word.any net.any", false, results_word_network)
run("import num", "~ num.any ~", "-o subs", results_number_grep)

ok, msg = pcall(run, "import word", "foo = word.any", nil, nil)
check(ok)
check(table.concat(msg, "\n"):find("Syntax error"))

ok, msg = pcall(run, "import word", "/foo/", nil, nil)
check(ok)
check(table.concat(msg, "\n"):find("Syntax error"))

ok, ignore = pcall(run, "import word", '"Gold"', nil, nil)
check(ok, [[testing for a shell quoting error in which rpl expressions containing double quotes
      were not properly passed to lua in bin/run-rosie]])

cmd = rosie_cmd .. " list --rpl 'lua_ident = {[[:alpha:]] / \"_\" / \".\" / \":\"}+' 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "Expression on command line can contain [[.,.]]") -- command succeeded
check(code==0, "Return code is zero")
results_txt = table.concat(results, '\n')
check(results_txt:find("lua_ident"))
check(results_txt:find("names"))
if (#results <=0) or (code ~= 0) then
   print(cmd)
   print("\nChecking that the command line expression can contain [[...]] per Issue #22")
end

---------------------------------------------------------------------------------------------------
test.heading("Test command")

-- Passing tests
cmd = rosie_cmd .. " test " .. TEST_HOME .. "/lightweight-test-pass.rpl 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0)
check(code==0, "Return code is zero")
check(results[#results]:find("tests passed"))
if (#results <=0) or (code ~= 0) then
   print(cmd)
   print("\nSniff test of the lightweight test facility (MORE TESTS LIKE THIS ARE NEEDED)")
end

-- Failing tests
cmd = rosie_cmd .. " test " .. TEST_HOME .. "/lightweight-test-fail.rpl 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0)
check(type(results[1])=="string")
check(code~=0, "Return code not zero")
if (#results <=0) or (code == 0) then
   print(cmd)
end

-- The last two output lines explain the test failures in our sample input file
local function split(s, sep)
   sep = lpeg.P(sep)
   local elem = lpeg.C((1 - sep)^0)
   local p = lpeg.Ct(elem * (sep * elem)^0)
   return lpeg.match(p, s)
end
lines = split(results[1], "\n")
if lines[1]=="Loading rosie from source" then
   table.remove(lines, 1)
end
check(lines[1]:find("lightweight-test-fail.rpl", 1, true))
check(lines[2]:find("FAIL"))
check(lines[3]:find("FAIL"))
check(lines[4]:find("2 tests failed out of"))

---------------------------------------------------------------------------------------------------
test.heading("Config command")

cmd = rosie_cmd .. " config 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "config command failed")
check(code==0, "Return code is zero")
if (#results <=0) or (code ~= 0) then
   print(cmd)
end

-- check for a few of the items displayed by the info command
check(results[1]:find("ROSIE_HOME"))      
check(results[1]:find("ROSIE_VERSION"))      
check(results[1]:find("ROSIE_COMMAND"))      

---------------------------------------------------------------------------------------------------
test.heading("Help command")

cmd = rosie_cmd .. " help 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command failed")
check(code==0, "Return code is not zero")
check(results[1]:find("Usage:"))
check(results[1]:find("Options:"))
check(results[1]:find("Commands:"))
if (#results <=0) or (code ~= 0) then
   print(cmd)
end

---------------------------------------------------------------------------------------------------
test.heading("Error reporting")

cmd = rosie_cmd .. " -f test/nested-test.rpl grep foo test/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command failed")
check(code ~= 0, "return code should not be zero")
if (#results <=0) or (code == 0) then
   print(cmd)
end
msg = results[1]
check(msg:find('loader'))
check(msg:find('cannot open file'))
check(msg:find("in test/nested-test.rpl:2:1:", 1, true))

cmd = rosie_cmd .. " --libpath " .. TEST_HOME .. " -f test/nested-test2.rpl grep foo test/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command failed")
check(code ~= 0, "return code should not be zero")
if (#results <=0) or (code == 0) then
   print(cmd)
end

msg = results[1]
check(msg:find("Syntax error"))
check(msg:find("parser"))
check(msg:find("test/mod4.rpl:2:9:", 1, true))
check(msg:find("in test/nested-test2.rpl:6:3:", 1, true))

cmd = rosie_cmd .. " -f test/mod1.rpl grep foonet.any /etc/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command failed")
check(code ~= 0, "return code should not be zero")
if (#results <=0) or (code == 0) then
   print(cmd)
end
msg = results[1]
check(msg:find("error"))
check(msg:find("compiler"))
check(msg:find("unbound identifier"))
check(msg:find("foonet.any"))

cmd = rosie_cmd .. " -f test/mod4.rpl grep foonet.any /etc/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command failed")
check(code ~= 0, "return code should not be zero")
if (#results <=0) or (code == 0) then
   print(cmd)
end
msg = results[1]
check(msg:find("error"))
check(msg:find("parser"))
check(msg:find("in test/mod4.rpl:2:9"))
check(msg:find("package !@#"))

cmd = rosie_cmd .. " --libpath test -f test/nested-test3.rpl grep foo test/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command failed")
check(code ~= 0, "return code should not be zero")
if (#results <=0) or (code == 0) then
   print(cmd)
end

msg = results[1]
check(msg:find("error"))
check(msg:find("loader"))
check(msg:find("not a module"))
check(msg:find("in test/nested-test2.rpl", 1, true))
check(msg:find("in test/nested-test3.rpl:5:2", 1, true))

cmd = rosie_cmd .. " --rpl 'import net' list net.* 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command failed")
check(code == 0, "return code should be zero")
if (#results <=0) or (code ~= 0) then
   print(cmd)
end

msg = results[1]
nextline = util.string_nextline(msg)
line = nextline()
while line do
   if line:sub(1,4)=="path" then
      check(line:find("green"))
      done1 = true
   elseif line:sub(1,4)=="port" then
      check(line:find("red"))
      done2 = true
   elseif line:sub(1,5)=="ipv6 " then		    -- distinguish from ipv6_mixed
      check(line:find("red;underline"))
      done3 = true
   end
   line = nextline()
end -- while
check(done1 and done2 and done3)

-- This command should fail gracefully
cmd = rosie_cmd .. " match -o json 'csv.XXXXXX' test/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command should have failed with output")
check(code ~= 0, "return code should NOT be zero")
results_txt = table.concat(results, '\n')
check(not results_txt:find("traceback"))

cmd = rosie_cmd .. " grep 'net.any <\".com\"' test/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command should have produced output")
check(code == 0, "return should have been zero")
results_txt = table.concat(results, '\n')
check(not results_txt:find("traceback"))

cmd = rosie_cmd .. " grep '{net.any & num.int}' test/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command should have produced output")
check(code == 0, "return should have been zero")
results_txt = table.concat(results, '\n')
check(not results_txt:find("traceback"))

cmd = rosie_cmd .. " grep '(net.any & <\"search\")' test/resolv.conf 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command should have produced output")
check(code ~= 0, "return should not have been zero")
results_txt = table.concat(results, '\n')
check(not results_txt:find("traceback"))
check(results_txt:find("can match the empty string"))

cmd = rosie_cmd .. " expand 'a b' 2>&1"
results, status, code = util.os_execute_capture(cmd, nil)
check(#results>0, "command should have produced output")
check(code == 0, "return should have been zero")
results_txt = table.concat(results, '\n')
check(not results_txt:find("traceback"))
check(results_txt:find("a ~ b"))



return test.finish()
