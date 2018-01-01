-- -*- Mode: Lua; -*-                                                                             
--
-- unicode-utils.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local util = {}


function util.make_nextline_function(fn)
   return io.lines(UCD_DIR .. fn)
end


-- A range is a pair of integers (low, high), low <= high.
-- Tables of defined ranges are lists of tuples: (low, high, data), data must have gc field.

function util.filter_ranges(defined_ranges, cat)
   local results = {}
   for _,range in ipairs(defined_ranges) do
      local start, finish, fields = range[1], range[2], range[3]
      local category = fields.gc
      if category==cat then table.insert(results, {start, finish}); end
   end
   return results
end

function util.merge_ranges(R1, R2, value_name)
   local result = {}
   local idx, r1, r2 = 1, 1, 1
   local more_to_compare = R1[r1] and R2[r2]
   while more_to_compare do
      local next_range
      if R1[r1][1] < R2[r2][1] then
	 next_range = R1[r1]
	 r1 = r1 + 1
      elseif R2[r2][1] < R1[r1][1] then
	 next_range = R2[r2]
	 r2 = r2 + 1
      else
	 error("overlapping ranges")
      end
      result[idx] = next_range
      if idx > 1 then
	 assert(result[idx-1][2] < result[idx][1])
      end
      idx = idx + 1
      more_to_compare = R1[r1] and R2[r2]
   end
   if R1[r1] then
      table.move(R1, r1, #R1, idx, result)
   elseif R2[r2] then
      table.move(R2, r2, #R2, idx, result)
   end
   return result
end

----------------------------------------------------------------------------------------
-- Dinky utilities
----------------------------------------------------------------------------------------

function util.printranges(range_table)
   local t = range_table
   for r = 1,#t do print(string.format("%05x - %05x", t[r][1], t[r][2])); end
end

function util.display_utf8_string(s, optional_base)
   optional_base = optional_base or 16
   local fmtcode = ({[8]="03o", [10]="3d", [16]="02x"})[optional_base]
   if not fmtcode then error("optional 2nd argument (base) not 8, 10, or 16"); end
   io.write("|")
   -- utf8.codes will validate that the string is indeed utf8
   for p, cp in utf8.codes(s) do
      local char = utf8.char(cp)		    -- re-encode
      for i=1,#char do
	 io.write(string.format(" %"..fmtcode, string.byte(char, i)))
      end
      io.write(" |")
   end
   io.write("\n")
end


return util
