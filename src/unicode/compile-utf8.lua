-- -*- Mode: Lua; -*-                                                                             
--
-- compile-utf8.lua    Compile ranges of unicode characters encoded in utf8
--
-- © Copyright IBM Corporation 2016, 2017, 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

---------------------------------------------------------------------------------------------------
-- Compute an lpeg pattern that captures exactly the unicode codepoints from N to M, where they
-- are both utf8 encoded strings.
---------------------------------------------------------------------------------------------------

compile_utf8 = {}
local rosie = require("rosie")
local utf8 = require("utf8")
local lpeg = rosie.import("lpeg")

local range_start_for_n_byte_encoding =
   { string.char(0x00),
     string.char(0xC2, 0x80),
     string.char(0xE0, 0xA0, 0x80),		    -- E1 80 80, ...
     string.char(0xF0, 0x90, 0x80, 0x80),	    -- F1 80 80 80, ...
  }

local range_end_for_n_byte_encoding =
   { string.char(0x7F),
     string.char(0xDF, 0xBF),
     string.char(0xEF, 0xBF, 0xBF),		    -- ..., EE 80 80
     string.char(0xF4, 0x8F, 0xBF, 0xBF),	    -- ..., F3 80 80 80
  }

local function trailer(start_flag, len, index)
   assert(type(start_flag)=="boolean")
   return string.rep((start_flag and string.char(0x80)) or string.char(0xBF), len-index+1)
end

-- Output of R is a prefix expression encoded in a lua table as follows:
-- "+" is lpeg + (alternation) and can take 1..n arguments
-- "*" is lpeg * (sequence) and always takes 2 arguments
-- the "full ranges" primitive should produce a pattern matching any of the full ranges that start
-- with i, where i ranges from [1] to [2] inclusive; each full range is computed using the
-- range_start and range_end data for a sequence of length 'len', and the first byte of the output
-- pattern is the one at 'index'.

