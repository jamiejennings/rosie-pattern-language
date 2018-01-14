---- -*- Mode: Lua; -*- 
----
---- test-utf8-range.lua
----
---- (c) 2016, Jamie A. Jennings
----

--json = require "cjson"

-- Read the unicode db and generate all the valid codepoint ranges for all categories
--dofile("ucd.lua")
--run()


package.path = '/Users/jennings/Projects/lua-modules/?.lua;' .. package.path
--termcolor = require "termcolor"
test = require "test"

check = test.check
heading = test.heading
subheading = test.subheading

test.start(test.current_filename())

function check_range(range_exp, answer, level)
   level = level or 0
   check(type(range_exp)=="table", "range_exp not a table", level+1)
   check(answer,
	 "range included a value that is not in the correct answer: "..tostring(range_exp),
	 level+1)
   if not answer then return nil; end
   for k,v in pairs(range_exp) do
      if type(v)~="table" then
	 -- operator name or byte value
	 check(v==answer[k],
	       "atom not equal: ".. (v or "nil") .. ", "..(answer[k] or "nil"),
	    level+1)
      else
	 check_range(v, answer[k], level+1)
      end
   end
end
   
----------------------------------------------------------------------------------------
heading("Error catching")
----------------------------------------------------------------------------------------

-- high byte out of range for utf8.char function, which enforces max codepoint of 0x10FFFF
ok, r = pcall(codepoint_range, 0x0, 0x110000)
check(not ok)

-- low byte out of range for utf8.char function
ok, r = pcall(codepoint_range, -1, 0x10FFFF)
check(not ok)

-- start encoding longer than end encoding
ok, r = pcall(codepoint_range, 0x800, 0x84)
check(not ok)

----------------------------------------------------------------------------------------
heading("Compiling codepoint ranges to lpeg")
----------------------------------------------------------------------------------------

function check_compiled_range(n, m)
   local ok, r = pcall(codepoint_range, n, m)
   check(ok, tostring(r) .. " n="..n..", m="..m, 1)
   if not ok then return; end
   local p = compile_codepoint_range(r)
   if n > 0 then check(not p:match(utf8.char(n-1)), 1); end
   if m < 0x10FFFF then check(not p:match(utf8.char(m+1)), 1); end
   local success = true
   for i = n, m do
      local answer = p:match(utf8.char(i))
      if not answer then
	 success = false
	 print("check_compiled_range("..n..", "..m..") aborted the tests at codepoint: " .. i)
	 break
      end
   end -- for
   check(success, "loop from n=" .. n .. " to m=" .. m.." failed", 1)
end

subheading('Opcode "R"')
check_compiled_range(65, 65)
check_compiled_range(65, 70)
check_compiled_range(0x7F, 0x7F)

subheading('Opcode "*"')
check_compiled_range(0x80, 0x82)
check_compiled_range(0x80, 0x82)
check_compiled_range(0x3FF, 0x3FF)
check_compiled_range(0x10000, 0x10000)
check_compiled_range(0x10000, 0x1003F)

subheading('Opcode "+"')
check_compiled_range(0x10000, 0x10020)


subheading('Opcode "full ranges"')
check_compiled_range(0x80, 0xFF)
check_compiled_range(0x10000, 0x10040)
check_compiled_range(0x10040, 0x10050)

subheading('Full unicode range test')

check_compiled_range(0xFFF, 0x1000)
check_compiled_range(0x0, 0x1000)
check_compiled_range(0x10F000, 0x10FFFF)
check_compiled_range(0x100000, 0x10FFFF)

check_compiled_range(0xF0000, 0x10FFFF)
check_compiled_range(0x0, 0x10FFFF)


----------------------------------------------------------------------------------------
heading("Generating invalid utf8 encodings and probing various ranges")
----------------------------------------------------------------------------------------

