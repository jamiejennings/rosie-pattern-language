-- -*- Mode: Lua; -*-                                                                             
--
-- command-test.lua    Implements the 'test' command of the cli
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHORS: Jamie A. Jennings, Kevin Zander

local p = {}

-- TODO: find another place for this, which is also in cli.lua
local function load_string(rosie, en, input)
   local ok, results, messages = pcall(en.load, en, input)
   if not ok then
      if rosie.mode("dev") then error(results)
      else io.write("Cannot load rpl: \n", results); os.exit(-1); end
   end
   return results, messages
end

function p.setup_and_run(rosie, en, args)
   local match = rosie.import("command-match")

   local function startswith(str,sub)
      return string.sub(str,1,string.len(sub))==sub
   end
   -- from http://www.inf.puc-rio.br/~roberto/lpeg/lpeg.html
   local function split(s, sep)
      sep = lpeg.P(sep)
      local elem = lpeg.C((1 - sep)^0)
      local p = lpeg.Ct(elem * (sep * elem)^0)
      return lpeg.match(p, s)
   end
   local function find_test_lines(str)
      local num = 0
      local lines = {}
      for _,line in pairs(split(str, "\n")) do
	 if startswith(line,'-- test') then
	    table.insert(lines, line)
	    num = num + 1
	 end
      end
      return num, lines
   end
   local f = io.open(args.filename, 'r')
   local num_patterns, test_lines = find_test_lines(f:read('*a'))
   f:close()
   if num_patterns > 0 then
      local function test_accepts_exp(exp, q)
	 local res, pos = en:match(exp, q)
	 if pos ~= 0 then return false end
	 return true
      end
      local function test_rejects_exp(exp, q)
	 local res, pos = en:match(exp, q)
	 if pos == 0 then return false end
	 return true
      end
      local test_funcs = {test_rejects_exp=test_rejects_exp,test_accepts_exp=test_accepts_exp}
      local test_patterns =
	 [==[
	    testKeyword = "accepts" / "rejects"
	    test_line = "-- test" identifier testKeyword quoted_string (ignore "," ignore quoted_string)*
         ]==]

      rosie.file.load(en, "rpl/rosie/rpl_1_1.rpl")
      load_string(rosie, en, test_patterns)
      match.set_encoder(rosie, en, false, rosie.encoders)
      local failures = 0
      local exp = "test_line"
      for _,p in pairs(test_lines) do
	 local m, left = en:match(exp, p)
	 -- FIXME: need to test for failure to match
	 local name = m.subs[1].text
	 local testtype = m.subs[2].text
	 local testfunc = test_funcs["test_" .. testtype .. "_exp"]
	 local literals = 3 -- literals will start at subs offset 3
	 -- if we get here we have at least one per test_line expression rule
	 while literals <= #m.subs do
	    local teststr = m.subs[literals].text
	    teststr = common.unescape_string(teststr) -- allow, e.g. \" inside the test string
	    if not testfunc(name, teststr) then
	       print("FAIL: " .. name .. " did not " .. testtype:sub(1,-2) .. " " .. teststr)
	       failures = failures + 1
	    end
	    literals = literals + 1
	 end
      end
      if failures == 0 then
	 print("All tests passed")
      else
	 os.exit(-1)
      end
   else
      print("No tests found")
   end
   os.exit()
end

return p
