-- -*- Mode: Lua; -*-                                                                             
--
-- ucd.lua    Process the Unicode Character Database
--
-- © Copyright IBM Corporation 2016.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- Reserved, Unassigned, Private Use, and Non Characters
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

lpeg = require "lpeg"
--dofile("utf8-range.lua")

function run()
   init()
   load()
   categories()
   compute_all_ranges()
   print("Compiling all of the ranges in 'general_category_ranges' to lpeg patterns, storing in global 'general_category_patterns'")
   general_category_patterns = compile_all_ranges(general_category_ranges)
   test_all_codepoints_against_all_categories()
end


-- > f = io.open("/Users/jjennings/Work/Dev/private/rosie-plus/unicode/Nd.txt")
-- > entry = f:read("l")
-- > entry
-- 0030;DIGIT ZERO;Nd;0;EN;;0;0;0;N;;;;;
-- >
      
-- > ucdpat1 = lpeg.C((lpeg.P(1)-lpeg.S(";"))^0)
-- > ucdpatn = lpeg.S(";") * ucdpat1
-- > (ucdpat1 * ucdpatn^3):match(entry)
-- 0030	DIGIT ZERO	Nd	0	EN		0	0	0	N					
-- > (ucdpat1 * ucdpatn^1):match(entry)
-- 0030	DIGIT ZERO	Nd	0	EN		0	0	0	N					
-- >

