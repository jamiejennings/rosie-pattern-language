-- -*- Mode: Lua; -*-                                                                             
--
-- ucd.lua    Process the Unicode Character Database
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- The main "index" of Unicode characters is the file UnicodeData.txt.  Most of the file consists
-- of individual entries for each defined codepoint.  Such entries have a character name in the
-- second field that names the character, like these:
-- 
--     0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;
--     0042;LATIN CAPITAL LETTER B;Lu;0;L;;;;;N;;;;0062;
--     0043;LATIN CAPITAL LETTER C;Lu;0;L;;;;;N;;;;0063;
-- Note that a character name cannot have "<" or ">" in it.
-- 
-- Other entries in UnicodeData.txt declare the start or end of a range of codepoints.  They look
-- like this:
-- 
--     3400;<CJK Ideograph Extension A, First>;Lo;0;L;;;;;N;;;;;
--     4DB5;<CJK Ideograph Extension A, Last>;Lo;0;L;;;;;N;;;;;
-- 
-- We will call these "defined ranges", to distinguish them from codepoint ranges that we
-- compute ourselves.
-- 
-- References:
-- 
-- [UnicodeData.txt](http://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt)
-- [Explanation of fields of UnicodeData.txt](http://www.unicode.org/reports/tr44/tr44-18.html#UnicodeData.txt)
--
-- Fields of UnicodeData.txt:
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


local ucd = {}
local util = dofile("util.lua")
local list = import("list")
local violation = import("violation")

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

local function loadUnicodeData(engine, filename)
   print("Reading UnicodeData.txt")
   local character_data = {n = 0; max_codepoint = 0}
   local defined_ranges = {n = 0}
   local parser, errs = engine:compile("UnicodeData_line")
   if not parser then
      error(table.concat(list.map(violation.tostring, errs), "\n"))
   end
   local nl = util.make_nextline_function(filename)
   local i = 1
   local line = nl()
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

function ucd.processUnicodeData(engine, filename)
   local character_db, defined_ranges = loadUnicodeData(engine, filename)
   return character_db
end


return ucd
