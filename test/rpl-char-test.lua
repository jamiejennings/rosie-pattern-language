-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-char-test.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

assert(TEST_HOME, "TEST_HOME is not set")

utf8 = require("utf8")

list = import "list"
cons, map, flatten, member = list.cons, list.map, list.flatten, list.member
common = import "common"
violation = import "violation"

check = test.check
heading = test.heading
subheading = test.subheading
e = false;

global_rplx = false;

function set_expression(exp)
   global_rplx, msg = e:compile(exp)
   if not global_rplx then
      print("\nThis exp failed to compile: " .. tostring(exp))
      table.print(msg)
      error("compile failed in rpl-core-test")
   end
end

function check_match(exp, input, expectation, expected_leftover, expected_text, addlevel)
   expected_leftover = expected_leftover or 0
   addlevel = addlevel or 0
   if exp ~= global_rplx then set_expression(exp); end
   local m, leftover = global_rplx:match(input)
   check(expectation == (not (not m)), "expectation not met: " .. tostring(exp) .. " " ..
	 ((m and "matched") or "did NOT match") .. " '" .. input .. "'", 1+addlevel)
   local fmt = "expected leftover matching %s against '%s' was %d but received %d"
   if m then
      check(leftover==expected_leftover,
	    string.format(fmt, tostring(exp), input, expected_leftover, leftover), 1+addlevel)
      if expected_text and m then
	 local name, pos, text, subs = common.decode_match(m)
	 local fmt = "expected text matching %s against '%s' was '%s' but received '%s'"
	 check(expected_text==text,
	       string.format(fmt, tostring(exp), input, expected_text, text), 1+addlevel)
      end
   end
   return m, leftover
end
      
test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Setting up")
----------------------------------------------------------------------------------------

check(type(rosie)=="table")
e = rosie.engine.new("rpl core test")
check(rosie.engine.is(e))

t = e.env:lookup(".")
check(type(t)=="table")
t = e.env:lookup("~")
check(type(t)=="table")
t = e.env:lookup("^")
check(type(t)=="table")
t = e.env:lookup("$")
check(type(t)=="table")


----------------------------------------------------------------------------------------
heading("Dot")
----------------------------------------------------------------------------------------

set_expression('.')
ok, match, leftover = e:match('.', "a")
check(ok)
check(type(match)=="table")
check(type(leftover)=="number")
check(leftover==0)
check(match.type=="*")

MAX_CODEPOINT = 0x10FFFF

set_expression('.')
assert(global_rplx)

local failures = false
for codepoint = 0, MAX_CODEPOINT do
   local char = utf8.char(codepoint)
   match, leftover = global_rplx:match(char, 1, "line")
   if not match then
      failures = true
      check(false, string.format("match failed on codepoint 0x%x", codepoint))
   elseif leftover ~= 0 then
      failures = true
      check(false,
	    string.format("match failed with %d leftover bytes on codepoint 0x%x",
			  leftover,
			  codepoint))
   end
end -- for all possible codepoints
check(not failures, "dot failed to match some codepoints -- see test failures above")

-- We need to check single bytes in the range 128-255, because 0-127 will be recognized as valid
-- utf8 codepoints, so they will have been tested already.  But, just in case, we will check every
-- possible single byte value here.
local failures = false
for byte = 0, 255 do
   local char = string.char(byte)
   match, leftover = global_rplx:match(char, 1, "line")
   if not match then
      failures = true
      check(false, string.format("match failed on byte 0x%x", byte))
   elseif leftover ~= 0 then
      failures = true
      check(false,
	    string.format("match failed with %d leftover bytes on byte 0x%x",
			  leftover,
			  byte))
   end
end -- for all possible codepoints
check(not failures, "dot failed to match some single bytes -- see test failures above")



----------------------------------------------------------------------------------------
heading("Boundary")
----------------------------------------------------------------------------------------

-- Note: Many tests of key boundary properties have already been run in rpl-core-test.lua.  The
-- tests here are meant to focus on exactly what the boundary matches.
set_expression('~')
assert(global_rplx)

-- Empty input matches
check_match(global_rplx, '', true, 0, "")
-- Start of input matches
check_match(global_rplx, 'X', true, 1, "")
check_match(global_rplx, 'XYZ', true, 3, "")
-- Char X does not match
match, leftover = global_rplx:match('XYZ', 2, "line")
check(not match)
-- End of input matches
match, leftover = global_rplx:match('X', 2, "line")
check(match)
check(leftover == 0)
match, leftover = global_rplx:match('XYZ', 4, "line")
check(match)
check(leftover == 0)


local byte_matches = {}
for byte = 0, 255 do
   local char = 'X' .. string.char(byte) .. 'Y'
   match, leftover = global_rplx:match(char, 2, "line")
   if match and (leftover ~= 0) then
      byte_matches[byte] = true
   end
end -- for all possible bytes

whitespace_bytes = {9, 10, 11, 12, 13, 32}

punctuation_bytes = {33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
		    58, 59, 60, 61, 62, 63, 64, 91, 92, 93, 94, 95, 96, 123,
		    124, 125, 126}
   
