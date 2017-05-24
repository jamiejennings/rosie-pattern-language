-- -*- Mode: Lua; -*-                                                                             
--
-- command-test.lua    Implements the 'test' command of the cli
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHORS: Jamie A. Jennings, Kevin Zander

local p = {}
local cli_common = import("command-common")
local io = import("io")
local common = import("common")

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

-- setup the engine that will parse the test lines in the rpl file
function p.setup(en)
   local test_patterns =
		[==[
			containsKeyword = "contains" identifier
			testKeyword = "accepts" / "rejects"
			test_line = "-- test" identifier (testKeyword / containsKeyword) quoted_string (ignore "," ignore quoted_string)*
		]==]
   en:load("import rosie/rpl_1_1 as .")
   en:load(test_patterns)
end   


function p.run(rosie, en, args, filename)
   -- fresh engine for testing this file
   local test_engine = rosie.engine.new()
   -- set it up using whatever rpl strings or files were given on the command line
   cli_common.setup_engine(test_engine, args)
   -- load the rpl code we are going to test
   test_engine:loadfile(filename, true)             -- second arg true --> do not search
   cli_common.set_encoder(rosie, test_engine, false)
   -- read the tests out of the file and run each one
   local f, msg = io.open(filename, 'r')
   if not f then error(msg); end
   local num_patterns, test_lines = find_test_lines(f:read('*a'))
   f:close()
   if num_patterns == 0 then
      print(filename .. ": No tests found")
      return 0, 0
   end
   local function test_accepts_exp(exp, q)
      local res, pos = test_engine:match(exp, q)
      if (not res) or (pos ~= 0) then return false end
      return true
   end
   local function test_rejects_exp(exp, q)
      local res, pos = test_engine:match(exp, q)
      if res and (pos == 0) then return false end
      return true
   end
   local function test_contains_ident(exp, q, id)
      local function searchForID(tbl, id)
         -- tbl MUST BE "subs" table from a match
         local found = false
         for i = 1, #tbl do
            if tbl[i].subs ~= nil then
               found = searchForID(tbl[i].subs, id)
               if found then break end
            end
            if tbl[i].type == id then
               found = true
               break
            end
         end
         return found
      end
      local res, pos = test_engine:match(exp, q)
      return searchForID(res.subs, id)
   end
   local test_funcs = {rejects=test_rejects_exp,accepts=test_accepts_exp}
   local failures, total = 0, 0
   local exp = "test_line"
   for _,p in pairs(test_lines) do
      local m, left = en:match(exp, p)
      -- FIXME: need to test for failure to match
      local testIdentifier = m.subs[1].text
      local testType = m.subs[2].type
      local literals = 3 -- literals will start at subs offset 3
      if testType == "containsKeyword" then
         -- test contains
         local containedIdentifier = m.subs[2].subs[1].text
         for i = literals, #m.subs do
            total = total + 1
            local teststr = m.subs[i].text
            teststr = common.unescape_string(teststr)
            if not test_contains_ident(testIdentifier, teststr, containedIdentifier) then
               print(filename .. ": FAIL: " .. testIdentifier .. " did not contain " .. containedIdentifier .. " from " .. teststr)
               failures = failures + 1
            end
         end
      else
         -- test accepts/rejects
         for i = literals, #m.subs do
            total = total + 1
            local teststr = m.subs[i].text
            teststr = common.unescape_string(teststr) -- allow, e.g. \" inside the test string
            if not test_funcs[m.subs[2].text](testIdentifier, teststr) then
               if #teststr==0 then teststr = "the empty string"; end -- for display purposes
               print(filename .. ": FAIL: " .. testIdentifier .. " did not " .. m.subs[2].text:sub(1,-2) .. " " .. teststr)
               failures = failures + 1
            end
         end
      end
   end
   if failures == 0 then
      print(filename .. ": All " .. tostring(total) .. " tests passed")
   else
      print(filename .. ": " .. tostring(failures) .. " tests failed out of " .. tostring(total) .. " attempted")
   end
   return failures, total
end

return p
