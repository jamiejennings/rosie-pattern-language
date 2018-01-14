-- -*- Mode: Lua; -*-                                                                             
--
-- unicode-utils.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local util = {}

local compile_utf8 = dofile("compile-utf8.lua")
local codepoint_range = compile_utf8.codepoint_range
local compile_codepoint_range = compile_utf8.compile_codepoint_range


function util.make_nextline_function(fn)
   return io.lines(UCD_DIR .. fn)
end

-- Note:   When comparing block names, casing, whitespace, hyphens,
--         and underbars are ignored.
--         For example, "Latin Extended-A" and "latin extended a" are equivalent.
function util.canonicalize_value(val)
   return (val:gsub(' ', '_'):gsub('-','_'))
end

-- -----------------------------------------------------------------------------
-- Compile the ranges
-- -----------------------------------------------------------------------------

function util.compile_all_ranges(range_table, as_peg)
   local patterns = {}
   for cat, ranges in pairs(range_table) do
      local utf8_range = {"+"}
      for _,range in ipairs(ranges) do
	 table.insert(utf8_range, codepoint_range(range[1], range[2]))
      end
      if #ranges > 0 then
	 patterns[cat] = compile_codepoint_range(utf8_range, as_peg)
      else
	 print("ERROR", cat, "has no ranges")
      end
   end
   return patterns
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
