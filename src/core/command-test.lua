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
	 includesKeyword = ("includes" / "excludes")
	 includesClause = includesKeyword identifier
	 testKeyword = "accepts" / "rejects"
	 test_line = "-- test" identifier (testKeyword / includesClause) quoted_string (ignore "," ignore quoted_string)*
   ]==]
   en:load("import rosie/rpl_1_1 as .")
   en:load(test_patterns)
end   


function p.run(rosie, en, args, filename)
   -- fresh engine for testing this file
   local test_engine = rosie.engine.new()
   -- set it up using whatever rpl strings or files were given on the command line
   cli_common.setup_engine(test_engine, args)
   -- load the rpl code we are going to test (second arg true means "do not search")
   local ok, pkgname, msgs, actual_path = test_engine:loadfile(filename, true)
   if not ok then
      io.write("Error: rpl file did not compile\n", util.table_to_pretty_string(msgs), "\n")
      return 0, 0
   end
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
      if pkgname then exp = pkgname .. "." .. exp; end
      local ok, res, pos = test_engine:match(exp, q)
      if not ok then
	 print("***"); table.print(res); print("***")
      end
      if (not ok) then io.write("Error: test expression did not compile: ", tostring(exp), "\n"); end
      if (not ok) or (not res) or (pos ~= 0) then return false end
      return true
   end
   local function test_rejects_exp(exp, q)
      if pkgname then exp = pkgname .. "." .. exp; end
      local ok, res, pos = test_engine:match(exp, q)
      if (not ok) then io.write("Error: test expression did not compile: ", tostring(exp), "\n"); end
      if (not ok) or (res and (pos == 0)) then return false end
      return true
   end
   -- return values: true, false, nil (nil means failure to match)
   local function test_includes_ident(exp, q, id)
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
      if pkgname then exp = pkgname .. "." .. exp; end
      local ok, res, leftover = test_engine:match(exp, q)
      if (not ok) then io.write("Error: test expression did not compile: ", tostring(exp), "\n"); end
      -- check for match error, which prevents testing containment
      if (not ok) or (not res) or (leftover~=0) then return nil; end
      return searchForID(res.subs, id)
   end
   local test_funcs = {rejects=test_rejects_exp,accepts=test_accepts_exp}
   local failures, total = 0, 0
   local test_rplx, msg = en:compile("test_line")
   assert(test_rplx, "internal error: test_line failed to compile")
   for _,p in pairs(test_lines) do
      local m, left = test_rplx:match(p)
      if not m then
	 print(filename .. ": FAIL: invalid test syntax: " .. p)
	 failures = failures + 1
	 break
      end
      local testIdentifier = m.subs[1].text
      local testType = m.subs[2].type
      local literals = 3 -- literals will start at subs offset 3
      if testType == "includesClause" then
         -- test includes
	 local t = m.subs[2]
	 assert(t.subs and t.subs[1] and t.subs[1].type=="includesKeyword")
	 local testing_excludes = (t.subs[1].text=="excludes")
	 assert(t.subs[2] and t.subs[2].type=="identifier",
		"not an identifier: " .. tostring(t.subs[2].type))
         local containedIdentifier = t.subs[2].text
         for i = literals, #m.subs do
            total = total + 1
            local teststr = m.subs[i].text
            teststr = common.unescape_string(teststr)
	    local includes = test_includes_ident(testIdentifier, teststr, containedIdentifier)
	    local msg
	    if includes==nil then
	       msg = " did not accept " .. teststr ..
		  " (blocked includes/excludes test of " .. containedIdentifier .. ")"
	    elseif (not testing_excludes and not includes) then
	       msg = " did not include " .. containedIdentifier .. " with input " .. teststr
	    elseif (testing_excludes and includes) then
	       msg = " did not exclude " .. containedIdentifier .. " with input " .. teststr
	    end
	    if msg then
               print(filename .. ((includes==nil and ": BLOCKED: ") or ": FAIL: ") .. testIdentifier .. msg)
               failures = failures + 1
            end
         end
      elseif testType == "testKeyword" then
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
      else -- unknown test type
	 assert(false, "parser for test expressions produced unexpected test type: " .. tostring(testType))
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