local function Rsame(s, e, ix)
   -- s, e are utf8 encodings of N, M, which are unicode codepoints
   -- N < M  (integer comparison)
   -- #s==#e (encodings have SAME byte sequence length)
   -- ix is the byte position in the sequence that we are comparing now
   ix = ix or 1
   assert(#s==#e, "encodings have different lengths")
   assert((ix >= 1) and (ix <= #s), "index out of range: " .. ix)
   local s1, e1 = s:byte(ix), e:byte(ix)
   -- base case: we are looking at the last byte of s, e
   if ix==#s then
      assert(s1 <= e1, "encoded bytes at end of sequence are out of order: " .. s1 .. ", " .. e1)
      return {"R", s1, e1}			    -- byte range operator
   end
   -- recursive case: we're not at the end yet;
   -- consider first the case where the current byte is the same for s, e
   if s1==e1 then
      -- when s and e (at current ix) start with same value, we return a pattern that looks for
      -- that value followed by a pattern that matches the range of the rest of the bytes.
      assert(ix < #s)
      return {"*",				    -- sequence
	      {"R", s1, s1},			    -- byte range
	      Rsame(s, e, ix+1)}		    -- compute range of the rest of s, e
   else
      assert(s1 < e1, "encoded bytes out of order: " .. s1 .. ", " .. e1)
      -- construct a pattern that is the ordered choice of 3 parts:
      -- (1) from s to the end of the range that starts with s1
      -- (2) all the "full ranges", if any, between s1 and e1
      -- (3) from the start of the range that starts with e1 to e
      -- optimization: if part (1) or (3) happen to be a full range, then collapse them into (2).
      local result = {"+"}			    -- ordered choice operator
      local first_full_range, last_full_range
      -- ** part (1)
      if s:sub(ix+1)==range_start_for_n_byte_encoding[#s]:sub(ix+1) then
	 first_full_range = s1
      else
	 first_full_range = s1 + 1
	 local range_end = s:sub(1,ix) .. trailer(false, #s, ix+1)
	 table.insert(result,
		      {"*", {"R", s1, s1}, Rsame(s, range_end, ix+1)})
      end
      -- ** part (3) optimization test
      local end_range_is_full = (e:sub(ix)==range_end_for_n_byte_encoding[#e]:sub(ix))
      if end_range_is_full then
	 last_full_range = e1
      else
	 last_full_range = e1 - 1
      end
      -- ** part (2): create the tests for full ranges between start and end
      if (first_full_range <= last_full_range) and ((#s-ix) >= 0) then
	 table.insert(result, {"full ranges", len=#s, index=ix+1, first_full_range, last_full_range})
      end
      -- ** part (3) the end range, unless it was optimized into part (2)
      if not end_range_is_full then
	 local range_start = e:sub(1,ix) .. trailer(true, #e, ix+1)
	 table.insert(result, Rsame(range_start, e, ix))
      end
      return result
   end -- s1 < e1
end

local function R(s, e)
   -- s, e are utf8 encodings of N, M, which are unicode codepoints
   -- N < M  (integer comparison)
   -- s and e are ASSUMED TO BE VALID ENCODINGS
   if #s==#e then return Rsame(s, e); end
   assert(#s < #e, "start encoding longer than end encoding")
   -- construct a pattern that is the ordered choice of 3 parts:
   -- (1) from s to the end of all of the sequences of #s bytes
   -- (2) all the "full ranges", if any, between #s and #e
   -- (3) from the start of the range of all the sequences of #e bytes to e itself
   -- optimization: if part (1) or (3) happen to be a full range, then collapse them into (2).
   local result = {"+"}			    -- ordered choice operator
   local first_full_range, last_full_range
   -- ** part (1)
   if s==range_start_for_n_byte_encoding[#s] then
      first_full_range = #s			    -- length
   else
      first_full_range = #s+1
      table.insert(result, Rsame(s, range_end_for_n_byte_encoding[#s]))
   end
   -- ** part (3) optimization test
   if e==range_end_for_n_byte_encoding[#e] then
      last_full_range = #e			    -- length
   else
      last_full_range = #e-1
   end
   -- ** part (2): all the full ranges from length first_full_range to last_full_range, inclusive
   for len = first_full_range, last_full_range do
      table.insert(result, Rsame(range_start_for_n_byte_encoding[len],
				 range_end_for_n_byte_encoding[len]))
   end
   -- ** part (3) the end range, unless it was optimized into part (2)
   if e~=range_end_for_n_byte_encoding[#e] then
      --local start = e:sub(1,1) .. range_start_for_n_byte_encoding[#e]:sub(2)
      start = range_start_for_n_byte_encoding[#e]
      table.insert(result, Rsame(start, e))
   end
   return result
end

local function expand_full_ranges(range)
   if type(range)=="number" then return range; end
   assert(type(range)=="table", "range not a number or table: " .. tostring(range))   
   local op = range[1]
   if op=="R" then
      return {"R", expand_full_ranges(range[2]), expand_full_ranges(range[3])}
   elseif op=="*" then
      return {"*", expand_full_ranges(range[2]), expand_full_ranges(range[3])}
   elseif op=="+" then
      -- "+" takes from 1..k args
      local r = {"+"}
      for i=2,#range do table.insert(r, expand_full_ranges(range[i])); end
      return r
   elseif op=="full ranges" then
      local len, index = range.len, range.index
      local r = {"+"}
      local first_full_range, last_full_range
      local low = range_start_for_n_byte_encoding[len]:byte(index)
      -- if first of all the full ranges happens to be the start of ranges of that length...
      if (range[2]==range_start_for_n_byte_encoding[len]:byte(index-1)) and (low ~= 0x80) then
	 -- first range does not go from 0x80 to 0xBF
	 first_full_range = range[2]+1
	 local first_range = {"*", {"R", range[2], range[2]}}
	 for i=index, len do table.insert(first_range, {"R", low, 0xBF}); end
	 table.insert(r, first_range)
      else
	 -- first range goes from 0x80 to 0xBF
	 first_full_range = range[2]
      end
      local high = range_end_for_n_byte_encoding[len]:byte(index)
      -- if last of all the full ranges happens to be the end of ranges of that length...
      local end_is_special = (range[3]==range_end_for_n_byte_encoding[len]:byte(index-1)) and (high ~= 0xBF)
      if end_is_special then
	 last_full_range = range[3]-1
      else
	 -- last range goes from 0x80 to 0xBF
	 last_full_range = range[3]
      end
      -- now fill in all the truly full ranges (the ones from 0x80 to 0xBF)
      local middle = {"*", {"R", first_full_range, last_full_range}}
      for i = index, len do
	 table.insert(middle, {"R", 0x80, 0xBF})
      end
      table.insert(r, middle)
      if end_is_special then
	 local last_range = {"*", {"R", range[3], range[3]}, {"R", 0x80, high}}
	 for i=index+1, len do table.insert(last_range, {"R", 0x80, 0xBF}); end
	 table.insert(r, last_range)
	 end
      return r
   end
end

-- n, m are integers in the range 0 to 0x10FFFF inclusive
-- this range includes all valid (and some invalid) unicode codepoints
-- n < m
function compile_utf8.codepoint_range(n, m)
   assert(n <= m, "codepoints out of order: "..n..", "..m)
   return expand_full_ranges(R(utf8.char(n), utf8.char(m)));
end

function flatten_star(range)
   local op = range[1]
   if op ~= "*" then
      return {range}
   else
      local firsts = flatten_star(range[2])
      local seconds = flatten_star(range[3])
      table.move(seconds, 1, #seconds, #firsts+1, firsts)
      return firsts
   end
end
      
function compile_utf8.compile_codepoint_range(range, as_peg)
   assert(type(range)=="table", "range not a table: " .. tostring(range))
   local op = range[1]
   if op=="R" then
      if as_peg then
	 return lpeg.R(string.char(range[2], range[3]))
      else
	 if range[2] == range[3] then
	    return string.format("[\\x%02x]", range[2])
	 else
	    return string.format("[\\x%02x-\\x%02x]", range[2], range[3])
	 end
      end
   elseif op=="*" then
      local components = flatten_star(range)
      local result = compile_utf8.compile_codepoint_range(components[1], as_peg)
      for i=2,#components do
	 local nextcomponent = compile_utf8.compile_codepoint_range(components[i], as_peg)
	 if as_peg then
	    result = result + nextcomponent	    -- lpeg +
	 else
	    result = result .. " " .. nextcomponent
	 end
      end
      if #components > 1 then
	 return "{" .. result .. "}"
      else
	 return result
      end
   elseif op=="+" then
      -- "+" takes from 1..k args
      assert(range[2], 'no args supplied to "+"')
      local result = compile_utf8.compile_codepoint_range(range[2], as_peg)
      for i=3,#range do
	 local nextcomponent = compile_utf8.compile_codepoint_range(range[i], as_peg)
	 if as_peg then
	    result = result + nextcomponent	    -- lpeg +
	 else
	    result = result .. " / " .. nextcomponent
	 end
      end
      return result
   end
   error("unknown unicode range opcode: " .. tostring(range[1]))
end


return compile_utf8