function check_byte_matches(correct_match_list, name)
   failures = false
   for _, n in ipairs(correct_match_list) do
      if byte_matches[n] then
	 byte_matches[n] = nil
      else
	 check(false, "dot failed to match " .. name .. " char " .. tostring(n))
	 failures = true
      end
   end
   check(not failures, "dot failed on some " .. name .. " chars -- see failures above")
end

check_byte_matches(whitespace_bytes, "whitespace")
check_byte_matches(punctuation_bytes, "punctuation")



----------------------------------------------------------------------------------------
heading("Start of input")
----------------------------------------------------------------------------------------

set_expression('^')
assert(global_rplx)

-- Empty input matches
check_match(global_rplx, '', true, 0, "")
-- Start of input matches
check_match(global_rplx, 'X', true, 1, "")
check_match(global_rplx, 'XYZ', true, 3, "")
-- Char X does not match
match, leftover = global_rplx:match('XYZ', 2, "line")
check(not match)
-- End of input does not match
match, leftover = global_rplx:match('X', 2, "line")
check(not match)
match, leftover = global_rplx:match('XYZ', 4, "line")
check(not match)
      
----------------------------------------------------------------------------------------
heading("End of input")
----------------------------------------------------------------------------------------

set_expression('$')
assert(global_rplx)

-- Empty input matches
check_match(global_rplx, '', true, 0, "")
-- Start of input does not match
check_match(global_rplx, 'X', false, 1, "")
check_match(global_rplx, 'XYZ', false, 3, "")
-- Char X does not match
match, leftover = global_rplx:match('XYZ', 2, "line")
check(not match)
-- End of input matches
match, leftover = global_rplx:match('X', 2, "line")
check(match)
check(leftover == 0)
match, leftover = global_rplx:match('XYZ', 4, "line")
check(match)
check(leftover == 0)


----------------------------------------------------------------------------------------
heading("Escape sequences")
----------------------------------------------------------------------------------------

subheading("Valid escapes")

literals = {{"A", "A"},				   -- A quick sanity check first
	    {"\\x41", "A"},
	    {"\\u0041", "A"},
	    {"\\U00000041", "A"},
	    {"\\u2323", "⌣"},
	    {"\\U00002323", "⌣"},
	    {"\\U00010175", "𐅵"},
	    {"\\U00010175", utf8.char(0x10175)},
	    {"\\a", "\a"},
	    {"\\b", "\b"},
	    {"\\f", "\f"},
	    {"\\n", "\n"},
	    {"\\r", "\r"},
	    {"\\t", "\t"},
	 }
for i=0, 0xFF do
   table.insert(literals, {string.format("\\x%02x", i), string.char(i)})
end

for _, entry in ipairs(literals) do
   local literal, input = entry[1], entry[2]
   check_match('"' .. literal .. '"', input, true, 0)
end

subheading("Invalid escapes")

pat, err = e:compile("\\x")
check(not pat)
msg = violation.tostring(err[1])
check(msg:find('syntax error'))

for _,thing in ipairs({'\\x', '\\x4', '\\x0 ', '\\x 1', '\\x1G'}) do
   pat, err = e:compile('"' .. thing .. '"')
   check(not pat)
   msg = violation.tostring(err[1])
   check(msg:find('invalid hex escape'))
end

pat, err = e:compile("\\u")
check(not pat)
msg = violation.tostring(err[1])
check(msg:find('syntax error'))

for _,thing in ipairs({'\\u', '\\uF', '\\uFF', '\\u432', '\\u012 ', '\\u 234', '\\uABCG'}) do
   pat, err = e:compile('"' .. thing .. '"')
   check(not pat)
   msg = violation.tostring(err[1])
   check(msg:find('invalid unicode escape'))
end

pat, err = e:compile("\\U")
check(not pat)
msg = violation.tostring(err[1])
check(msg:find('syntax error'))

for _,thing in ipairs({'\\U', '\\U4', '\\U43', '\\U432', '\\U1234567',
		       '\\U1234567 ', '\\U 0010FF80', '\\U0010FF8X'}) do
   pat, err = e:compile('"' .. thing .. '"')
   check(not pat)
   msg = violation.tostring(err[1])
   check(msg:find('invalid Unicode escape'))
end

----------------------------------------------------------------------------------------
heading("Generating escape sequences")
----------------------------------------------------------------------------------------
escape = rosie.env.ustring.escape
for i = 0, 0xFF do
   local str = escape(string.char(i))
   if i==7 then check(str=='\\a')
   elseif i==8 then check(str=='\\b')
   elseif i==9 then check(str=='\\t')
   elseif i==10 then check(str=='\\n')
   elseif i==12 then check(str=='\\f')
   elseif i==13 then check(str=='\\r')
   elseif i==92 then check(str=='\\\\')
   elseif i>=32 and i<=126 then
      check(str == string.char(i), "failed at char " .. tostring(i))
   else
      check(str == string.format("\\x%02X", i), "failed at char " .. tostring(i))
   end
end


-- return the test results in case this file is being called by another one which is collecting
-- up all the results:
return test.finish()

