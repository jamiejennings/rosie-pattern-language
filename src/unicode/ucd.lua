-- -*- Mode: Lua; -*-                                                                             
--
-- ucd.lua    Process the Unicode Character Database
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings



--[[

-- NOTE regarding Reserved, Unassigned, Private Use, and Non-Characters:
--
-- Reserved characters and Unassigned characters are the same.  They are valid codepoints which
-- happen to be unassigned.  They are NOT listed in UnicodeData.txt.  They are NOT a member of any
-- defined General Category
--
-- Private Use character ranges are listed in UnicodeData.txt, so we get those ranges directly.
--
-- Non-Characters are permanently reserved for internal use, i.e. they will never be assigned.
-- They are a small fixed list, and are NOT listed in UnicodeData.txt.  Because the list is fixed,
-- we define it manually in this code.

-- What I am calling "defined ranges" appear in UnicodeData.txt like this:
    -- bash-3.2$ grep '\(First\)\|\(Last\)' UnicodeData.txt
    -- 3400;<CJK Ideograph Extension A, First>;Lo;0;L;;;;;N;;;;;
    -- 4DB5;<CJK Ideograph Extension A, Last>;Lo;0;L;;;;;N;;;;;
    -- 4E00;<CJK Ideograph, First>;Lo;0;L;;;;;N;;;;;
    -- 9FD5;<CJK Ideograph, Last>;Lo;0;L;;;;;N;;;;;
    -- AC00;<Hangul Syllable, First>;Lo;0;L;;;;;N;;;;;
    -- D7A3;<Hangul Syllable, Last>;Lo;0;L;;;;;N;;;;;
    -- ...
-- Whereas other entries in UnicodeData.txt represent a single codepoint and have names that
-- do not have the format "<name, First>" or "<name, Last>".

-- [UnicodeData.txt](http://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt)
-- [Explanation of fields of UnicodeData.txt](http://www.unicode.org/reports/tr44/tr44-18.html#UnicodeData.txt)
--
-- Fields:
-- (0) Codepoint in hex
-- (1) Name
-- (2) General Category
-- (3) Canonical Combining Class
-- (4) Bidi Class
-- (5) Decomposition Type and Mapping
-- (6,7,8) Numeric Type and Value
-- (9) Bidi Mirrored
-- (10,11) Obsolete
-- (12) Simple Uppercase Mapping
-- (13) Simple Lowercase Mapping
-- (14) Simple Titlecase Mapping


      

-- [General Categories](http://www.unicode.org/reports/tr44/tr44-18.html#General_Category_Values)
-- In that table are these derived categories:
-- LC	Cased_Letter	Lu | Ll | Lt
-- L	Letter	Lu | Ll | Lt | Lm | Lo
-- M	Mark	Mn | Mc | Me
-- N	Number	Nd | Nl | No
-- P	Punctuation	Pc | Pd | Ps | Pe | Pi | Pf | Po
-- S	Symbol	Sm | Sc | Sk | So
-- Z	Separator	Zs | Zl | Zp
-- C	Other	Cc | Cf | Cs | Co | Cn  (Note: Cn means "unassigned" and won't appear in db)


-- There are two sources of ranges: the list of single codepoints in db[code], and the list of
-- already-defined ranges in db.defined_ranges[].  


--return ucd

--]]

local ucd = {}
local rosie = require("rosie")
local compile_utf8 = dofile("compile-utf8.lua")
local util = dofile("util.lua")

local codepoint_range = compile_utf8.codepoint_range
local compile_codepoint_range = compile_utf8.compile_codepoint_range

local engine = rosie.engine.new(); engine:loadfile("ucd.rpl")

local manually_defined_ranges = {
--    { 0xFDD0,   0xFDEF, {gc="Cn"} },
--    { 0xFFFE,   0xFFFF, {gc="Cn"} },
--    { 0x1FFFE,  0x1FFFF, {gc="Cn"} },
--    { 0x2FFFE,  0x2FFFF, {gc="Cn"} },
--    { 0x3FFFE,  0x3FFFF, {gc="Cn"} },
--    { 0x4FFFE,  0x4FFFF, {gc="Cn"} },
--    { 0x5FFFE,  0x5FFFF, {gc="Cn"} },
--    { 0x6FFFE,  0x6FFFF, {gc="Cn"} },
--    { 0x7FFFE,  0x7FFFF, {gc="Cn"} },
--    { 0x8FFFE,  0x8FFFF, {gc="Cn"} },
--    { 0x9FFFE,  0x9FFFF, {gc="Cn"} },
--    { 0xAFFFE,  0xAFFFF, {gc="Cn"} },
--    { 0xBFFFE,  0xBFFFF, {gc="Cn"} },
--    { 0xCFFFE,  0xCFFFF, {gc="Cn"} },
--    { 0xDFFFE,  0xDFFFF, {gc="Cn"} },
--    { 0xEFFFE,  0xEFFFF, {gc="Cn"} },
--    { 0xFFFFE,  0xFFFFF, {gc="Cn"} },
--    { 0x10FFFE, 0x10FFFF,{gc="Cn"} }
}

local function storeUnicodeData(data, character_data, defined_ranges)
   assert(data.type=='UnicodeData_line')
   data = data.subs[1]
   if data.type=='comment' or data.type=='blank_line' then return; end
   assert(data.type=='UnicodeData')
   assert(data.subs[1].type=='codePoint')
   local code = tonumber(data.subs[1].data, 16)
   character_data.max_codepoint = math.max(code, character_data.max_codepoint)
   assert(code)
   local character_name = assert(data.subs[2])
   local gc = assert(data.subs[3].data)
   local upper = data.subs[13] and data.subs[13].data
   local lower = data.subs[14] and data.subs[14].data
   local title = data.subs[15] and data.subs[15].data
   local fields_to_save = {gc=gc, upper=upper, lower=lower, title=title}
   if character_name.subs then			    -- defined_range
      character_name = character_name.subs[1]
      local rangeName = character_name.subs[1]
      assert(rangeName.type=='defined_range_name')
      local rangeEdge = character_name.subs[2]
      assert(rangeEdge.type=='first_last')
      if rangeEdge.data=="First" then
	 table.insert(defined_ranges, {code, nil, fields_to_save, rangeName.data})
      elseif rangeEdge.data=="Last" then
	 local entry = defined_ranges[#defined_ranges]
	 assert(entry[4]==rangeName.data,
		string.format("previous entry was not the First that matches this Last: code=%X, name=%s",
			      code, fields_to_save[1]))
	 entry[2] = code
	 defined_ranges.n = defined_ranges.n + 1
      else
	 error("range edge not 'First' or 'Last': code=%X, name=%s first_last=%s",
	       code, character_name, tostring(rangeEdge))
      end -- switch on rangeEdge
   else
      character_data[code] = fields_to_save
      character_data.n = character_data.n + 1
   end
end

local function loadUnicodeData(filename)
   print("Reading UnicodeData.txt")
   local character_data = {n = 0; max_codepoint = 0}
   local defined_ranges = {n = 0}
   local parser = engine:compile("UnicodeData_line")
   local nl = util.make_nextline_function(filename)
   local line = nl(); i = 1;
   while(line) do
      local data = parser:match(line)
      if not data then
	 print(string.format("Parse error at line %d: %q", i, line))
      else
	 storeUnicodeData(data, character_data, defined_ranges)
      end
      line = nl(); i = i+1;
   end
   print(tostring(character_data.n) .. " individual codepoints processed")
   print(tostring(defined_ranges.n) .. " defined ranges processed")
   return character_data, defined_ranges
end

-- -----------------------------------------------------------------------------
-- Calculate ranges for each general category
-- -----------------------------------------------------------------------------

local function ranges1(character_data, cat, start, results)
   local last = 0x10FFFF
   if start > last then return results; end
   -- Find next range of chars that are in this category
   local codepoint = start;
   local start, finish;
   while ((codepoint <= last) and
          (not character_data[codepoint] or
	   character_data[codepoint].gc ~=cat)) do
      codepoint = codepoint + 1
   end
   if (codepoint > last) then return results; end
   -- Found start of range.  Now find end of range.
   start = codepoint
   codepoint = codepoint + 1
   while ((codepoint <= last) and
          character_data[codepoint] and
	  character_data[codepoint].gc==cat) do
      codepoint = codepoint + 1
   end
   if codepoint > last then
      finish = last;
   else
      finish = codepoint - 1;
   end
   table.insert(results, {start,finish})
   return ranges1(character_data, cat, finish+1, results)
end

-- From the individual character data, derive a set of ranges for a given General Category
local function ranges_from_character_data(character_data, cat)
   return ranges1(character_data, cat, 0, {})
end

-- N.B. This function is NOT a fast lookup.  It is relatively slow (though there are only a few
-- dozen defined ranges) because it does data validation while computing the result.
local function codepoint_to_defined_range(defined_ranges, manually_defined_ranges, cp)
   -- Check both defined_ranges and manually_defined_ranges.
   -- Error case if cp is in more than one such range.
   local found_range
   for _,range in ipairs(defined_ranges) do
      local start, finish, fields = range[1], range[2], range[3]
      local category = fields.gc
      if (start <= cp) and (cp <= finish) then
	 assert(not found_range)
	 found_range = range
      end
   end
   for _,range in ipairs(manually_defined_ranges) do
      local start, finish, fields = range[1], range[2], range[3]
      local category = fields.gc
      if (start <= cp) and (cp <= finish) then
	 assert(not found_range)
	 found_range = range
      end
   end
   return found_range
end

local function find_unassigned_codepoints(character_data, defined_ranges, manually_defined_ranges)
   -- Returns a set of ranges {n, m}
   local result = {}
   local start, finish
   for code = 0x0, 0x10FFFF do
      if ((not character_data[code]) and
          (not codepoint_to_defined_range(defined_ranges, manually_defined_ranges, code))) then
	 -- this codepoint is unassigned
	 if not start then start=code; finish=code;
	 elseif code==finish+1 then finish=code;
	 else
	    table.insert(result, {start, finish})
	    start, finish = code, nil
	 end
      else
	 -- This codepoint is assigned
	 if start then
	    -- Save the range we were working on
	    table.insert(result, {start, finish})
	    -- Start over
	    start, finish = nil, nil
	 end
      end
   end
   return result
end

-- N.B. the ranges must be returned in sorted order for later processing to work.
-- Supply an argument of nil to calculate all the unassigned character ranges.
local function compute_ranges(character_data, defined_ranges, manually_defined_ranges, cat)
   if cat==nil then
      return find_unassigned_codepoints(character_data, defined_ranges, manually_defined_ranges)
   end
   assert(type(cat)=="string", "Category not a string: " .. tostring(cat))
   -- First derive ranges from all the single codepoint entries in UnicodeData.txt
   local ranges = ranges_from_character_data(character_data, cat)
   -- Next, gather the "defined ranges" of UnicodeData.txt
   local defined_ranges = util.filter_ranges(defined_ranges, cat)
   -- Next, gather any manually defined ranges for this category
   local manual_ranges = util.filter_ranges(manually_defined_ranges, cat)
   -- Merge the three
   return util.merge_ranges(ranges, util.merge_ranges(defined_ranges, manual_ranges, cat), cat)
end

-- -----------------------------------------------------------------------------
-- Extract the list of general category names, and generate ranges for each
-- -----------------------------------------------------------------------------

local function extract_categories(character_data, defined_ranges, manually_defined_ranges)
   print("Generating list of general categories")
   local cats = {}
   local new = {}
   for codepoint, fields in pairs(character_data) do
      if type(codepoint)=="number" then
	 local category = fields.gc
	 cats[category] = (cats[category] or 0) + 1;
	 new[category] = true;
      end
   end
   print("Categories from individual character data:")
   local i = 0
   for c,_ in pairs(new) do print("", c, cats[c]); i = i + 1; end
   print(i, "categories")
   new = {}
   for _, range in ipairs(defined_ranges) do
      local start, finish, fields = range[1], range[2], range[3]
      local category = fields.gc
      cats[category] = (cats[category] or 0) + (finish-start+1)
      new[category] = true;
   end
   print("Categories from defined_ranges:")
   i = 0
   for c,_ in pairs(new) do print("", c, cats[c]); i = i + 1; end
   print(i, "categories")
   new = {}
   for _, range in ipairs(manually_defined_ranges) do
      local start, finish, fields = range[1], range[2], range[3]
      local category = fields.gc
      cats[category] = (cats[category] or 0) + (finish-start+1)
      new[category] = true;
   end
   print("Categories from manually defined ranges:")
   i = 0
   for c,_ in pairs(new) do print("", c, cats[c]); i = i + 1; end
   print(i, "categories")
   return cats
end

-- -----------------------------------------------------------------------------
-- Compile the ranges
-- -----------------------------------------------------------------------------

local function compile_all_ranges(range_table)
   local patterns = {}
   for cat, ranges in pairs(range_table) do
      local utf8_range = {"+"}
      for _,range in ipairs(ranges) do
	 table.insert(utf8_range, codepoint_range(range[1], range[2]))
      end
      if #ranges > 0 then
	 patterns[cat] = compile_codepoint_range(utf8_range)
      else
	 print("ERROR", cat, "has no ranges")
      end
   end
   return patterns
end

-- -----------------------------------------------------------------------------
-- Testing the patterns produced from UnicodeData
-- -----------------------------------------------------------------------------

local function test_defined_codepoints_against_all_patterns(character_data, patterns)
   -- First, a "sniff test" to make sure we are ready to run this test
   assert(patterns, "general category patterns have not been compiled")
   local Lu = patterns.Lu
   assert(type(Lu)=="userdata", "something wrong with contents of patterns.Lu")
   assert(not Lu:match("a"), "Lu should only match UPPER CASE")
   assert(not Lu:match(" "), "Lu should only match UPPER CASE")
   assert(not Lu:match("!"), "Lu should only match UPPER CASE")
   assert(Lu:match("X"), "Lu must match UPPER CASE")
   -- Now the full test against all unicode characters
   local j=0
   for cat_name, cat_peg in pairs(patterns) do
      io.write("Testing category: " .. cat_name .. " ")
      j=j+1
      local i=0;
      local err=0;
      for codepoint, fields in pairs(character_data) do
	 if type(codepoint)~="number" then break; end
	 i=i+1;
	 local match = cat_peg:match(utf8.char(codepoint))
	 if (cat_name==fields.gc) and (not match) then
	    print(string.format("Pattern failure: %s failed (%X %s)", cat_name, codepoint, fields.gc))
	    err=err+1
	 elseif (cat_name~=fields.gc) and match then
	    print(string.format("Pattern failure: %s matched (%X %s)", cat_name, codepoint, fields.gc))
	    err=err+1
	 end
      end -- for each codepoint
      io.write(tostring(i), " characters tested, ", tostring(err), " failures\n")
   end -- for each general category
   io.write(tostring(j), " Categories tested\n")
end


-- -----------------------------------------------------------------------------
-- Top level
-- -----------------------------------------------------------------------------

function ucd.processUnicodeData(filename)
   local character_db, defined_ranges = loadUnicodeData(filename)
   local cats = extract_categories(character_db, defined_ranges, manually_defined_ranges)
   local ranges = {}
   local i = 0
   for cat, catsize in pairs(cats) do
      assert(not ranges[cat], "Duplicate category name: " .. cat)
      ranges[cat] = compute_ranges(character_db, defined_ranges, manually_defined_ranges, cat)
      print("Category", cat, "has", #ranges[cat], "ranges")
      i = i + 1
   end
   -- Unicode TR#44, Section 5.7.1 "the value gc=Cn does not actually occur in UnicodeData.txt,
   -- because that data file does not list unassigned code points."
   assert(not ranges["Cn"])
   ranges["Cn"] = compute_ranges(character_db, defined_ranges, manually_defined_ranges, nil)
   print("Category", "Cn", "has", #ranges["Cn"], "ranges")
   i = i + 1
   print("Compiling ranges for each general category")
   patterns = compile_all_ranges(ranges)
   print(i, "general categories compiled")
   test_defined_codepoints_against_all_patterns(character_db, patterns)
   return character_db, patterns
end


return ucd