function probe_peg_with_non_valids(p)
   local success, msg
   -- 1-byte non-valids
   success = true
   msg = "uninitialized message"
   for i=0x80, 0xFF do
      if p:match(string.char(i)) then
	 success = false;
	 msg = "matched invalid utf8 1-byte encoding: "..i
	 break
      end
   end
   check(success, "1-byte non-valid sequence failed: " .. msg, 2)   

   -- In the rest of these tests, we occasionally generate a prefix of a valid utf8-encoded
   --character.  Therefore, we alter the match pattern to match the entire input.
   p = p * lpeg.P(-1)

   -- 2-byte
   success = true
   msg = "uninitialized message"
   for i=0x0, 0x7F do
      local test = string.char(0xC2, i)
      if p:match(test) then
	 success = false;
	 msg = "matched invalid utf8 2-byte encoding: "..i
	 break
      end
   end
   check(success, "2-byte non-valid sequence failed: " .. msg, 2)
   -- 3-byte
   success = true
   msg = "uninitialized message"
   for i=0x0, 0xFF do				    -- includes valid middle bytes
      for j=0x0, 0x7F do			    -- invalid last byte
	 local test = string.char(0xC2, i, j)
	 if p:match(test) then
	    success = false
	    msg = string.format("matched invalid utf8 3-byte encoding %02X %02X %02X",
				0xC2, i, j)
	    break
	 end
      end -- for j
      if not success then break; end
   end -- for i
   if success then
      -- continue testing
      for i=0x0, 0x7F do			    -- only invalid middle bytes
	 for j=0x80, 0xFF do			    -- valid last bytes
	    local test = string.char(0xC2, i, j)
	    if p:match(test) then
	       success = false
	       msg = string.format("matched invalid utf8 3-byte encoding %02X %02X %02X",
				   0xC2, i, j)
	       break
	    end
	 end -- for j
	 if not success then break; end
      end -- for i
   end -- if success then test more stuff
   check(success, "3-byte non-valid sequence failed: " .. msg, 2)
   -- 4-byte sequences
   success = true
   msg = "uninitialized message"
   for _,i in ipairs{0x0, 0x30, 0x7F} do	    -- a few valid 2nd bytes
      for j=0x0, 0x7F do			    -- invalid middle bytes
	 for k=0x0, 0xFF do			    -- includes valid last bytes
	    local test = string.char(0xF0, i, j, k)
	    if p:match(test) then
	       success = false
	       msg = string.format("matched invalid utf8 4-byte encoding %02X %02X %02X %02X",
				   0xC2, i, j, k)
	       break
	    end
	 end -- for k
	 if not success then break; end
      end -- for j
      if not success then break; end
   end -- for i
   if success then
      -- continue testing
      for i=0x0, 0x7F do			      -- all invalid 2nd bytes
	 for _,j in ipairs{0x80, 0x99, 0xF0, 0xFF} do -- some valid bytes
	    for _,k in ipairs{0x80, 0x99, 0xF0, 0xFF} do -- some valid bytes
	       local test = string.char(0xC2, i, j)
	       if p:match(test) then
		  success = false
		  msg = string.format("matched invalid utf8 4-byte encoding %02X %02X %02X %02X",
				      0xC2, i, j, k)
		  break
	       end
	    end -- for k
	    if not success then break; end
	 end -- for j
	 if not success then break; end
      end -- for i
   end -- if success then test more stuff
   check(success, "4-byte non-valid sequence failed: " .. msg, 2)
end


function check_compiled_range_against_non_valids(n, m)
   local ok, r = pcall(codepoint_range, n, m)
   check(ok, tostring(r) .. " n="..n..", m="..m, 1)
   if not ok then return; end
   local p = compile_codepoint_range(r)
   probe_peg_with_non_valids(p)
end

subheading('Complete (full) ranges, all of same length')
-- 1-byte sequences
check_compiled_range_against_non_valids(0x0, 0x7F)
-- 2-byte sequences
check_compiled_range_against_non_valids(0x80, 0x7FF)
-- 3-byte sequences
check_compiled_range_against_non_valids(0x800, 0xFFFF)
-- 4-byte sequences
check_compiled_range_against_non_valids(0x10000, 0x10FFFF)

subheading('Misc ranges')
check_compiled_range_against_non_valids(0x0, 0x80)
check_compiled_range_against_non_valids(0x0, 0x7FF)
check_compiled_range_against_non_valids(0x0, 0x800)
check_compiled_range_against_non_valids(0x0, 0xFFFF)
check_compiled_range_against_non_valids(0x0, 0x10000)
check_compiled_range_against_non_valids(0x0, 0x10FFFF)

check_compiled_range_against_non_valids(0x80, 0x80)
check_compiled_range_against_non_valids(0x88, 0x7FF)
check_compiled_range_against_non_valids(0x93, 0x800)
check_compiled_range_against_non_valids(0xA0, 0xFFFF)
check_compiled_range_against_non_valids(0xCC, 0x10000)
check_compiled_range_against_non_valids(0xFF, 0x10FFFF)

subheading('Random ranges')
for i=1, 200 do
   n = math.random(0x10FFFF)
   m = math.random(0x10FFFF)
   if (m < n) then n, m = m, n; end
   check_compiled_range_against_non_valids(n, m)
end

test.finish()