-- [UCD database version 9.0.0](http://www.unicode.org/versions/Unicode9.0.0/)
-- [UCD database files](http://www.unicode.org/Public/UCD/latest/ucd/)
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



ucdpat1 = lpeg.C((lpeg.P(1)-lpeg.S(";"))^0)
ucdpatn = lpeg.S(";") * ucdpat1
ucd_peg = (ucdpat1 * ucdpatn^12)

name_is_range = lpeg.Ct(lpeg.S"<" *
			lpeg.C((lpeg.P(1)-lpeg.S",>")^1) *
		        (lpeg.S"," * (lpeg.S" ")^0 * lpeg.C((lpeg.P(1)-lpeg.S">")^1))^-1 * 
		        lpeg.S">")

function init()
   print("Initializing globals 'db' and 'cats' with null values")
   db = {defined_ranges={}}
   cats = {}
end

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

function store(code, ...)
   if not code then return false; end
   local fields = {...}
   code = tonumber(code, 16)
   local data_to_save = fields[2];		    -- save only the general category
   local range = name_is_range:match(fields[1])
   local name, firstlast
   if range then
      name = range[1]
      firstlast = range[2]
   end
   if firstlast then
      -- this line in UnicodeData.txt is the start or end of a range
      if firstlast=="First" then
	 table.insert(db.defined_ranges, {code, nil, data_to_save, name})
      elseif firstlast=="Last" then
	 local entry = db.defined_ranges[#db.defined_ranges]
	 assert(entry[4]==name,
		string.format("previous entry was not the First that matches this Last: code=%X, name=%s",
			      code, fields[1]))
	 entry[2] = code
      else
	 error("Range indicator not 'First' or 'Last': code=%X, name=%s first/last=%s",
	       code, fields[1], tostring(firstlast))
      end -- switch on firstlast
   else
      -- this line is not the First or Last of a defined range
      db[code] = data_to_save
   end
   db.max = math.max(code, (db.max or -1))
   return true
end
      
-- TO DO:
-- Script names?  E.g. 'Greek', 'Latin'
-- Combine script names with general categories, e.g. 'Greek' script and 'Lu' (upper case)
-- Create unicode_name package? (Or unicode.name) in which character names are bound to patterns that recognize them?


function load()
   print("Loading data from UnicodeData.txt into global variable 'db'")
   nl = io.lines("/Users/jjennings/Work/Dev/private/rosie-plus/unicode/UCD/UnicodeData.txt")
   line = nl(); i = 1;
   while(line) do
      if not(store(ucd_peg:match(line))) then 
	 print(string.format("Parse error at line %d: %q", i, line))
      end
      line = nl(); i = i+1;
   end
   db.n = i-1
   assert(db.max==0x10FFFD)			    -- highest codepoint value
end

function memtest(thunk)
   mem1 = (function() collectgarbage("collect"); return collectgarbage("count"); end)()
   thunk()
   mem2 = (function() collectgarbage("collect"); return collectgarbage("count"); end)()
   return mem2-mem1, "Kb"
end

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

manually_defined_ranges = {
   { 0xFDD0, 0xFDEF, "Cn" },
   { 0xFFFE, 0xFFFF, "Cn" },
   { 0x1FFFE, 0x1FFFF, "Cn" },
   { 0x2FFFE, 0x2FFFF, "Cn" },
   { 0x3FFFE, 0x3FFFF, "Cn" },
   { 0x4FFFE, 0x4FFFF, "Cn" },
   { 0x5FFFE, 0x5FFFF, "Cn" },
   { 0x6FFFE, 0x6FFFF, "Cn" },
   { 0x7FFFE, 0x7FFFF, "Cn" },
   { 0x8FFFE, 0x8FFFF, "Cn" },
   { 0x9FFFE, 0x9FFFF, "Cn" },
   { 0xAFFFE, 0xAFFFF, "Cn" },
   { 0xBFFFE, 0xBFFFF, "Cn" },
   { 0xCFFFE, 0xCFFFF, "Cn" },
   { 0xDFFFE, 0xDFFFF, "Cn" },
   { 0xEFFFE, 0xEFFFF, "Cn" },
   { 0xFFFFE, 0xFFFFF, "Cn" },
   { 0x10FFFE, 0x10FFFF, "Cn" }
}


-- Create a list of all the General Categories that are present in the data set:
function categories()
   print("Generating list of categories in global variable 'cats'")
   local new = {}
   for codepoint, category in pairs(db) do
      if type(codepoint)=="number" then
	 cats[category] = (cats[category] or 0) + 1;
	 new[category] = true;
      end
   end
   print("", "Categories from individual codepoints in db:")
   for c,_ in pairs(new) do print("", "", c); end
   new = {}
   for _, range in ipairs(db.defined_ranges) do
      local start, finish, category = range[1], range[2], range[3]
      cats[category] = (cats[category] or 0) + (finish-start+1)
      new[category] = true;
   end
   print("", "Categories from db.defined_ranges:")
   for c,_ in pairs(new) do print("", "", c); end
   new = {}
   for _, range in ipairs(manually_defined_ranges) do
      local start, finish, category = range[1], range[2], range[3]
      cats[category] = (cats[category] or 0) + (finish-start+1)
      new[category] = true;
   end
   print("", "Categories from manually defined ranges in global 'manually_defined_ranges':")
   for c,_ in pairs(new) do print("", "", c); end
end

-- There are two sources of ranges: the list of single codepoints in db[code], and the list of
-- already-defined ranges in db.defined_ranges[].  From the single codepoints, we derive a set of
-- ranges for a given General Category as follows:
function derive_ranges(cat, optional_start, results)
   optional_start = optional_start or 0
   results = results or {}
   local last = math.max(db.max, 0x10FFFF)	    -- makes Cn come out right
   if optional_start > last then return results; end
   -- find next range of chars that are in this category
   local start, finish;
   local codepoint = optional_start;
   while (codepoint <= last) and db[codepoint]~=cat do codepoint = codepoint + 1; end
   if codepoint <= last then
      -- found start of range.  now find end of range.
      start = codepoint
      codepoint = codepoint + 1
      while (codepoint <= last) and db[codepoint]==cat do codepoint = codepoint + 1; end
      if codepoint > last then
	 finish = last;
      else
	 finish = codepoint - 1;
      end
      table.insert(results, {start,finish})
      return derive_ranges(cat, finish+1, results)
   else
      return results
   end
end

-- N.B. This function is NOT a fast lookup.  It is relatively slow (though there are only a few
-- dozen defined ranges) because it does data validation while computing the result.
function codepoint_to_defined_range(cp)
   -- Check both db.defined_ranges and manually_defined_ranges
   -- Error case if cp is in more than one such range
   local found_range
   for _,range in ipairs(db.defined_ranges) do
      local start, finish, category = range[1], range[2], range[3]
      if (start <= cp) and (cp <= finish) then
	 assert(not found_range)
	 found_range = range
      end
   end
   for _,range in ipairs(manually_defined_ranges) do
      local start, finish, category = range[1], range[2], range[3]
      if (start <= cp) and (cp <= finish) then
	 assert(not found_range)
	 found_range = range
      end
   end
   return found_range
end

function find_unassigned_codepoints()
   -- returns a set of ranges {n, m}
   local result = {}
   local start, finish
   for code = 0x0, 0x10FFFF do
      if (not db[code]) and (not codepoint_to_defined_range(code)) then
	 -- this codepoint is unassigned
	 if not start then start=code; finish=code;
	 elseif code==finish+1 then finish=code;
	 else
	    table.insert(result, {start, finish})
	    start, finish = code, nil
	 end
      else
	 -- this codepoint is assigned
	 if start then
	    -- save the range we were working on
	    table.insert(result, {start, finish})
	    -- start over
	    start, finish = nil, nil
	 end
      end
   end
   return result
end

-- N.B. the ranges will NOT necessarily be in sorted order, because the "defined ranges" are
-- appended at the bottom of the ranges we derived.
-- Supply an argument of nil to calculate all the unassigned character ranges.
function compute_ranges(cat)
   if cat==nil then
      return find_unassigned_codepoints()
   end
   assert(cat, "Category not a string: " .. tostring(cat))
   assert(cats[cat], "Category not listed in categories table: " .. tostring(cat))
   -- First derive ranges from all the single codepoint entries in UnicodeData.txt
   local results = derive_ranges(cat)
   -- Next, add in the "defined ranges" of UnicodeData.txt
   for _,range in ipairs(db.defined_ranges) do
      local start, finish, category = range[1], range[2], range[3]
      if category==cat then table.insert(results, {start, finish}); end
   end
   -- Next, add in the manually defined ranges
   for _,range in ipairs(manually_defined_ranges) do
      local start, finish, category = range[1], range[2], range[3]
      if category==cat then table.insert(results, {start, finish}); end
   end
   return results
end

-- Create range entries for each defined General Category, as well as UNASSIGNED
-- !@# TODO: Should the UNASSIGNED codepoints be assigned the Cn property?
function compute_all_ranges()
   print("For each category in 'cats', plus UNASSIGNED, generating ranges and storing in global 'general_category_ranges'")
   general_category_ranges = {}
   for cat,_ in pairs(cats) do
      assert(not general_category_ranges[cat], "Duplicate category name: " .. cat)
      general_category_ranges[cat] = compute_ranges(cat)
   end
   general_category_ranges["UNASSIGNED"] = compute_ranges(nil);
end

-- Turn the ranges into lpeg patterns
function compile_all_ranges(range_table)
   local patterns = {}
   for cat,ranges in pairs(range_table) do
      local utf8_range = {"+"}
      for _,range in ipairs(ranges) do
	 table.insert(utf8_range, codepoint_range(range[1], range[2]))
      end
      patterns[cat] = compile_codepoint_range(utf8_range)
   end
   return patterns
end

function test_all_codepoints_against_all_categories()
   -- sniff test to make sure we are ready to run this test
   assert(general_category_patterns, "general category patterns have not been compiled")
   local Lu = general_category_patterns.Lu
   assert(type(Lu)=="userdata", "something wrong with contents of general_category_patterns.Lu")
   assert(not Lu:match("a"), "Lu should only match UPPER CASE")
   assert(not Lu:match(" "), "Lu should only match UPPER CASE")
   assert(not Lu:match("!"), "Lu should only match UPPER CASE")
   assert(Lu:match("X"), "Lu must match UPPER CASE")
   -- ok, now let's do a full test against all unicode characters
   local j=0
   for cat_name, cat_peg in pairs(general_category_patterns) do
      io.write("Testing category: " .. cat_name .. " ")
      j=j+1
      local i=0;
      local err=0;
      for codepoint, db_cat in pairs(db) do
	 if type(codepoint)~="number" then break; end
	 i=i+1;
	 local match = cat_peg:match(utf8.char(codepoint))
	 if (cat_name==db_cat) and (not match) then
	    print(string.format("\nPattern failure: %s failed (%X %s)", cat_name, codepoint, db_cat))
	    err=err+1
	 elseif (cat_name~=db_cat) and match then
	    print(string.format("\nPattern failure: %s matched (%X %s)", cat_name, codepoint, db_cat))
	    err=err+1
	 end
      end -- for each codepoint
      io.write(tostring(i), " characters tested, ", tostring(err), " failures\n")
   end -- for each general category
   io.write(tostring(j), " Categories tested\n")
end



----------------------------------------------------------------------------------------
-- Dinky utilities
----------------------------------------------------------------------------------------

function printranges(range_table)
   local t = range_table
   for r = 1,#t do print(string.format("%05x - %05x", t[r][1], t[r][2])); end
end

function display_utf8_string(s, optional_base)
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
